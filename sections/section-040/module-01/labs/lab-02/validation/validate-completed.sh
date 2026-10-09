#!/usr/bin/env bash
# Confirms the timeout sits on the caller's route: navcom keeps its 3s
# delay fault (with no useless timeout on the same route), jason's rule in the
# scout VirtualService has a timeout of at most 1s, and live requests prove it:
# jason gets a 504 made by the shuttle's own sidecar within about a second,
# everyone else still gets a fast 200.

set -u

NS="starfleet"

fail() { echo "FAIL: $*"; exit 1; }

to_ms() {  # "1s" "0.5s" "500ms" "1m" -> milliseconds, empty if unparsable
  local v="$1"
  case "$v" in
    *ms) python3 -c "print(int(float('${v%ms}')))" 2>/dev/null ;;
    *s)  python3 -c "print(int(float('${v%s}')*1000))" 2>/dev/null ;;
    *m)  python3 -c "print(int(float('${v%m}')*60000))" 2>/dev/null ;;
    *)   echo "" ;;
  esac
}

# --- 0. the deployments are still what the lab handed over ---------------------
for d in bridge-v1 cargo-v1 navcom-v1 scout-v1 scout-v2 scout-v3 shuttle; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the deployments alone: the fix belongs in the VirtualServices"
done
deploy_count=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$deploy_count" -eq 7 ]] || fail "$NS holds $deploy_count deployments, expected exactly 7 - do not add or remove deployments"

# --- 1. navcom keeps the delay fault, without a timeout ------------------------
kubectl -n "$NS" get virtualservice navcom >/dev/null 2>&1 \
  || fail "VirtualService 'navcom' not found in $NS. Keep the delay fault on navcom - only move the timeout"
delay=$(kubectl -n "$NS" get virtualservice navcom -o jsonpath='{.spec.http[0].fault.delay.fixedDelay}' 2>/dev/null)
pct=$(kubectl -n "$NS" get virtualservice navcom -o jsonpath='{.spec.http[0].fault.delay.percentage.value}' 2>/dev/null)
[[ "$delay" == "3s" ]] || fail "navcom's first rule delays requests by '$delay', expected 3s. Keep the delay fault as it is - it simulates a slow navcom backend"
[[ "$pct" == "100" ]] || fail "navcom's delay applies to '$pct' percent of requests, expected 100"
nav_to=$(kubectl -n "$NS" get virtualservice navcom -o jsonpath='{.spec.http[*].timeout}' 2>/dev/null)
[[ -z "$nav_to" ]] || fail "the navcom VirtualService still has timeout '$nav_to'. A route with a fault ignores its own timeout, so it does nothing there. Remove it and put the timeout on the caller's route instead"

# --- 2. jason's scout rule has the timeout --------------------------------------
kubectl -n "$NS" get virtualservice scout >/dev/null 2>&1 || fail "VirtualService 'scout' not found in $NS"
first=$(kubectl -n "$NS" get virtualservice scout -o jsonpath='{.spec.http[0].match[0].headers.end-user.exact}|{.spec.http[0].route[0].destination.subset}' 2>/dev/null)
[[ "$first" == "jason|v2" ]] || fail "the first scout rule is '$first', expected end-user=jason to subset v2. Keep the routing as it is and only add the timeout"
last=$(kubectl -n "$NS" get virtualservice scout -o jsonpath='{.spec.http[-1:].route[0].destination.subset}' 2>/dev/null)
[[ "$last" == "v1" ]] || fail "the last scout rule sends to '$last', expected the catch-all to subset v1"
to=$(kubectl -n "$NS" get virtualservice scout -o jsonpath='{.spec.http[0].timeout}' 2>/dev/null)
[[ -n "$to" ]] || fail "jason's scout rule has no timeout. The timeout belongs on the route the shuttle uses: the scout VirtualService"
ms=$(to_ms "$to")
[[ -n "$ms" ]] || fail "could not read jason's timeout '$to'"
[[ "$ms" -le 1000 && "$ms" -gt 0 ]] || fail "jason's timeout is $to, expected at most 1s"

# --- 3. live requests -------------------------------------------------------------
probe_jason() {
  kubectl -n "$NS" exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}" \
    --max-time 10 -H "end-user: jason" http://scout:9080/reviews/0 2>/dev/null
}
ok=""
for i in $(seq 1 20); do
  read -r code t <<<"$(probe_jason)"
  if [[ "$code" == "504" ]] && python3 -c "import sys; sys.exit(0 if float('$t') <= 1.6 else 1)"; then ok=1; break; fi
  sleep 3
done
jt="$t"
[[ -n "$ok" ]] || fail "jason's request returned '$code' after ${t}s, expected 504 within about 1s. Check that the timeout is on jason's rule in the scout VirtualService and has reached the shuttle's proxy"

found=""
for i in $(seq 1 10); do
  if kubectl -n "$NS" logs deploy/shuttle -c istio-proxy --tail=20 2>/dev/null | grep -q '" 504 UT '; then found=1; break; fi
  sleep 2
done
[[ -n "$found" ]] || fail "the shuttle's access log shows no '504 UT' line. The 504 must be made by the shuttle's own sidecar when the timeout runs out"

read -r code t <<<"$(kubectl -n "$NS" exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}" --max-time 10 http://scout:9080/reviews/0 2>/dev/null)"
[[ "$code" == "200" ]] || fail "a request without jason's header returned '$code', expected 200 from scout v1"
python3 -c "import sys; sys.exit(0 if float('$t') < 1.0 else 1)" \
  || fail "a request without jason's header took ${t}s, expected well under a second (scout v1 never calls navcom)"

echo "PASS: navcom keeps its 3s delay fault with no timeout, jason's scout rule has timeout $to, jason gets 504 UT after ${jt}s from the shuttle's own sidecar, and everyone else still gets a fast 200"
