#!/usr/bin/env bash
# Confirms the Service, DestinationRule and VirtualService fields, that the
# shuttle's proxy holds the connection settings, that no workload was changed,
# and - the part that matters - that live requests behave: the failing zone-a
# probe is ejected so every request returns 200 from probe-zone-b, and a slow
# request fails with 504 inside the route timeout.

set -u

NS="starfleet"
FQDN="probe.starfleet.svc.cluster.local"

fail() { echo "FAIL: $*"; exit 1; }

dr_field() { kubectl -n "$NS" get destinationrule probe -o jsonpath="{$1}" 2>/dev/null; }
vs_field() { kubectl -n "$NS" get virtualservice probe -o jsonpath="{$1}" 2>/dev/null; }

# --- 0. the environment is still what the lab handed over -------------------
for d in shuttle probe-zone-a-damaged probe-zone-b; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Keep every deployment running, the failing pod included: the proxy has to eject it"
done
deploy_count=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$deploy_count" -eq 3 ]] || fail "$NS holds $deploy_count deployments, expected exactly 3 - do not add or remove deployments"
for n in $(kubectl get nodes -o name); do
  zone=$(kubectl get "$n" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}')
  region=$(kubectl get "$n" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/region}')
  [[ "$region/$zone" == "local/zone-a" ]] || fail "node $n is now in '$region/$zone', expected local/zone-a. Leave the node labels alone"
done
shuttle_loc=$(kubectl -n "$NS" get deployment shuttle -o jsonpath='{.spec.template.metadata.labels.istio-locality}' 2>/dev/null)
[[ -z "$shuttle_loc" ]] || fail "the shuttle now carries istio-locality=$shuttle_loc. It must keep the node's locality, local/zone-a"
a_loc=$(kubectl -n "$NS" get deployment probe-zone-a-damaged -o jsonpath='{.spec.template.metadata.labels.istio-locality}' 2>/dev/null)
b_loc=$(kubectl -n "$NS" get deployment probe-zone-b -o jsonpath='{.spec.template.metadata.labels.istio-locality}' 2>/dev/null)
[[ "$a_loc" == "local.zone-a" && "$b_loc" == "local.zone-b" ]] || fail "the probe localities changed (zone-a='$a_loc', zone-b='$b_loc'). Leave the pod localities alone"

# --- 1. the Service ----------------------------------------------------------
td=$(kubectl -n "$NS" get service probe -o jsonpath='{.spec.trafficDistribution}' 2>/dev/null)
[[ "$td" == "PreferClose" ]] || fail "the probe Service has trafficDistribution '$td', expected PreferClose (a field of the Service, not of a DestinationRule)"
selector=$(kubectl -n "$NS" get service probe -o jsonpath='{.spec.selector}' 2>/dev/null)
[[ "$selector" == '{"app":"probe"}' ]] || fail "the probe Service selector is '$selector', expected {\"app\":\"probe\"}"
port=$(kubectl -n "$NS" get service probe -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
[[ "$port" == "8000" ]] || fail "the probe Service port is '$port', expected 8000"

# --- 2. the DestinationRule --------------------------------------------------
kubectl -n "$NS" get destinationrule probe >/dev/null 2>&1 || fail "DestinationRule 'probe' not found in $NS"
dr_count=$(kubectl -n "$NS" get destinationrule -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$dr_count" -eq 1 ]] || fail "$NS holds $dr_count DestinationRules, expected exactly 1 (named probe)"
case "$(dr_field .spec.host)" in
  probe|"$FQDN") ;;
  *) fail "the DestinationRule host is '$(dr_field .spec.host)', expected probe" ;;
esac
[[ "$(dr_field .spec.trafficPolicy.outlierDetection.consecutive5xxErrors)" == "2" ]] || fail "outlierDetection.consecutive5xxErrors must be 2"
[[ "$(dr_field .spec.trafficPolicy.outlierDetection.interval)" == "5s" ]] || fail "outlierDetection.interval must be 5s"
[[ "$(dr_field .spec.trafficPolicy.outlierDetection.baseEjectionTime)" == "30s" ]] || fail "outlierDetection.baseEjectionTime must be 30s"
[[ "$(dr_field .spec.trafficPolicy.outlierDetection.maxEjectionPercent)" == "100" ]] || fail "outlierDetection.maxEjectionPercent must be 100. With the default of 10 percent, one of two endpoints can never be ejected"
[[ -z "$(dr_field .spec.trafficPolicy.loadBalancer.localityLbSetting)" ]] || fail "the DestinationRule sets localityLbSetting. The preference must come from the Service field, so remove it"

