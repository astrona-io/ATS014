#!/usr/bin/env bash
# Confirms subsets exist, the VirtualService puts an internal-tester header rule
# ABOVE a 70/30 weighted rule, the proxy holds matching weightedClusters, live
# traffic lands in the right proportion, header traffic bypasses the split, and
# neither Deployment was scaled to fake the result.

set -u

NS="shifting-demo"
SVC="notification-service"
VS="notification"
V1='["EMAIL"]'
V2='["EMAIL","SMS"]'

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is intact -------------------------------------------
for d in notification-service-v1 notification-service-v2 tester; do
  r=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$r" && "$r" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas"
done

for d in notification-service-v1 notification-service-v2; do
  n=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.spec.replicas}' 2>/dev/null)
  [[ "$n" == "1" ]] || fail "$d runs $n replicas, expected 1. Traffic share is a weight, not a pod count - do not scale to change the split"
done

dcount=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$dcount" -eq 3 ]] || fail "$NS holds $dcount deployments, expected exactly 3"

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

# --- 2. the VirtualService shape --------------------------------------------
kubectl -n "$NS" get virtualservice "$VS" >/dev/null 2>&1 \
  || fail "VirtualService '$VS' not found in $NS"

# rule 0 must be the header match to v2
hdr_val=$(kubectl -n "$NS" get virtualservice "$VS" \
  -o jsonpath='{.spec.http[0].match[0].headers.x-internal.exact}' 2>/dev/null)
[[ "$hdr_val" == "true" ]] \
  || fail "the FIRST http rule does not match header x-internal: \"true\" (found '$hdr_val'). Rules are evaluated top down and first match wins, so the internal-tester rule has to be above the weighted one"

hdr_subset=$(kubectl -n "$NS" get virtualservice "$VS" \
  -o jsonpath='{.spec.http[0].route[0].destination.subset}' 2>/dev/null)
[[ "$hdr_subset" == "v2" ]] || fail "the header rule routes to subset '$hdr_subset', expected v2"

# rule 1 must be the weighted split, with no match block
rule1_match=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[1].match}' 2>/dev/null)
[[ -z "$rule1_match" ]] \
  || fail "the SECOND http rule carries a match block ($rule1_match) - the weighted rule must be the catch-all default"

w1=$(kubectl -n "$NS" get virtualservice "$VS" \
  -o jsonpath='{.spec.http[1].route[?(@.destination.subset=="v1")].weight}' 2>/dev/null)
w2=$(kubectl -n "$NS" get virtualservice "$VS" \
  -o jsonpath='{.spec.http[1].route[?(@.destination.subset=="v2")].weight}' 2>/dev/null)
[[ "$w1" == "70" ]] || fail "the weighted rule gives subset v1 weight '$w1', expected 70"
[[ "$w2" == "30" ]] || fail "the weighted rule gives subset v2 weight '$w2', expected 30"

rules=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[2]}' 2>/dev/null)
[[ -z "$rules" ]] || fail "the VirtualService has more than 2 http rules - the specification asks for exactly two"

# --- 3. the proxy received the weights --------------------------------------
routes=$(istioctl proxy-config routes deploy/tester -n "$NS" -o json 2>/dev/null)
[[ -n "$routes" ]] || fail "could not read the tester proxy's route config"
grep -q 'weightedClusters' <<<"$routes" \
  || fail "the tester proxy holds no weightedClusters for $SVC - the VirtualService exists but the weights never reached the sidecar"

# --- 4. header traffic bypasses the split -----------------------------------
for i in 1 2 3 4 5; do
  a=$(kubectl -n "$NS" exec deploy/tester -- \
    curl -s --max-time 10 -X POST -H "x-internal: true" http://notification-service/notify 2>/dev/null)
  [[ "$a" == "$V2" ]] \
    || fail "a request with header 'x-internal: true' returned '$a', expected $V2. It must reach v2 every time, not be part of the 70/30 draw"
done

# --- 5. the split itself, over a meaningful sample --------------------------
out=$(kubectl -n "$NS" exec deploy/tester -- sh -c \
  'for i in $(seq 1 200); do curl -s --max-time 10 -X POST http://notification-service/notify; echo; done' 2>/dev/null)
[[ -n "$out" ]] || fail "no responses to default traffic - check the weighted rule resolves to subsets that have endpoints"

n1=$(grep -cxF "$V1" <<<"$out")
n2=$(grep -cxF "$V2" <<<"$out")
total=$((n1 + n2))
[[ "$total" -ge 180 ]] || fail "only $total of 200 requests produced a recognisable answer - something is failing, not splitting"

[[ "$n2" -gt 0 ]] || fail "all $total default requests reached v1 - the weighted rule is not splitting. Check that both destinations are in ONE route block and that the header rule is not matching ordinary traffic"
[[ "$n1" -gt 0 ]] || fail "all $total default requests reached v2 - check the weights are on the right subsets"

pct1=$(( n1 * 100 / total ))
if [[ "$pct1" -lt 55 || "$pct1" -gt 85 ]]; then
  fail "v1 received ${pct1}% of $total default requests, expected roughly 70% (accepted band 55-85%). The weights look wrong, or a rule above the weighted one is diverting traffic"
fi

echo "PASS: subsets v1/v2 defined, header rule x-internal pins to v2 above a 70/30 weighted default, the proxy holds the matching weightedClusters, ${pct1}% of ${total} default requests reached v1, and both Deployments still run 1 replica"
exit 0
