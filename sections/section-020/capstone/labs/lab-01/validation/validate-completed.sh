#!/usr/bin/env bash
# Section 020 capstone. Confirms the header rule sits above a weighted 80/20
# default, that the SAME default rule mirrors to the separate shadow service,
# that live traffic splits in proportion while the shadow receives every copy,
# and that nothing was scaled to fake any of it.

set -u

NS="checkout"
SVC="notification-service"
SHADOW="notification-shadow"
VS="notification"
V1='["EMAIL"]'
V2='["EMAIL","SMS"]'

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is intact -------------------------------------------
for d in notification-service-v1 notification-service-v2 notification-shadow tester; do
  r=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$r" && "$r" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas"
  n=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.spec.replicas}' 2>/dev/null)
  [[ "$n" == "1" ]] || fail "$d runs $n replicas, expected 1. Traffic share is a weight, not a pod count"
done

dcount=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$dcount" -eq 4 ]] || fail "$NS holds $dcount deployments, expected exactly 4"

sel=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.selector}' 2>/dev/null)
grep -q 'version' <<<"$sel" && fail "the $SVC Service selector is $sel - it must keep selecting on app only"

# --- 1. subsets --------------------------------------------------------------
kubectl -n "$NS" get destinationrule "$SVC" >/dev/null 2>&1 \
  || fail "DestinationRule '$SVC' not found in $NS"
for s in v1 v2; do
  lbl=$(kubectl -n "$NS" get destinationrule "$SVC" \
    -o jsonpath="{.spec.subsets[?(@.name=='$s')].labels.version}" 2>/dev/null)
  [[ "$lbl" == "$s" ]] || fail "subset '$s' selects on version='$lbl', expected version='$s'"
done

# --- 2. rule 1: the internal-tester match ------------------------------------
kubectl -n "$NS" get virtualservice "$VS" >/dev/null 2>&1 \
  || fail "VirtualService '$VS' not found in $NS"

hv=$(kubectl -n "$NS" get virtualservice "$VS" \
  -o jsonpath='{.spec.http[0].match[0].headers.x-internal.exact}' 2>/dev/null)
[[ "$hv" == "true" ]] \
  || fail "the FIRST http rule does not match header x-internal: \"true\" (found '$hv'). First match wins, so the internal rule must be above the weighted one"

hs=$(kubectl -n "$NS" get virtualservice "$VS" \
  -o jsonpath='{.spec.http[0].route[0].destination.subset}' 2>/dev/null)
[[ "$hs" == "v2" ]] || fail "the header rule routes to subset '$hs', expected v2"

# --- 3. rule 2: weighted split + mirror --------------------------------------
m1=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[1].match}' 2>/dev/null)
[[ -z "$m1" ]] || fail "the SECOND http rule carries a match block ($m1) - it must be the catch-all default"

w1=$(kubectl -n "$NS" get virtualservice "$VS" \
  -o jsonpath='{.spec.http[1].route[?(@.destination.subset=="v1")].weight}' 2>/dev/null)
w2=$(kubectl -n "$NS" get virtualservice "$VS" \
  -o jsonpath='{.spec.http[1].route[?(@.destination.subset=="v2")].weight}' 2>/dev/null)
[[ "$w1" == "80" ]] || fail "the weighted rule gives subset v1 weight '$w1', expected 80"
[[ "$w2" == "20" ]] || fail "the weighted rule gives subset v2 weight '$w2', expected 20"

mh=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[1].mirror.host}' 2>/dev/null)
[[ -n "$mh" ]] \
  || fail "the second http rule has no 'mirror' field - it belongs beside 'route' on the SAME rule"
case "$mh" in
  "$SHADOW"|"$SHADOW.$NS"|"$SHADOW.$NS.svc"|"$SHADOW.$NS.svc.cluster.local") ;;
  *) fail "the mirror targets host '$mh', expected $SHADOW" ;;
esac

