#!/usr/bin/env bash
# Confirms endpoints carry localities, that BOTH outlierDetection and
# localityLbSetting are configured with a maxEjectionPercent that can act, that
# the failing local zone is ejected, and that traffic ends up healthy in zone-b
# without the broken workload having been removed.

set -u

NS="locality-demo"
SVC="httpbin"
CLUSTER="outbound|8000||httpbin.locality-demo.svc.cluster.local"

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

# --- 0. nothing was removed to fake the result ------------------------------
for d in httpbin-zone-a httpbin-zone-b tester; do
  r=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$r" && "$r" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas"
  n=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.spec.replicas}' 2>/dev/null)
  [[ "$n" == "1" ]] || fail "$d runs $n replicas, expected 1. The broken zone must stay up - outlier detection is what takes it out"
done

ep_count=$(kubectl -n "$NS" get endpoints "$SVC" \
  -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w | tr -d ' ')
[[ "$ep_count" -eq 2 ]] \
  || fail "the $SVC Service has $ep_count endpoint(s), expected 2"

# --- 1. endpoints carry a locality ------------------------------------------
epjson=$(istioctl proxy-config endpoints deploy/tester -n "$NS" --cluster "$CLUSTER" -o json 2>/dev/null)
[[ -n "$epjson" ]] || fail "could not read the tester proxy's endpoint list"
zones=$(grep -c '"zone"' <<<"$epjson")
[[ "$zones" -ge 2 ]] \
  || fail "fewer than 2 endpoints report a zone. Without a locality every setting in this module is a no-op - check the istio-locality pod labels and the node topology labels"

# --- 2. the DestinationRule has BOTH halves ---------------------------------
kubectl -n "$NS" get destinationrule "$SVC" >/dev/null 2>&1 \
  || fail "DestinationRule '$SVC' not found in $NS"

od() { kubectl -n "$NS" get destinationrule "$SVC" \
        -o jsonpath="{.spec.trafficPolicy.outlierDetection.$1}" 2>/dev/null; }

c5=$(od consecutive5xxErrors); iv=$(od interval); be=$(od baseEjectionTime); mx=$(od maxEjectionPercent)
llb=$(kubectl -n "$NS" get destinationrule "$SVC" \
  -o jsonpath='{.spec.trafficPolicy.loadBalancer.localityLbSetting}' 2>/dev/null)

[[ -n "$llb" ]] \
  || fail "the DestinationRule has no loadBalancer.localityLbSetting"
[[ -n "$c5$iv$be$mx" ]] \
  || fail "the DestinationRule has localityLbSetting but NO outlierDetection. This is the failure the task exists to teach: locality failover has no health checker of its own, so with nothing to mark an endpoint unhealthy it never fails over"

[[ "$c5" == "2" ]]   || fail "consecutive5xxErrors is '$c5', expected 2"
[[ "$iv" == "5s" ]]  || fail "interval is '$iv', expected 5s"
[[ "$be" == "30s" ]] || fail "baseEjectionTime is '$be', expected 30s"
[[ -n "$mx" ]]       || fail "maxEjectionPercent is not set. Its 10% default cannot eject anything from a two-endpoint pool, so nothing becomes unhealthy and nothing fails over"
[[ "$mx" -ge 50 ]] \
  || fail "maxEjectionPercent is $mx, which on two endpoints allows $((2 * mx / 100)) ejections. You need at least 50"

# --- 3. the policy is live in the proxy -------------------------------------
dump=$(istioctl proxy-config cluster deploy/tester -n "$NS" \
  --fqdn "httpbin.${NS}.svc.cluster.local" -o json 2>/dev/null)
grep -q 'outlierDetection' <<<"$dump" \
  || fail "the tester proxy's cluster has no outlierDetection block - the DestinationRule never reached the sidecar"

# --- 4. drive traffic until the local zone is ejected -----------------------
before_total=$(stat_val 'outlier_detection.ejections_total'); before_total=${before_total:-0}

ejected=0
for round in 1 2 3 4; do
  drive 60
  sleep 6
  active=$(stat_val 'outlier_detection.ejections_active'); active=${active:-0}
  total=$(stat_val 'outlier_detection.ejections_total');  total=${total:-0}
  eps=$(istioctl proxy-config endpoints deploy/tester -n "$NS" --cluster "$CLUSTER" 2>/dev/null)
  if [[ "$active" -ge 1 || "$total" -gt "$before_total" ]] || grep -qi FAILED <<<"$eps"; then
    ejected=1
    break
  fi
done

[[ "$ejected" -eq 1 ]] \
  || fail "after 240 requests nothing was ejected (ejections_total still $before_total). The failing local endpoint is never being marked unhealthy - check maxEjectionPercent and that outlierDetection is present"

# --- 5. traffic is healthy, and it moved to zone-b --------------------------
out=$(kubectl -n "$NS" exec deploy/tester -- sh -c \
  'for i in $(seq 1 40); do curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://httpbin:8000/get; done' 2>/dev/null)
ok=$(grep -c '^200$' <<<"$out")
[[ "$ok" -ge 32 ]] \
  || fail "only $ok of 40 requests succeeded after the ejection. Traffic has not moved out of the failing locality"

zb_ip=$(kubectl -n "$NS" get pods -l app=httpbin,zone=b \
  -o jsonpath='{.items[0].status.podIP}' 2>/dev/null)
sleep 1
served=$(kubectl -n "$NS" logs deploy/tester -c istio-proxy --tail=40 2>/dev/null \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080' | sort | uniq -c | sort -rn | head -1)
grep -q "$zb_ip" <<<"$served" \
  || fail "the busiest upstream in the last 40 requests was '$served', which is not the zone-b pod ($zb_ip). Traffic should have moved to the healthy locality"

final_total=$(stat_val 'outlier_detection.ejections_total'); final_total=${final_total:-0}

echo "PASS: both endpoints carry a locality, outlierDetection (2 consecutive 5xx, maxEjectionPercent ${mx}) and localityLbSetting are both configured, ejections_total=${final_total}, and ${ok}/40 requests now succeed from the zone-b endpoint while zone-a is still running"
exit 0
