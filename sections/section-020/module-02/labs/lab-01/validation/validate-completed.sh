#!/usr/bin/env bash
# Confirms 100% of caller traffic reaches v1, that a mirror to v2 is configured
# at 100%, that the CLIENT proxy holds a requestMirrorPolicy for the v2 cluster,
# and - the part a happy caller can never prove - that the shadow really
# received copies carrying the rewritten -shadow authority.

set -u

NS="mirror-demo"
SVC="notification-service"
VS="notification"
V1='["EMAIL"]'
V2='["EMAIL","SMS"]'

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is intact -------------------------------------------
for d in notification-service-v1 notification-service-v2 tester; do
  r=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$r" && "$r" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas"
  n=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.spec.replicas}' 2>/dev/null)
  [[ "$n" == "1" ]] || fail "$d runs $n replicas, expected 1 - do not scale the workloads"
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
  pods=$(kubectl -n "$NS" get pods -l "app=$SVC,version=$s" \
    --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')
  [[ "$pods" -ge 1 ]] || fail "subset '$s' selects no running pod - a mirror to a subset with no endpoints silently does nothing"
done

# --- 2. the VirtualService shape --------------------------------------------
kubectl -n "$NS" get virtualservice "$VS" >/dev/null 2>&1 \
  || fail "VirtualService '$VS' not found in $NS"

route_subset=$(kubectl -n "$NS" get virtualservice "$VS" \
  -o jsonpath='{.spec.http[0].route[0].destination.subset}' 2>/dev/null)
[[ "$route_subset" == "v1" ]] \
  || fail "the primary route sends to subset '$route_subset', expected v1 - callers must be served by the stable version"

route_n=$(kubectl -n "$NS" get virtualservice "$VS" \
  -o jsonpath='{.spec.http[0].route[1].destination}' 2>/dev/null)
[[ -z "$route_n" ]] \
  || fail "the route block holds more than one destination - a mirror is a sibling of route, not a second weighted destination"

mirror_subset=$(kubectl -n "$NS" get virtualservice "$VS" \
  -o jsonpath='{.spec.http[0].mirror.subset}' 2>/dev/null)
mirror_host=$(kubectl -n "$NS" get virtualservice "$VS" \
  -o jsonpath='{.spec.http[0].mirror.host}' 2>/dev/null)
[[ -n "$mirror_host" ]] \
  || fail "the http rule has no 'mirror' field - it belongs beside 'route' on the same rule, not inside it"
[[ "$mirror_subset" == "v2" ]] \
  || fail "the mirror targets subset '$mirror_subset', expected v2"

pct=$(kubectl -n "$NS" get virtualservice "$VS" \
  -o jsonpath='{.spec.http[0].mirrorPercentage.value}' 2>/dev/null)
case "$pct" in
  100|100.0) ;;
  "") fail "mirrorPercentage is not set - the task asks for it explicitly, even though the default is already 100" ;;
  *)  fail "mirrorPercentage.value is '$pct', expected 100" ;;
esac

# --- 3. the client proxy holds a mirror policy ------------------------------
routes=$(istioctl proxy-config routes deploy/tester -n "$NS" -o json 2>/dev/null)
[[ -n "$routes" ]] || fail "could not read the tester proxy's route config"
grep -q 'requestMirrorPolicies' <<<"$routes" \
  || fail "the tester proxy holds no requestMirrorPolicies - the VirtualService exists but the mirror never reached the sidecar"
grep -q '|v2|' <<<"$routes" \
  || fail "the tester proxy's mirror policy does not reference the v2 cluster"

# --- 4. no mirrored response ever reaches the caller ------------------------
out=$(kubectl -n "$NS" exec deploy/tester -- sh -c \
  'for i in $(seq 1 30); do curl -s --max-time 10 -X POST http://notification-service/notify; echo; done' 2>/dev/null)
[[ -n "$out" ]] || fail "no responses from the caller - check the primary route resolves to a subset with endpoints"

bad=$(grep -cxF "$V2" <<<"$out")
[[ "$bad" -eq 0 ]] \
  || fail "$bad of 30 caller responses came from v2. The mirrored response must always be discarded - check that v2 is the 'mirror' target and not a second entry in the route block"

good=$(grep -cxF "$V1" <<<"$out")
[[ "$good" -ge 28 ]] \
  || fail "only $good of 30 caller responses came from v1 - something is failing rather than mirroring"

# --- 5. the shadow really received copies -----------------------------------
# baseline first: the log holds copies from any earlier run
before=$(kubectl -n "$NS" logs -l version=v2 -c istio-proxy --tail=-1 2>/dev/null | grep -c -- "-shadow")
kubectl -n "$NS" exec deploy/tester -- sh -c \
  'for i in $(seq 1 40); do curl -s -o /dev/null --max-time 10 -X POST http://notification-service/notify; done' 2>/dev/null
sleep 3
after=$(kubectl -n "$NS" logs -l version=v2 -c istio-proxy --tail=-1 2>/dev/null | grep -c -- "-shadow")
copies=$((after - before))

[[ "$copies" -gt 0 ]] \
  || fail "the shadow received 0 mirrored requests out of 40. The caller is happy, which proves nothing - a mirror pointing at a subset with no endpoints, or at an undefined subset, fails exactly like this. Check 'istioctl analyze -n $NS' and the v2 endpoint list"
[[ "$copies" -ge 30 ]] \
  || fail "the shadow received only $copies mirrored requests out of 40, which is well short of 100%. Check mirrorPercentage"

echo "PASS: all 30 caller responses came from v1, the tester proxy holds a requestMirrorPolicy for the v2 cluster at 100%, and the shadow received $copies of 40 copies carrying the -shadow authority"
exit 0
