#!/usr/bin/env bash
# Confirms one DestinationRule for the probe holds both halves of a circuit
# breaker with the required values, and - the part that matters - that both
# halves work on live signals: fortio's proxy refuses overflow signals, and the
# shuttle's proxy pulls the broken ship out of formation, while Kubernetes
# still lists it.

set -u

NS="starfleet"
SVC="probe"
FQDN="probe.starfleet.svc.cluster.local"
CLUSTER="outbound|8000||$FQDN"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is still what the mission handed over ---------------
for d in probe-v1 probe-v2 probe-broken shuttle fortio; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the ships alone: the broken ship must be removed by the proxy's own judgement, not by you"
done

deploy_count=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$deploy_count" -eq 5 ]] || fail "$NS holds $deploy_count deployments, expected exactly 5 - do not add or remove ships"

selector=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.selector.app}' 2>/dev/null)
[[ "$selector" == "probe" ]] || fail "the $SVC Service must keep selecting app=probe (found '$selector')"

broken_ip=$(kubectl -n "$NS" get pods -l app=probe,version=broken -o jsonpath='{.items[0].status.podIP}' 2>/dev/null)
[[ -n "$broken_ip" ]] || fail "could not find the probe-broken pod"

# --- 1. exactly one DestinationRule for the probe ----------------------------
drs=""
for dr in $(kubectl -n "$NS" get destinationrule -o name 2>/dev/null); do
  host=$(kubectl -n "$NS" get "$dr" -o jsonpath='{.spec.host}' 2>/dev/null)
  case "$host" in
    "$SVC"|"$SVC.$NS"|"$SVC.$NS.svc"|"$FQDN") drs="$drs ${dr#*/}" ;;
  esac
done
count=$(wc -w <<<"$drs" | tr -d ' ')
[[ "$count" -ge 1 ]] || fail "there is no DestinationRule for the probe yet. Create one, named probe, that holds both the connectionPool and the outlierDetection"
[[ "$count" -eq 1 ]] || fail "found $count DestinationRules for the probe ($drs), expected exactly one. Keep the connection pool and outlier detection in one rule: two rules for one host do not combine reliably"
DR="${drs// /}"

get() { kubectl -n "$NS" get destinationrule "$DR" -o jsonpath="{.spec.trafficPolicy.$1}" 2>/dev/null; }

# --- 2. the connection pool ---------------------------------------------------
[[ "$(get connectionPool.tcp.maxConnections)" == "1" ]] \
  || fail "connectionPool.tcp.maxConnections is '$(get connectionPool.tcp.maxConnections)', expected 1"
[[ "$(get connectionPool.http.http1MaxPendingRequests)" == "1" ]] \
  || fail "connectionPool.http.http1MaxPendingRequests is '$(get connectionPool.http.http1MaxPendingRequests)', expected 1. Without a small queue, waiting signals pile up instead of being refused"

# --- 3. outlier detection -----------------------------------------------------
[[ "$(get outlierDetection.consecutive5xxErrors)" == "3" ]] \
  || fail "outlierDetection.consecutive5xxErrors is '$(get outlierDetection.consecutive5xxErrors)', expected 3"
[[ "$(get outlierDetection.interval)" == "5s" ]] \
  || fail "outlierDetection.interval is '$(get outlierDetection.interval)', expected 5s"
[[ "$(get outlierDetection.baseEjectionTime)" == "30s" ]] \
  || fail "outlierDetection.baseEjectionTime is '$(get outlierDetection.baseEjectionTime)', expected 30s"
mep=$(get outlierDetection.maxEjectionPercent)
[[ -n "$mep" && "$mep" -ge 34 ]] \
  || fail "outlierDetection.maxEjectionPercent is '${mep:-unset (10%)}'. With three probe ships, one ejection is 33% of the list, so the limit must be at least 34 or nothing is ever ejected"

# --- 4. the shields: fortio's proxy refuses overflow signals -----------------
stat() {  # $1 = deployment, $2 = counter name
  kubectl -n "$NS" exec deploy/"$1" -c istio-proxy -- pilot-agent request GET stats 2>/dev/null \
    | grep -F "$CLUSTER" | grep -E "\.$2: " | awk '{print $2}' | head -1
}
ok=""
for i in $(seq 1 6); do
  kubectl -n "$NS" exec deploy/fortio -c fortio -- \
    fortio load -c 4 -qps 0 -n 40 -loglevel Error "http://$SVC:8000/get" >/dev/null 2>&1
  overflow=$(stat fortio upstream_rq_pending_overflow)
  if [[ -n "$overflow" && "$overflow" -gt 0 ]]; then ok=1; break; fi
  sleep 5
done
[[ -n "$ok" ]] || fail "fortio sent 40 signals over 4 parallel connections and its proxy refused none (upstream_rq_pending_overflow is '${overflow:-missing}'). The connection pool is not live in fortio's proxy"

# --- 5. the ejection: the shuttle's proxy pulls the broken ship out ---------
ejected=""
for i in $(seq 1 8); do
  for n in $(seq 1 15); do
    kubectl -n "$NS" exec deploy/shuttle -- curl -s -o /dev/null --max-time 5 "http://$SVC:8000/get" >/dev/null 2>&1
  done
  if istioctl proxy-config endpoints deploy/shuttle -n "$NS" --cluster "$CLUSTER" 2>/dev/null \
       | grep -F "$broken_ip:" | grep -q FAILED; then
    ejected=1; break
  fi
  sleep 3
done
total=$(stat shuttle outlier_detection.ejections_total)
[[ -n "$ejected" ]] || fail "after many signals, the shuttle's proxy still has the broken ship ($broken_ip) in its list (ejections_total is '${total:-missing}'). Check consecutive5xxErrors and maxEjectionPercent"
[[ -n "$total" && "$total" -ge 1 ]] || fail "the shuttle's proxy shows the broken ship as FAILED, but ejections_total is '${total:-missing}'"

# --- 6. while ejected, single signals succeed --------------------------------
fails=0
for n in $(seq 1 10); do
  code=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://$SVC:8000/get" 2>/dev/null)
  [[ "$code" == "200" ]] || fails=$((fails + 1))
done
[[ "$fails" -le 1 ]] || fail "$fails of 10 single signals failed while the broken ship should be ejected. Expected at most 1"

# --- 7. Kubernetes still lists the broken ship -------------------------------
kubectl -n "$NS" get endpointslices -l kubernetes.io/service-name="$SVC" -o jsonpath='{.items[*].endpoints[*].addresses[*]}' 2>/dev/null \
  | grep -qw "$broken_ip" \
  || fail "the probe Service no longer lists the broken ship ($broken_ip). The ejection must be the proxy's own verdict, not a change to the Service"

echo "PASS: one DestinationRule '$DR' holds both shields; fortio's proxy refused $overflow overflow signals, the shuttle's proxy ejected the broken ship ($broken_ip, ejections_total=$total), single signals succeed while it is out, and Kubernetes still lists it"
