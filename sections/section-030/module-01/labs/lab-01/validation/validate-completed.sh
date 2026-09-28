#!/usr/bin/env bash
# Confirms host-level consistent hashing pins a user to one stable endpoint,
# that a subset-level ROUND_ROBIN override spreads canary traffic for the SAME
# user value, that a request with nothing to hash falls back to spreading, and
# that the two clusters really carry different lbPolicy values.

set -u

NS="lb-demo"
SVC="httpbin"

fail() { echo "FAIL: $*"; exit 1; }

# Count distinct upstream endpoints the tester proxy chose for the last N calls.
# Returns the count on stdout.
distinct_endpoints() {
  local n="$1"; shift
  kubectl -n "$NS" exec deploy/tester -- sh -c \
    "for i in \$(seq 1 $n); do curl -s -o /dev/null --max-time 10 $* ; done" >/dev/null 2>&1
  sleep 2
  kubectl -n "$NS" logs deploy/tester -c istio-proxy --tail="$n" 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080' | sort -u | wc -l | tr -d ' '
}

# --- 0. the environment is intact -------------------------------------------
s=$(kubectl -n "$NS" get deployment httpbin-stable -o jsonpath='{.spec.replicas}' 2>/dev/null)
c=$(kubectl -n "$NS" get deployment httpbin-canary -o jsonpath='{.spec.replicas}' 2>/dev/null)
[[ "$s" == "3" ]] || fail "httpbin-stable runs $s replicas, expected 3 - three endpoints is the minimum that makes affinity distinguishable from luck"
[[ "$c" == "2" ]] || fail "httpbin-canary runs $c replicas, expected 2"

for d in httpbin-stable httpbin-canary tester; do
  r=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$r" && "$r" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas"
done

sel=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.selector}' 2>/dev/null)
grep -q 'version' <<<"$sel" && fail "the $SVC Service selector is $sel - it must keep selecting on app only"

# --- 1. the DestinationRule shape -------------------------------------------
kubectl -n "$NS" get destinationrule "$SVC" >/dev/null 2>&1 \
  || fail "DestinationRule '$SVC' not found in $NS"

for sub in stable canary; do
  lbl=$(kubectl -n "$NS" get destinationrule "$SVC" \
    -o jsonpath="{.spec.subsets[?(@.name=='$sub')].labels.version}" 2>/dev/null)
  [[ "$lbl" == "$sub" ]] || fail "subset '$sub' selects on version='$lbl', expected version='$sub'"
done

hdr=$(kubectl -n "$NS" get destinationrule "$SVC" \
  -o jsonpath='{.spec.trafficPolicy.loadBalancer.consistentHash.httpHeaderName}' 2>/dev/null)
[[ "$hdr" == "x-user" ]] \
  || fail "the HOST-level trafficPolicy does not hash on header x-user (found '$hdr'). It belongs at spec.trafficPolicy, not inside a subset"

hsimple=$(kubectl -n "$NS" get destinationrule "$SVC" \
  -o jsonpath='{.spec.trafficPolicy.loadBalancer.simple}' 2>/dev/null)
[[ -z "$hsimple" ]] \
  || fail "the host-level loadBalancer also sets simple='$hsimple' - simple and consistentHash are mutually exclusive"

csimple=$(kubectl -n "$NS" get destinationrule "$SVC" \
  -o jsonpath="{.spec.subsets[?(@.name=='canary')].trafficPolicy.loadBalancer.simple}" 2>/dev/null)
[[ "$csimple" == "ROUND_ROBIN" ]] \
  || fail "the canary subset does not override with simple: ROUND_ROBIN (found '$csimple'). The override goes in the subset's own trafficPolicy"

ssimple=$(kubectl -n "$NS" get destinationrule "$SVC" \
  -o jsonpath="{.spec.subsets[?(@.name=='stable')].trafficPolicy}" 2>/dev/null)
[[ -z "$ssimple" ]] \
  || fail "the stable subset carries its own trafficPolicy ($ssimple). A subset policy REPLACES the host one, so this would remove the consistent hashing from stable"

