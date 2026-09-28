#!/usr/bin/env bash
# Section 030 capstone. Confirms host-level consistent hashing pins a session to
# one stable endpoint, that a subset-level LEAST_REQUEST override applies to the
# canary only, that no caller response comes from the canary, and that the canary
# still receives the mirrored copies.

set -u

NS="sessions"
SVC="httpbin"

fail() { echo "FAIL: $*"; exit 1; }

distinct_endpoints() {
  local n="$1"; shift
  kubectl -n "$NS" exec deploy/tester -- sh -c \
    "for i in \$(seq 1 $n); do curl -s -o /dev/null --max-time 10 $* ; done" >/dev/null 2>&1
  sleep 2
  kubectl -n "$NS" logs deploy/tester -c istio-proxy --tail="$n" 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080' | sort -u
}

# --- 0. the environment is intact -------------------------------------------
s=$(kubectl -n "$NS" get deployment httpbin-stable -o jsonpath='{.spec.replicas}' 2>/dev/null)
c=$(kubectl -n "$NS" get deployment httpbin-canary -o jsonpath='{.spec.replicas}' 2>/dev/null)
[[ "$s" == "3" ]] || fail "httpbin-stable runs $s replicas, expected 3"
[[ "$c" == "2" ]] || fail "httpbin-canary runs $c replicas, expected 2"
for d in httpbin-stable httpbin-canary tester; do
  r=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$r" && "$r" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas"
done
sel=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.selector}' 2>/dev/null)
grep -q 'version' <<<"$sel" && fail "the $SVC Service selector is $sel - it must keep selecting on app only"

# record the canary pod IPs so we can tell caller traffic from mirrored traffic
canary_ips=$(kubectl -n "$NS" get pods -l app=httpbin,version=canary \
  -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' 2>/dev/null | sed '/^$/d')
[[ -n "$canary_ips" ]] || fail "could not read the canary pod IPs"

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
[[ "$hdr" == "x-session" ]] \
  || fail "the HOST-level trafficPolicy does not hash on header x-session (found '$hdr')"

csimple=$(kubectl -n "$NS" get destinationrule "$SVC" \
  -o jsonpath="{.spec.subsets[?(@.name=='canary')].trafficPolicy.loadBalancer.simple}" 2>/dev/null)
[[ "$csimple" == "LEAST_REQUEST" ]] \
  || fail "the canary subset does not override with simple: LEAST_REQUEST (found '$csimple')"

stp=$(kubectl -n "$NS" get destinationrule "$SVC" \
  -o jsonpath="{.spec.subsets[?(@.name=='stable')].trafficPolicy}" 2>/dev/null)
[[ -z "$stp" ]] \
  || fail "the stable subset carries its own trafficPolicy ($stp) - it must inherit the host-level one. A subset policy REPLACES rather than merges"

# --- 2. the VirtualService shape --------------------------------------------
kubectl -n "$NS" get virtualservice "$SVC" >/dev/null 2>&1 \
  || fail "VirtualService '$SVC' not found in $NS"

rs=$(kubectl -n "$NS" get virtualservice "$SVC" \
  -o jsonpath='{.spec.http[0].route[0].destination.subset}' 2>/dev/null)
[[ "$rs" == "stable" ]] || fail "the route sends to subset '$rs', expected stable"

extra_dest=$(kubectl -n "$NS" get virtualservice "$SVC" \
  -o jsonpath='{.spec.http[0].route[1].destination}' 2>/dev/null)
[[ -z "$extra_dest" ]] \
  || fail "the route block holds more than one destination - the canary must be the mirror target, not a weighted destination"

ms=$(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{.spec.http[0].mirror.subset}' 2>/dev/null)
[[ "$ms" == "canary" ]] \
  || fail "the mirror targets subset '$ms', expected canary. 'mirror' is a sibling of 'route' on the same rule"

mp=$(kubectl -n "$NS" get virtualservice "$SVC" \
  -o jsonpath='{.spec.http[0].mirrorPercentage.value}' 2>/dev/null)
case "$mp" in
  100|100.0) ;;
  "") fail "mirrorPercentage is not set - the task asks for it explicitly" ;;
  *)  fail "mirrorPercentage.value is '$mp', expected 100" ;;
esac

