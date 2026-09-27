#!/usr/bin/env bash
# Section 040 capstone. Confirms all four resilience features are configured and
# working together: differing retry policies for writes and reads, a sufficient
# timeout budget, a connection pool that rejects concurrent overflow with UO,
# outlier detection that ejects the failing endpoint, and locality awareness.

set -u

NS="payments"
SVC="ledger"
CLUSTER="outbound|8000||ledger.payments.svc.cluster.local"

fail() { echo "FAIL: $*"; exit 1; }

stat_val() {
  kubectl -n "$NS" exec deploy/fortio -c istio-proxy -- \
    pilot-agent request GET stats 2>/dev/null \
    | grep -F "$SVC" | grep -F "$1" | awk -F': ' '{print $2}' | head -1
}
server_attempts() {
  local path="$1"; shift
  local before after
  before=$(kubectl -n "$NS" logs -l app=ledger -c istio-proxy --tail=-1 2>/dev/null | grep -c -- "$path")
  kubectl -n "$NS" exec deploy/fortio -c fortio -- \
    fortio curl -quiet "$@" "http://ledger:8000${path}" >/dev/null 2>&1 || true
  sleep 3
  after=$(kubectl -n "$NS" logs -l app=ledger -c istio-proxy --tail=-1 2>/dev/null | grep -c -- "$path")
  echo $((after - before))
}

# --- 0. the environment is intact -------------------------------------------
declare -A WANT=( [ledger-good]=2 [ledger-bad]=1 [fortio]=1 )
for d in "${!WANT[@]}"; do
  r=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$r" && "$r" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas"
  n=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.spec.replicas}' 2>/dev/null)
  [[ "$n" == "${WANT[$d]}" ]] || fail "$d runs $n replicas, expected ${WANT[$d]}. Do not scale or remove the failing replica"
done

sel=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.selector}' 2>/dev/null)
grep -q 'health' <<<"$sel" && fail "the $SVC Service selector is $sel - it must keep selecting on app only"

# --- 1. VirtualService: the write rule --------------------------------------
kubectl -n "$NS" get virtualservice "$SVC" >/dev/null 2>&1 \
  || fail "VirtualService '$SVC' not found in $NS"