# --- 2. the VirtualService ---------------------------------------------------
kubectl -n "$NS" get virtualservice "$SVC" >/dev/null 2>&1 \
  || fail "VirtualService '$SVC' not found in $NS"

tv=$(kubectl -n "$NS" get virtualservice "$SVC" \
  -o jsonpath='{.spec.http[0].match[0].headers.x-track.exact}' 2>/dev/null)
[[ "$tv" == "canary" ]] \
  || fail "the FIRST http rule does not match header x-track: \"canary\" (found '$tv'). First match wins, so it must sit above the default"

ts=$(kubectl -n "$NS" get virtualservice "$SVC" \
  -o jsonpath='{.spec.http[0].route[0].destination.subset}' 2>/dev/null)
[[ "$ts" == "canary" ]] || fail "the x-track rule routes to subset '$ts', expected canary"

ds=$(kubectl -n "$NS" get virtualservice "$SVC" \
  -o jsonpath='{.spec.http[1].route[0].destination.subset}' 2>/dev/null)
[[ "$ds" == "stable" ]] || fail "the default rule routes to subset '$ds', expected stable"

# --- 3. the two clusters carry different policies ---------------------------
dump=$(istioctl proxy-config cluster deploy/tester -n "$NS" \
  --fqdn "httpbin.${NS}.svc.cluster.local" -o json 2>/dev/null)
[[ -n "$dump" ]] || fail "could not read the tester proxy's cluster config"

pol_stable=$(python3 - "$dump" <<'PY' 2>/dev/null
import json,sys
for c in json.loads(sys.argv[1]):
    if c.get("name","").split("|")[2:3] == ["stable"]:
        # Envoy omits lbPolicy from the dump when it is the default
        # ROUND_ROBIN, so an absent field means ROUND_ROBIN, not "no cluster".
        print(c.get("lbPolicy","ROUND_ROBIN")); break
PY
)
pol_canary=$(python3 - "$dump" <<'PY' 2>/dev/null
import json,sys
for c in json.loads(sys.argv[1]):
    if c.get("name","").split("|")[2:3] == ["canary"]:
        # Envoy omits lbPolicy from the dump when it is the default
        # ROUND_ROBIN, so an absent field means ROUND_ROBIN, not "no cluster".
        print(c.get("lbPolicy","ROUND_ROBIN")); break
PY
)
[[ -n "$pol_stable" && -n "$pol_canary" ]] \
  || fail "could not find both the stable and canary clusters in the proxy dump - check the subsets exist and the push landed"
[[ "$pol_stable" == "RING_HASH" ]] \
  || fail "the stable cluster's lbPolicy is '$pol_stable', expected RING_HASH (Envoy's name for consistentHash)"
[[ "$pol_canary" != "$pol_stable" ]] \
  || fail "the stable and canary clusters both report lbPolicy '$pol_stable' - the subset override did not take effect"

# --- 4. behaviour: affinity on stable ---------------------------------------
n=$(distinct_endpoints 12 '-H "x-user: alice" http://httpbin:8000/get')
[[ "$n" == "1" ]] \
  || fail "12 requests with x-user: alice and no x-track reached $n distinct endpoints, expected exactly 1. The host-level consistentHash is not pinning"

# --- 5. behaviour: the canary override spreads the SAME user ----------------
n=$(distinct_endpoints 12 '-H "x-user: alice" -H "x-track: canary" http://httpbin:8000/get')
[[ "$n" -ge 2 ]] \
  || fail "12 requests with x-track: canary and the same x-user reached only $n endpoint. The canary subset must use ROUND_ROBIN, which spreads regardless of the header"

# --- 6. behaviour: nothing to hash falls back to spreading ------------------
n=$(distinct_endpoints 12 'http://httpbin:8000/get')
[[ "$n" -ge 2 ]] \
  || fail "12 requests with NO x-user header reached only $n endpoint. A request with nothing to hash must fall back to normal load balancing"

echo "PASS: host-level consistentHash pins x-user to one stable endpoint (lbPolicy $pol_stable), the canary subset overrides to $pol_canary and spreads the same user, and unheaded requests fall back to spreading"
exit 0
