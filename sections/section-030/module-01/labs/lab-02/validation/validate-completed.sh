#!/usr/bin/env bash
# Confirms cookie-based affinity is attached through portLevelSettings for port
# 8000, that Istio issues the cookie itself (which only happens when ttl is
# set), that a client returning it is pinned to one endpoint, and that a client
# without it is not.

set -u

NS="lb-demo"
SVC="httpbin"
PORT="8000"
COOKIE_NAME="session-id"

fail() { echo "FAIL: $*"; exit 1; }
in_tester() { kubectl -n "$NS" exec deploy/tester -- "$@"; }

# how many distinct endpoints served the last $1 requests, per the tester proxy
distinct_upstreams() {
  kubectl -n "$NS" logs deploy/tester -c istio-proxy --tail="$1" 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080' | sort -u | wc -l | tr -d ' '
}

# --- 0. the environment is still what the lab handed over -------------------
for d in httpbin-stable httpbin-canary tester; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS"
done
[[ "$(kubectl -n "$NS" get deployment httpbin-stable -o jsonpath='{.spec.replicas}')" == "3" ]] \
  || fail "httpbin-stable no longer has 3 replicas - affinity must be shown against an unchanged pool"
[[ "$(kubectl -n "$NS" get deployment httpbin-canary -o jsonpath='{.spec.replicas}')" == "2" ]] \
  || fail "httpbin-canary no longer has 2 replicas - leave the replica counts alone"

# --- 1. the policy is attached at PORT level, not host level ----------------
kubectl -n "$NS" get destinationrule "$SVC" >/dev/null 2>&1 \
  || fail "DestinationRule '$SVC' not found in $NS"

host_lb=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.trafficPolicy.loadBalancer}' 2>/dev/null)
[[ -z "$host_lb" ]] \
  || fail "the policy is set as a host-level loadBalancer - task 1 asks for it through portLevelSettings for port $PORT"

pls_port=$(kubectl -n "$NS" get destinationrule "$SVC" \
  -o jsonpath='{.spec.trafficPolicy.portLevelSettings[0].port.number}' 2>/dev/null)
[[ "$pls_port" == "$PORT" ]] \
  || fail "portLevelSettings names port '$pls_port', expected $PORT - the Service port, not the container port"

cname=$(kubectl -n "$NS" get destinationrule "$SVC" \
  -o jsonpath='{.spec.trafficPolicy.portLevelSettings[0].loadBalancer.consistentHash.httpCookie.name}' 2>/dev/null)
[[ "$cname" == "$COOKIE_NAME" ]] \
  || fail "the hash is on cookie '$cname', expected '$COOKIE_NAME'"

cttl=$(kubectl -n "$NS" get destinationrule "$SVC" \
  -o jsonpath='{.spec.trafficPolicy.portLevelSettings[0].loadBalancer.consistentHash.httpCookie.ttl}' 2>/dev/null)
[[ -n "$cttl" ]] \
  || fail "the cookie has no ttl - without it Istio only hashes a cookie the client already sends, and never issues one"

# --- 2. the proxy really compiled it to a ring hash -------------------------
lb=$(istioctl proxy-config cluster deploy/tester -n "$NS" \
  --fqdn "$SVC.$NS.svc.cluster.local" --port "$PORT" -o json 2>/dev/null | grep -o '"lbPolicy": *"[^"]*"' | head -1)
grep -q 'RING_HASH' <<<"$lb" \
  || fail "the tester's cluster for $SVC:$PORT reports $lb - expected RING_HASH, so the policy has not reached the proxy"

# --- 3. Istio issues the cookie to a client that has none -------------------
setc=$(in_tester curl -s -D - -o /dev/null "http://$SVC:$PORT/get" | tr -d '\r' | grep -i '^set-cookie:' || true)
[[ -n "$setc" ]] \
  || fail "a request with no cookie received no Set-Cookie header - Istio is not issuing the session cookie"
grep -qi "$COOKIE_NAME" <<<"$setc" \
  || fail "a Set-Cookie was issued but does not name '$COOKIE_NAME': $setc"

COOKIE=$(in_tester sh -c "curl -s -D - -o /dev/null http://$SVC:$PORT/get | tr -d '\r' | sed -n 's/^[Ss]et-[Cc]ookie: *\($COOKIE_NAME=[^;]*\).*/\1/p'" | head -1)
[[ -n "$COOKIE" ]] || fail "could not read the issued $COOKIE_NAME cookie back out of the response"

# --- 4. returning the cookie pins the client to one endpoint ----------------
in_tester sh -c "for i in \$(seq 1 12); do curl -s -o /dev/null -H 'Cookie: $COOKIE' http://$SVC:$PORT/get; done"
sleep 2
pinned=$(distinct_upstreams 12)
[[ "$pinned" == "1" ]] \
  || fail "12 requests carrying the same $COOKIE_NAME cookie reached $pinned distinct endpoints, expected 1 - the client is not pinned"

# --- 5. no cookie means no affinity ----------------------------------------
in_tester sh -c "for i in \$(seq 1 16); do curl -s -o /dev/null http://$SVC:$PORT/get; done"
sleep 2
spread=$(distinct_upstreams 16)
[[ "$spread" -ge 2 ]] \
  || fail "16 requests with no cookie all reached one endpoint - requests with nothing to hash should fall back to spreading"

echo "PASS: port-level cookie affinity verified - Istio issues the cookie, a returning client is pinned to one endpoint, and a client without it spreads across $spread"