mp=$(kubectl -n "$NS" get virtualservice "$VS" \
  -o jsonpath='{.spec.http[1].mirrorPercentage.value}' 2>/dev/null)
case "$mp" in
  100|100.0) ;;
  "") fail "mirrorPercentage is not set on the second rule - the task asks for it explicitly" ;;
  *)  fail "mirrorPercentage.value is '$mp', expected 100" ;;
esac

# the shadow must NOT be a weighted destination
if kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[*].route[*].destination.host}' 2>/dev/null \
   | grep -q "$SHADOW"; then
  fail "$SHADOW appears as a route destination - it must be the 'mirror' target, not a weighted destination. As a route entry its responses would reach callers"
fi

extra=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[2]}' 2>/dev/null)
[[ -z "$extra" ]] || fail "the VirtualService has more than 2 http rules - the specification asks for exactly two"

# --- 4. the proxy holds both features ----------------------------------------
routes=$(istioctl proxy-config routes deploy/tester -n "$NS" -o json 2>/dev/null)
[[ -n "$routes" ]] || fail "could not read the tester proxy's route config"
grep -q 'weightedClusters' <<<"$routes" || fail "the tester proxy holds no weightedClusters - the weights never reached the sidecar"
grep -q 'requestMirrorPolicies' <<<"$routes" || fail "the tester proxy holds no requestMirrorPolicies - the mirror never reached the sidecar"

# --- 5. internal testers bypass the split ------------------------------------
for i in 1 2 3 4 5; do
  a=$(kubectl -n "$NS" exec deploy/tester -- \
    curl -s --max-time 10 -X POST -H "x-internal: true" http://notification-service/notify 2>/dev/null)
  [[ "$a" == "$V2" ]] \
    || fail "a request with header 'x-internal: true' returned '$a', expected $V2 every time"
done

# --- 6. the split, and the shadow, measured together -------------------------
before=$(kubectl -n "$NS" logs -l app="$SHADOW" -c istio-proxy --tail=-1 2>/dev/null | grep -c -- "-shadow")

out=$(kubectl -n "$NS" exec deploy/tester -- sh -c \
  'for i in $(seq 1 200); do curl -s --max-time 10 -X POST http://notification-service/notify; echo; done' 2>/dev/null)
[[ -n "$out" ]] || fail "no responses to ordinary traffic"

sleep 3
after=$(kubectl -n "$NS" logs -l app="$SHADOW" -c istio-proxy --tail=-1 2>/dev/null | grep -c -- "-shadow")
copies=$((after - before))

n1=$(grep -cxF "$V1" <<<"$out")
n2=$(grep -cxF "$V2" <<<"$out")
total=$((n1 + n2))
[[ "$total" -ge 180 ]] || fail "only $total of 200 requests produced a recognisable answer - something is failing rather than splitting"

[[ "$n2" -gt 0 ]] || fail "all $total ordinary requests reached v1 - the weighted rule is not splitting"
[[ "$n1" -gt 0 ]] || fail "all $total ordinary requests reached v2 - check the weights are on the right subsets"

pct1=$(( n1 * 100 / total ))
if [[ "$pct1" -lt 65 || "$pct1" -gt 92 ]]; then
  fail "v1 received ${pct1}% of $total ordinary requests, expected roughly 80% (accepted band 65-92%)"
fi

[[ "$copies" -gt 0 ]] \
  || fail "$SHADOW received 0 mirrored requests out of $total. Callers are served correctly, which proves nothing - check that 'mirror' is on the SECOND rule and that $SHADOW has a ready endpoint"
[[ "$copies" -ge 150 ]] \
  || fail "$SHADOW received only $copies copies of $total ordinary requests, well short of 100%. Check mirrorPercentage on the second rule"

echo "PASS: header rule pins internal traffic to v2; the catch-all rule split ${pct1}% of ${total} requests to v1 at a nominal 80/20 and mirrored ${copies} copies to ${SHADOW}; the proxy holds both weightedClusters and requestMirrorPolicies; all four Deployments still run 1 replica"
exit 0