# --- 3. the VirtualService ---------------------------------------------------
kubectl -n "$NS" get virtualservice probe >/dev/null 2>&1 || fail "VirtualService 'probe' not found in $NS"
vs_count=$(kubectl -n "$NS" get virtualservice -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$vs_count" -eq 1 ]] || fail "$NS holds $vs_count VirtualServices, expected exactly 1 (named probe)"
[[ "$(vs_field .spec.hosts[0])" == "probe" ]] || fail "the VirtualService host is '$(vs_field .spec.hosts[0])', expected probe"
dest=$(vs_field .spec.http[0].route[0].destination.host)
case "$dest" in
  probe|"$FQDN") ;;
  *) fail "the VirtualService routes to '$dest', expected the probe host" ;;
esac
[[ "$(vs_field .spec.http[0].timeout)" == "3s" ]] || fail "the route timeout is '$(vs_field .spec.http[0].timeout)', expected 3s"
[[ "$(vs_field .spec.http[0].retries.attempts)" == "2" ]] || fail "retries.attempts is '$(vs_field .spec.http[0].retries.attempts)', expected 2"
[[ "$(vs_field .spec.http[0].retries.perTryTimeout)" == "1s" ]] || fail "retries.perTryTimeout is '$(vs_field .spec.http[0].retries.perTryTimeout)', expected 1s"
retry_on=$(vs_field .spec.http[0].retries.retryOn)
case "$retry_on" in
  *5xx*) ;;
  *) fail "retries.retryOn is '$retry_on', expected it to contain 5xx" ;;
esac

# --- 4. the shuttle's proxy holds the connection settings --------------------
cluster_json() {
  istioctl proxy-config cluster deploy/shuttle -n "$NS" --fqdn "$FQDN" --port 8000 -o json 2>/dev/null | tr -d ' \n\t'
}
checks=('"connectTimeout":"2s"' '"idleTimeout":"60s"' '"maxConnectionDuration":"300s"' '"keepaliveProbes":3' '"keepaliveTime":30' '"keepaliveInterval":10')
missing=""
for attempt in $(seq 1 30); do
  json=$(cluster_json)
  missing=""
  for c in "${checks[@]}"; do
    grep -qF "$c" <<<"$json" || missing="$missing $c"
  done
  [[ -z "$missing" ]] && break
  sleep 2
done
[[ -z "$missing" ]] || fail "the shuttle's proxy does not hold these values for $FQDN:$missing"

# --- 5. live behaviour -------------------------------------------------------
send_request() {  # prints "<status> <seconds> <body>"; retries only a failed kubectl exec
  local out t
  for t in 1 2 3; do
    out=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s -w ' %{http_code} %{time_total}' --max-time 15 "http://probe:8000$1" 2>/dev/null) && break
    sleep 1
  done
  echo "$out"
}

# Warm up: the first requests reach the failing pod and are retried while the
# proxy counts the errors. After two consecutive 5xx the proxy ejects it.
sleep 3
for i in $(seq 1 10); do send_request /hostname >/dev/null; done

# A slow request must fail with 504 after about the route timeout (3s).
slow=$(send_request /delay/5)
slow_code=$(tail -n1 <<<"$slow" | awk '{print $(NF-1)}')
slow_time=$(tail -n1 <<<"$slow" | awk '{print $NF}')
[[ "$slow_code" == "504" ]] || fail "GET /delay/5 returned status '$slow_code', expected 504 from the 3s route timeout"
awk -v t="$slow_time" 'BEGIN { exit !(t >= 2.5 && t <= 4.5) }' \
  || fail "GET /delay/5 failed after ${slow_time}s, expected about 3s (the route timeout)"

# Every request must now succeed and be answered by the healthy zone-b probe.
bad=0
zone_b=0
for i in $(seq 1 20); do
  out=$(send_request /hostname)
  code=$(tail -n1 <<<"$out" | awk '{print $(NF-1)}')
  [[ "$code" == "200" ]] || bad=$((bad + 1))
  grep -q 'probe-zone-b' <<<"$out" && zone_b=$((zone_b + 1))
done
[[ "$bad" -eq 0 ]] || fail "$bad of 20 requests did not return 200. The failing zone-a probe must be ejected, and the Service must prefer close endpoints so the proxy fails over to zone-b only after the ejection"
[[ "$zone_b" -eq 20 ]] || fail "only $zone_b of 20 requests were answered by probe-zone-b, expected all 20"

echo "PASS: Service, DestinationRule and VirtualService are correct, the proxy holds the connection settings, the failing zone-a probe is ejected so all 20 requests returned 200 from probe-zone-b, and a slow request failed with 504 inside the timeout"
exit 0
