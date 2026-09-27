#!/usr/bin/env bash
# Confirms the connection pool limits are configured and live in the proxy, that
# a sequential load still succeeds while a concurrent one is rejected, and that
# the rejections carry the UO flag and move the pending-overflow counter while
# the backend sees nothing.

set -u

NS="circuit-demo"
SVC="notification-service"
FQDN="notification-service.circuit-demo.svc.cluster.local"

fail() { echo "FAIL: $*"; exit 1; }

stat_val() {
  kubectl -n "$NS" exec deploy/fortio -c istio-proxy -- \
    pilot-agent request GET stats 2>/dev/null \
    | grep -F "$SVC" | grep -F "$1" | awk -F': ' '{print $2}' | head -1
}

# --- 0. the environment is intact -------------------------------------------
for d in notification-service-v1 fortio; do
  r=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$r" && "$r" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas"
done

if kubectl -n "$NS" get virtualservice -o name 2>/dev/null | grep -q .; then
  fail "a VirtualService exists in $NS. A retry policy would hide the rejections this task is about - remove it"
fi

# --- 1. the DestinationRule --------------------------------------------------
kubectl -n "$NS" get destinationrule "$SVC" >/dev/null 2>&1 \
  || fail "DestinationRule '$SVC' not found in $NS"

mc=$(kubectl -n "$NS" get destinationrule "$SVC" \
  -o jsonpath='{.spec.trafficPolicy.connectionPool.tcp.maxConnections}' 2>/dev/null)
mp=$(kubectl -n "$NS" get destinationrule "$SVC" \
  -o jsonpath='{.spec.trafficPolicy.connectionPool.http.http1MaxPendingRequests}' 2>/dev/null)
mr=$(kubectl -n "$NS" get destinationrule "$SVC" \
  -o jsonpath='{.spec.trafficPolicy.connectionPool.http.maxRequestsPerConnection}' 2>/dev/null)

[[ "$mc" == "1" ]] || fail "tcp.maxConnections is '$mc', expected 1"
[[ "$mp" == "1" ]] || fail "http.http1MaxPendingRequests is '$mp', expected 1"
[[ "$mr" == "1" ]] || fail "http.maxRequestsPerConnection is '$mr', expected 1"

# --- 2. the limits reached the proxy ----------------------------------------
dump=$(istioctl proxy-config cluster deploy/fortio -n "$NS" --fqdn "$FQDN" -o json 2>/dev/null)
[[ -n "$dump" ]] || fail "could not read the fortio proxy's cluster config"

live_mc=$(python3 -c "
import json,sys
for c in json.loads(sys.argv[1]):
    t=(c.get('circuitBreakers') or {}).get('thresholds') or [{}]
    print(t[0].get('maxConnections','')); break
" "$dump" 2>/dev/null)
live_mp=$(python3 -c "
import json,sys
for c in json.loads(sys.argv[1]):
    t=(c.get('circuitBreakers') or {}).get('thresholds') or [{}]
    print(t[0].get('maxPendingRequests','')); break
" "$dump" 2>/dev/null)

[[ "$live_mc" == "1" ]] \
  || fail "the proxy's circuitBreakers maxConnections is '$live_mc', expected 1 - the DestinationRule exists but never reached the sidecar"
[[ "$live_mp" == "1" ]] \
  || fail "the proxy's circuitBreakers maxPendingRequests is '$live_mp', expected 1"

# --- 3. sequential load must still succeed ----------------------------------
seq_out=$(kubectl -n "$NS" exec deploy/fortio -c fortio -- \
  fortio load -c 1 -qps 0 -n 20 -loglevel Warning "http://${SVC}/notify" 2>&1)
seq_200=$(grep -oE 'Code 200 : [0-9]+' <<<"$seq_out" | awk '{print $4}')
seq_200=${seq_200:-0}
[[ "$seq_200" -ge 19 ]] \
  || fail "a SEQUENTIAL run of 20 requests only produced $seq_200 successes. The limit is on concurrency, not on request count - at -c 1 nothing should be rejected. Check maxConnections is not 0"

# --- 4. concurrent load must be rejected ------------------------------------
before_ovf=$(stat_val 'upstream_rq_pending_overflow')
before_ovf=${before_ovf:-0}

con_out=$(kubectl -n "$NS" exec deploy/fortio -c fortio -- \
  fortio load -c 5 -qps 0 -n 50 -loglevel Warning "http://${SVC}/notify" 2>&1)
con_503=$(grep -oE 'Code 503 : [0-9]+' <<<"$con_out" | awk '{print $4}')
con_503=${con_503:-0}
[[ "$con_503" -gt 0 ]] \
  || fail "a CONCURRENT run of 50 requests at -c 5 produced no 503s. With maxConnections 1 and http1MaxPendingRequests 1, a third simultaneous request has nowhere to go. Check the limits are on the right host"

# --- 5. the rejections carry UO ---------------------------------------------
sleep 2
uo=$(kubectl -n "$NS" logs deploy/fortio -c istio-proxy --tail=200 2>/dev/null | grep -c ' 503 UO ')
[[ "$uo" -gt 0 ]] \
  || fail "no ' 503 UO ' lines in the fortio proxy access log. The 503s are not circuit-breaker rejections - check whether the backend is producing them instead"

# --- 6. the counter moved ----------------------------------------------------
after_ovf=$(stat_val 'upstream_rq_pending_overflow')
after_ovf=${after_ovf:-0}
delta=$((after_ovf - before_ovf))
[[ "$delta" -gt 0 ]] \
  || fail "upstream_rq_pending_overflow did not increase during the concurrent run (before=$before_ovf after=$after_ovf). That counter is the proof a pending slot was unavailable"

# --- 7. the backend saw none of it ------------------------------------------
srv_503=$(kubectl -n "$NS" logs -l app="$SVC" -c istio-proxy --tail=200 2>/dev/null | grep -c ' 503 ')
[[ "$srv_503" -eq 0 ]] \
  || fail "the backend's proxy logged $srv_503 responses with status 503. Circuit-breaker rejections are produced by the CALLER and never reach the backend, so these 503s have a different cause"

echo "PASS: pool limited to 1 connection + 1 pending (live in the proxy); a sequential run passed ${seq_200}/20 while a concurrent run was rejected ${con_503} times with ${uo} UO-flagged log lines, pending_overflow rose by ${delta}, and the backend logged no 503s"
exit 0
