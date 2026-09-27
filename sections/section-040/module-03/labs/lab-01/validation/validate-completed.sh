#!/usr/bin/env bash
# Confirms the outlier detection fields are set with a maxEjectionPercent that
# can actually act on a two-endpoint service, that the policy is live in the
# proxy, that driving traffic really ejects the failing endpoint, and that
# Kubernetes still lists it while the proxy has stopped using it.

set -u

NS="outlier-demo"
SVC="httpbin"
CLUSTER="outbound|8000||httpbin.outlier-demo.svc.cluster.local"

fail() { echo "FAIL: $*"; exit 1; }

stat_val() {
  kubectl -n "$NS" exec deploy/tester -c istio-proxy -- \
    pilot-agent request GET stats 2>/dev/null \
    | grep -F "$SVC" | grep -F "$1" | awk -F': ' '{print $2}' | head -1
}

drive() {
  kubectl -n "$NS" exec deploy/tester -- sh -c \
    "for i in \$(seq 1 $1); do curl -s -o /dev/null --max-time 5 http://httpbin:8000/get; done" >/dev/null 2>&1
}

# --- 0. the environment is intact -------------------------------------------
for d in httpbin-good httpbin-bad tester; do
  r=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$r" && "$r" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas. The bad endpoint must stay running; the proxy has to eject it"
done

ep_count=$(kubectl -n "$NS" get endpoints "$SVC" \
  -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w | tr -d ' ')
[[ "$ep_count" -eq 2 ]] \
  || fail "the $SVC Service has $ep_count endpoint(s), expected 2. Do not remove the bad pod - outlier detection is what must take it out of rotation"

if kubectl -n "$NS" get virtualservice -o name 2>/dev/null | grep -q .; then
  fail "a VirtualService exists in $NS. The task asks for outlier detection alone - a retry policy would mask the failures"
fi

# --- 1. the DestinationRule fields ------------------------------------------
kubectl -n "$NS" get destinationrule "$SVC" >/dev/null 2>&1 \
  || fail "DestinationRule '$SVC' not found in $NS"

od() {
  kubectl -n "$NS" get destinationrule "$SVC" \
    -o jsonpath="{.spec.trafficPolicy.outlierDetection.$1}" 2>/dev/null
}
c5=$(od consecutive5xxErrors)
iv=$(od interval)
be=$(od baseEjectionTime)
mx=$(od maxEjectionPercent)

[[ "$c5" == "3" ]]   || fail "consecutive5xxErrors is '$c5', expected 3"
[[ "$iv" == "5s" ]]  || fail "interval is '$iv', expected 5s"
[[ "$be" == "30s" ]] || fail "baseEjectionTime is '$be', expected 30s"
[[ -n "$mx" ]]       || fail "maxEjectionPercent is not set. Its default is 10%, and 10% of two endpoints rounds down to zero - nothing could ever be ejected"
[[ "$mx" -ge 50 ]] \
  || fail "maxEjectionPercent is $mx. On a two-endpoint service that allows $((2 * mx / 100)) ejections - you need at least 50 for one endpoint to be removable"

# --- 2. the policy is live in the proxy -------------------------------------
dump=$(istioctl proxy-config cluster deploy/tester -n "$NS" \
  --fqdn "httpbin.${NS}.svc.cluster.local" -o json 2>/dev/null)
[[ -n "$dump" ]] || fail "could not read the tester proxy's cluster config"
grep -q 'outlierDetection' <<<"$dump" \
  || fail "the tester proxy's cluster has no outlierDetection block - the DestinationRule exists but never reached the sidecar"

# --- 3. drive traffic until an ejection happens -----------------------------
before_total=$(stat_val 'outlier_detection.ejections_total'); before_total=${before_total:-0}

ejected=0
for round in 1 2 3 4; do
  drive 60
  sleep 6
  active=$(stat_val 'outlier_detection.ejections_active'); active=${active:-0}
  total=$(stat_val 'outlier_detection.ejections_total');  total=${total:-0}
  if [[ "$active" -ge 1 || "$total" -gt "$before_total" ]]; then
    ejected=1
    break
  fi
done

[[ "$ejected" -eq 1 ]] \
  || fail "after 240 requests, outlier_detection.ejections_active is 0 and ejections_total has not moved from $before_total. The failures are being counted but nothing is being ejected - the usual cause is maxEjectionPercent being too low for a two-endpoint pool"

# --- 4. the endpoint view shows the verdict ---------------------------------
eps=$(istioctl proxy-config endpoints deploy/tester -n "$NS" --cluster "$CLUSTER" 2>/dev/null)
[[ -n "$eps" ]] || fail "could not read the tester proxy's endpoint list for $CLUSTER"
grep -qi 'FAILED' <<<"$eps" \
  || fail "no endpoint shows OUTLIER CHECK: FAILED in the proxy's endpoint list. Re-run after driving more traffic - ejection expires after baseEjectionTime and you may have caught it between ejections"

# --- 5. Kubernetes still lists both, and the bad pod still runs --------------
ep_after=$(kubectl -n "$NS" get endpoints "$SVC" \
  -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w | tr -d ' ')
[[ "$ep_after" -eq 2 ]] \
  || fail "the Service now has $ep_after endpoints. Outlier detection must not change the Kubernetes object - if this dropped to 1 the bad pod was removed by something else"

bad_ready=$(kubectl -n "$NS" get deployment httpbin-bad -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ "$bad_ready" == "1" ]] || fail "httpbin-bad is no longer ready - it must stay running"

# --- 6. traffic is measurably healthier -------------------------------------
out=$(kubectl -n "$NS" exec deploy/tester -- sh -c \
  'for i in $(seq 1 40); do curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://httpbin:8000/get; done' 2>/dev/null)
ok=$(grep -c '^200$' <<<"$out")
[[ "$ok" -ge 32 ]] \
  || fail "only $ok of 40 requests succeeded after the ejection, which is close to the unconfigured 50% failure rate. The ejection is not holding - check maxEjectionPercent and baseEjectionTime"

final_active=$(stat_val 'outlier_detection.ejections_active'); final_active=${final_active:-0}
final_total=$(stat_val 'outlier_detection.ejections_total');  final_total=${final_total:-0}

echo "PASS: outlier detection configured (3 consecutive 5xx, 5s interval, 30s base, maxEjectionPercent ${mx}); ejections_total=${final_total}, ejections_active=${final_active}; the proxy reports OUTLIER CHECK FAILED for one endpoint while Kubernetes still lists both, and ${ok}/40 requests now succeed"
exit 0