m=$(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{.spec.http[0].match[0].method.exact}' 2>/dev/null)
[[ "$m" == "POST" ]] \
  || fail "the FIRST http rule does not match method POST (found '$m'). The catch-all read rule would swallow everything if it came first"

pa=$(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{.spec.http[0].retries.attempts}' 2>/dev/null)
[[ "$pa" == "0" ]] \
  || fail "the POST rule has retries.attempts='$pa', expected 0. Omitting the retries block leaves Istio's implicit default of 2 attempts in force"

pt=$(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{.spec.http[0].timeout}' 2>/dev/null)
[[ "$pt" == "3s" ]] || fail "the POST rule's timeout is '$pt', expected 3s"

# --- 2. VirtualService: the read rule ---------------------------------------
rm_=$(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{.spec.http[1].match}' 2>/dev/null)
[[ -z "$rm_" ]] || fail "the SECOND http rule carries a match block ($rm_) - it must be the catch-all"

a=$(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{.spec.http[1].retries.attempts}' 2>/dev/null)
p=$(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{.spec.http[1].retries.perTryTimeout}' 2>/dev/null)
ro=$(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{.spec.http[1].retries.retryOn}' 2>/dev/null)
t=$(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{.spec.http[1].timeout}' 2>/dev/null)

[[ "$a" == "2" ]]  || fail "the read rule has retries.attempts='$a', expected 2"
[[ "$p" == "1s" ]] || fail "the read rule has perTryTimeout='$p', expected 1s"
grep -q 'gateway-error' <<<"$ro" || fail "the read rule has retryOn='$ro', which does not include gateway-error"
[[ -n "$t" ]] || fail "the read rule has no timeout"

tsec=${t%s}; psec=${p%s}
case "$tsec" in ''|*[!0-9.]*) fail "could not parse the read timeout '$t' - use a plain value like 4s" ;; esac
need=$(python3 -c "print((${a} + 1) * ${psec})" 2>/dev/null)
ok=$(python3 -c "print(1 if ${tsec} >= ${need} else 0)" 2>/dev/null)
[[ "$ok" == "1" ]] \
  || fail "the read timeout is ${t} but (attempts + 1) x perTryTimeout = ${need}s. A shorter timeout silently truncates the retries"

# --- 3. DestinationRule ------------------------------------------------------
kubectl -n "$NS" get destinationrule "$SVC" >/dev/null 2>&1 \
  || fail "DestinationRule '$SVC' not found in $NS"

cp_mc=$(kubectl -n "$NS" get destinationrule "$SVC" \
  -o jsonpath='{.spec.trafficPolicy.connectionPool.tcp.maxConnections}' 2>/dev/null)
cp_mp=$(kubectl -n "$NS" get destinationrule "$SVC" \
  -o jsonpath='{.spec.trafficPolicy.connectionPool.http.http1MaxPendingRequests}' 2>/dev/null)
[[ "$cp_mc" == "2" ]] || fail "tcp.maxConnections is '$cp_mc', expected 2"
[[ "$cp_mp" == "2" ]] || fail "http.http1MaxPendingRequests is '$cp_mp', expected 2"

od() { kubectl -n "$NS" get destinationrule "$SVC" \
        -o jsonpath="{.spec.trafficPolicy.outlierDetection.$1}" 2>/dev/null; }
[[ "$(od consecutive5xxErrors)" == "3" ]]  || fail "consecutive5xxErrors is '$(od consecutive5xxErrors)', expected 3"
[[ "$(od interval)" == "5s" ]]             || fail "interval is '$(od interval)', expected 5s"
[[ "$(od baseEjectionTime)" == "30s" ]]    || fail "baseEjectionTime is '$(od baseEjectionTime)', expected 30s"
mx=$(od maxEjectionPercent)
[[ -n "$mx" ]] || fail "maxEjectionPercent is not set. Its 10% default cannot eject anything from a three-endpoint pool"
[[ "$mx" -ge 34 ]] \
  || fail "maxEjectionPercent is $mx, which on three endpoints allows $((3 * mx / 100)) ejections. You need at least 34"

llb=$(kubectl -n "$NS" get destinationrule "$SVC" \
  -o jsonpath='{.spec.trafficPolicy.loadBalancer.localityLbSetting.enabled}' 2>/dev/null)
[[ "$llb" == "true" ]] || fail "loadBalancer.localityLbSetting.enabled is '$llb', expected true"

# --- 4. live: retries on reads, none on writes ------------------------------
n=$(server_attempts /status/503)
[[ "$n" -eq 3 ]] \
  || fail "a GET /status/503 produced $n request(s) at the service, expected 3 (the original plus 2 retries)"

n=$(server_attempts /status/503 -X POST)
[[ "$n" -eq 1 ]] \
  || fail "a POST /status/503 produced $n requests at the service, expected exactly 1. Either the POST rule is not first, or its retries are not disabled"

# --- 5. live: the connection pool rejects concurrency -----------------------
before_ovf=$(stat_val 'upstream_rq_pending_overflow'); before_ovf=${before_ovf:-0}
kubectl -n "$NS" exec deploy/fortio -c fortio -- \
  fortio load -c 8 -qps 0 -n 80 -loglevel Warning "http://${SVC}:8000/get" >/dev/null 2>&1
sleep 2
after_ovf=$(stat_val 'upstream_rq_pending_overflow'); after_ovf=${after_ovf:-0}
[[ $((after_ovf - before_ovf)) -gt 0 ]] \
  || fail "upstream_rq_pending_overflow did not increase during a concurrent run at -c 8 against a pool of 2 connections + 2 pending. The connection pool is not binding"

uo=$(kubectl -n "$NS" logs deploy/fortio -c istio-proxy --tail=200 2>/dev/null | grep -c ' 503 UO ')
[[ "$uo" -gt 0 ]] \
  || fail "no ' 503 UO ' lines in the fortio proxy access log - the rejections are not circuit-breaker overflow"

# --- 6. live: the failing endpoint is ejected -------------------------------
before_total=$(stat_val 'outlier_detection.ejections_total'); before_total=${before_total:-0}
ejected=0
for round in 1 2 3 4; do
  kubectl -n "$NS" exec deploy/fortio -c fortio -- \
    fortio load -c 2 -qps 0 -n 80 -loglevel Warning "http://${SVC}:8000/get" >/dev/null 2>&1
  sleep 6
  active=$(stat_val 'outlier_detection.ejections_active'); active=${active:-0}
  total=$(stat_val 'outlier_detection.ejections_total');  total=${total:-0}
  eps=$(istioctl proxy-config endpoints deploy/fortio -n "$NS" --cluster "$CLUSTER" 2>/dev/null)
  if [[ "$active" -ge 1 || "$total" -gt "$before_total" ]] || grep -qi FAILED <<<"$eps"; then
    ejected=1; break
  fi
done
[[ "$ejected" -eq 1 ]] \
  || fail "after 320 requests nothing was ejected (ejections_total still $before_total). The failing replica is never being marked unhealthy - check maxEjectionPercent, and note that retries on the read path can hide failures from the caller but must NOT stop the proxy recording them"

# --- 7. Kubernetes still lists everything -----------------------------------
ep_after=$(kubectl -n "$NS" get endpoints "$SVC" \
  -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w | tr -d ' ')
[[ "$ep_after" -eq 3 ]] \
  || fail "the Service now has $ep_after endpoints, expected 3. Outlier detection must not change the Kubernetes object"

final_total=$(stat_val 'outlier_detection.ejections_total'); final_total=${final_total:-0}

echo "PASS: POST rule (timeout ${pt}, attempts 0) above the read rule (timeout ${t}, ${a} retries x ${p} on ${ro}); reads made 3 server attempts and writes 1; the pool (2 conn + 2 pending) produced ${uo} UO-flagged rejections with pending_overflow rising by $((after_ovf - before_ovf)); ejections_total=${final_total} with all 3 endpoints still registered"
exit 0
