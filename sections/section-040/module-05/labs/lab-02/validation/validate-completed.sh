#!/usr/bin/env bash
# Confirms that the probe Service has trafficDistribution PreferClose, that the
# DestinationRule has outlier detection that can eject (and no locality setting),
# that nothing else was changed, and - the part that matters - that live requests
# from the shuttle all stay in the shuttle's own zone.

set -u

NS="starfleet"
FQDN="probe.starfleet.svc.cluster.local"
CLUSTER="outbound|8000||$FQDN"

fail() { echo "FAIL: $*"; exit 1; }

answering_pod() {  # one request from the shuttle; prints the probe that answered.
  # A failed kubectl exec (not a failed request) is retried, so a flaky API
  # stream cannot fail the grade.
  local out t
  for t in 1 2 3; do
    out=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 10 http://probe:8000/hostname 2>/dev/null) && break
    sleep 1
  done
  grep -o 'probe-zone-[ab]' <<<"$out" || echo "no-answer"
}

# --- 0. the environment is still what the lab handed over -------------------
for d in shuttle probe-zone-a probe-zone-b; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Keep every deployment running"
done
deploy_count=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$deploy_count" -eq 3 ]] || fail "$NS holds $deploy_count deployments, expected exactly 3 - do not add or remove deployments"

for n in $(kubectl get nodes -o name); do
  zone=$(kubectl get "$n" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}')
  region=$(kubectl get "$n" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/region}')
  [[ "$region/$zone" == "local/zone-a" ]] || fail "node $n is now in '$region/$zone', expected local/zone-a. Leave the node labels alone"
done
shuttle_loc=$(kubectl -n "$NS" get deployment shuttle -o jsonpath='{.spec.template.metadata.labels.istio-locality}' 2>/dev/null)
[[ -z "$shuttle_loc" ]] || fail "the shuttle now carries istio-locality=$shuttle_loc. The shuttle must keep the node's locality, local/zone-a"
a_loc=$(kubectl -n "$NS" get deployment probe-zone-a -o jsonpath='{.spec.template.metadata.labels.istio-locality}' 2>/dev/null)
b_loc=$(kubectl -n "$NS" get deployment probe-zone-b -o jsonpath='{.spec.template.metadata.labels.istio-locality}' 2>/dev/null)
[[ "$a_loc" == "local.zone-a" && "$b_loc" == "local.zone-b" ]] || fail "the probe localities changed (zone-a='$a_loc', zone-b='$b_loc'). Leave the pod localities alone"

# --- 1. the Service asks for nearby endpoints --------------------------------
td=$(kubectl -n "$NS" get service probe -o jsonpath='{.spec.trafficDistribution}' 2>/dev/null)
[[ -n "$td" ]] || fail "the probe Service has no spec.trafficDistribution. Set it on the Service, not on a DestinationRule"
[[ "$td" == "PreferClose" ]] || fail "the probe Service has trafficDistribution '$td', expected PreferClose"
selector=$(kubectl -n "$NS" get service probe -o jsonpath='{.spec.selector}' 2>/dev/null)
[[ "$selector" == '{"app":"probe"}' ]] || fail "the probe Service selector is '$selector', expected {\"app\":\"probe\"}"
port=$(kubectl -n "$NS" get service probe -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
[[ "$port" == "8000" ]] || fail "the probe Service port is '$port', expected 8000"

# --- 2. the DestinationRule: outlier detection, no locality setting ----------
kubectl -n "$NS" get destinationrule probe >/dev/null 2>&1 || fail "DestinationRule 'probe' not found in $NS"
dr_count=$(kubectl -n "$NS" get destinationrule -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$dr_count" -eq 1 ]] || fail "$NS holds $dr_count DestinationRules, expected exactly 1 (named probe)"
host=$(kubectl -n "$NS" get destinationrule probe -o jsonpath='{.spec.host}' 2>/dev/null)
case "$host" in
  probe|"$FQDN") ;;
  *) fail "the DestinationRule host is '$host', expected probe" ;;
esac
errs=$(kubectl -n "$NS" get destinationrule probe -o jsonpath='{.spec.trafficPolicy.outlierDetection.consecutive5xxErrors}' 2>/dev/null)
[[ "$errs" == "2" ]] || fail "outlierDetection.consecutive5xxErrors is '$errs', expected 2"
interval=$(kubectl -n "$NS" get destinationrule probe -o jsonpath='{.spec.trafficPolicy.outlierDetection.interval}' 2>/dev/null)
[[ "$interval" == "5s" ]] || fail "outlierDetection.interval is '$interval', expected 5s"
base=$(kubectl -n "$NS" get destinationrule probe -o jsonpath='{.spec.trafficPolicy.outlierDetection.baseEjectionTime}' 2>/dev/null)
[[ "$base" == "30s" ]] || fail "outlierDetection.baseEjectionTime is '$base', expected 30s"
maxp=$(kubectl -n "$NS" get destinationrule probe -o jsonpath='{.spec.trafficPolicy.outlierDetection.maxEjectionPercent}' 2>/dev/null)
[[ "$maxp" == "100" ]] || fail "outlierDetection.maxEjectionPercent is '$maxp', expected 100. With the default of 10 percent, one of two endpoints can never be ejected"
loc=$(kubectl -n "$NS" get destinationrule probe -o jsonpath='{.spec.trafficPolicy.loadBalancer.localityLbSetting}' 2>/dev/null)
[[ -z "$loc" ]] || fail "the DestinationRule sets localityLbSetting. The preference must come from the Service field, so remove it"

# --- 3. the shuttle's proxy still sees both zones -----------------------------
zones=""
for i in $(seq 1 30); do
  zones=$(istioctl proxy-config endpoints deploy/shuttle -n "$NS" --cluster "$CLUSTER" -o json 2>/dev/null \
    | grep -o '"zone": "[^"]*"' | sed 's/.*: "//; s/"$//' | sort | tr '\n' ' ' | sed 's/ $//')
  [[ "$zones" == "zone-a zone-b" ]] && break
  sleep 2
done
[[ "$zones" == "zone-a zone-b" ]] || fail "the shuttle's proxy shows probe endpoints in zones [$zones], expected one in zone-a and one in zone-b. Both probes must stay endpoints of the Service"

# --- 4. live requests stay in the shuttle's zone ------------------------------
sleep 3
result=$(for i in $(seq 1 20); do answering_pod; done | sort | uniq -c | awk '{print $2"="$1}' | tr '\n' ' ' | sed 's/ $//')
[[ "$result" == "probe-zone-a=20" ]] || fail "20 requests from the shuttle gave [$result], expected all 20 from probe-zone-a, the shuttle's own zone"

echo "PASS: the probe Service prefers close endpoints, the DestinationRule has outlier detection that can eject, both probes stay endpoints, and all 20 requests stayed in the shuttle's zone"
exit 0