extra_rule=$(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{.spec.http[1]}' 2>/dev/null)
[[ -z "$extra_rule" ]] || fail "the VirtualService has more than one http rule - the specification asks for exactly one"

# --- 3. the two clusters carry different policies ---------------------------
dump=$(istioctl proxy-config cluster deploy/tester -n "$NS" \
  --fqdn "httpbin.${NS}.svc.cluster.local" -o json 2>/dev/null)
[[ -n "$dump" ]] || fail "could not read the tester proxy's cluster config"

read_pol() {
  python3 - "$dump" "$1" <<'PY' 2>/dev/null
import json,sys
want=sys.argv[2]
for c in json.loads(sys.argv[1]):
    parts=c.get("name","").split("|")
    if len(parts)>2 and parts[2]==want:
        # Envoy omits lbPolicy from the dump when it is the default
        # ROUND_ROBIN, so an absent field means ROUND_ROBIN, not "no cluster".
        print(c.get("lbPolicy","ROUND_ROBIN")); break
PY
}
pol_stable=$(read_pol stable)
pol_canary=$(read_pol canary)
[[ -n "$pol_stable" && -n "$pol_canary" ]] \
  || fail "could not find both the stable and canary clusters in the proxy dump"
[[ "$pol_stable" == "RING_HASH" ]] \
  || fail "the stable cluster's lbPolicy is '$pol_stable', expected RING_HASH (Envoy's name for consistentHash)"
[[ "$pol_canary" == "LEAST_REQUEST" ]] \
  || fail "the canary cluster's lbPolicy is '$pol_canary', expected LEAST_REQUEST - the subset override did not take effect"

# --- 4. the client proxy holds a mirror policy ------------------------------
routes=$(istioctl proxy-config routes deploy/tester -n "$NS" -o json 2>/dev/null)
grep -q 'requestMirrorPolicies' <<<"$routes" \
  || fail "the tester proxy holds no requestMirrorPolicies - the mirror never reached the sidecar"

# --- 5. affinity on stable, and no caller traffic to canary -----------------
eps=$(distinct_endpoints 12 '-H "x-session: alice" http://httpbin:8000/get')
n=$(wc -l <<<"$eps" | tr -d ' ')
[[ "$n" == "1" ]] \
  || fail "12 requests with x-session: alice reached $n distinct endpoints, expected exactly 1. The host-level consistentHash is not pinning"

while IFS= read -r ip; do
  [[ -z "$ip" ]] && continue
  if grep -q "^${ip}:8080$" <<<"$eps"; then
    fail "caller traffic reached canary pod $ip. The canary must be a mirror target only - check it is not also a route destination"
  fi
done <<<"$canary_ips"

# --- 6. nothing to hash falls back to spreading -----------------------------
eps2=$(distinct_endpoints 12 'http://httpbin:8000/get')
n2=$(wc -l <<<"$eps2" | tr -d ' ')
[[ "$n2" -ge 2 ]] \
  || fail "12 requests with NO x-session header reached only $n2 endpoint. A request with nothing to hash must fall back to normal load balancing"

# --- 7. the canary really receives the copies -------------------------------
# No caller traffic is routed to the canary, so every request its proxy logs is
# a mirrored copy. (Istio 1.30 no longer appends a "-shadow" authority suffix.)
canary_hits() {
  kubectl -n "$NS" logs -l app=httpbin,version=canary -c istio-proxy --tail=-1 2>/dev/null \
    | grep -c 'GET /get'
}
sleep 2   # let the previous step's access logs flush before the baseline
before=$(canary_hits)
kubectl -n "$NS" exec deploy/tester -- sh -c \
  'for i in $(seq 1 40); do curl -s -o /dev/null --max-time 10 -H "x-session: alice" http://httpbin:8000/get; done' >/dev/null 2>&1
sleep 3
after=$(canary_hits)
copies=$((after - before))

[[ "$copies" -gt 0 ]] \
  || fail "the canary received 0 mirrored requests out of 40. Callers are served correctly, which proves nothing - check the mirror subset and that canary has ready endpoints"
[[ "$copies" -ge 30 ]] \
  || fail "the canary received only $copies copies of 40, well short of 100%. Check mirrorPercentage"

echo "PASS: host-level consistentHash pins x-session to one stable endpoint (lbPolicy $pol_stable), the canary subset overrides to $pol_canary, no caller traffic reached a canary pod, unheaded requests spread across $n2 endpoints, and the canary logged $copies mirrored copies for the 40 requests sent"
exit 0
