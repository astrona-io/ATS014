#!/usr/bin/env bash
# Confirms the forgotten drill is scoped: navcom's flight plan has exactly two
# rules, the 500 abort for end-user: tester only, then a plain rule. Live
# signals prove it: ordinary scout answers carry star ratings again, tester's
# answers still show the drill, and the shuttle's flight log marks tester's
# direct signal to navcom with FI.

set -u

NS="starfleet"
ERR="Ratings service is currently unavailable"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the ships and the scout flight plan are unchanged -----------------------
for d in bridge-v1 cargo-v1 navcom-v1 scout-v1 scout-v2 scout-v3 shuttle; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the ships alone: the fix belongs in navcom's flight plan"
done
ssub=$(kubectl -n "$NS" get virtualservice scout -o jsonpath='{.spec.http[*].route[*].destination.subset}' 2>/dev/null)
[[ "$ssub" == "v2" ]] || fail "the scout flight plan routes to '$ssub', expected every signal to subset v2. Leave it as it was: scout v2 is the ship that calls navcom"

# --- 1. navcom's flight plan: drill first, plain rule last ---------------------
kubectl -n "$NS" get virtualservice navcom >/dev/null 2>&1 \
  || fail "VirtualService 'navcom' not found in $NS. Keep the drill: scope it, do not delete it"
rules=$(kubectl -n "$NS" get virtualservice navcom -o json 2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin)['spec'].get('http',[])))")
[[ "$rules" == "2" ]] || fail "navcom's flight plan has $rules rule(s), expected exactly 2: the drill for tester first, then a plain rule for everyone else"
user=$(kubectl -n "$NS" get virtualservice navcom -o jsonpath='{.spec.http[0].match[0].headers.end-user.exact}' 2>/dev/null)
[[ "$user" == "tester" ]] || fail "navcom's first rule matches end-user '$user', expected an exact match on 'tester'. The drill rule must come first and match only test signals"
status=$(kubectl -n "$NS" get virtualservice navcom -o jsonpath='{.spec.http[0].fault.abort.httpStatus}' 2>/dev/null)
[[ "$status" == "500" ]] || fail "navcom's first rule aborts with '$status', expected the drill to stay as it was: abort with 500"
pct=$(kubectl -n "$NS" get virtualservice navcom -o jsonpath='{.spec.http[0].fault.abort.percentage.value}' 2>/dev/null)
[[ -z "$pct" || "$pct" == "100" ]] || fail "the drill applies to $pct percent of tester's signals, expected all of them (100)"
lastmatch=$(kubectl -n "$NS" get virtualservice navcom -o jsonpath='{.spec.http[1].match}' 2>/dev/null)
[[ -z "$lastmatch" ]] || fail "navcom's second rule has a match. It must be a plain rule that catches every other signal"
lastfault=$(kubectl -n "$NS" get virtualservice navcom -o jsonpath='{.spec.http[1].fault}' 2>/dev/null)
[[ -z "$lastfault" ]] || fail "navcom's second rule still carries a fault. Everyone who is not tester must be left alone"
for r in 0 1; do
  sub=$(kubectl -n "$NS" get virtualservice navcom -o jsonpath="{.spec.http[$r].route[0].destination.subset}" 2>/dev/null)
  [[ "$sub" == "v1" ]] || fail "navcom's rule $r routes to subset '$sub', expected v1"
done

# --- 2. live: ordinary signals get star ratings again --------------------------
ok=""
for i in $(seq 1 20); do
  body=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 10 http://scout:9080/reviews/0 2>/dev/null)
  if [[ "$body" == *'"stars"'* && "$body" != *"$ERR"* ]]; then ok=1; break; fi
  sleep 3
done
[[ -n "$ok" ]] || fail "an ordinary signal to scout still gets no star rating ('$ERR'). The drill must not touch signals without end-user: tester"

# --- 3. live: tester still meets the drill -------------------------------------
body=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 10 -H "end-user: tester" http://scout:9080/reviews/0 2>/dev/null)
[[ "$body" == *"$ERR"* ]] || fail "tester's signal through scout got star ratings. The drill must still fail every navcom signal that carries end-user: tester"

code=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}" --max-time 10 -H "end-user: tester" http://navcom:9080/ratings/0 2>/dev/null)
[[ "$code" == "500" ]] || fail "tester's signal straight to navcom returned '$code', expected 500 from the drill"
found=""
for i in $(seq 1 10); do
  if kubectl -n "$NS" logs deploy/shuttle -c istio-proxy --tail=20 2>/dev/null | grep 'GET /ratings/0' | grep -q '" 500 FI '; then found=1; break; fi
  sleep 2
done
[[ -n "$found" ]] || fail "the shuttle's flight log shows no '500 FI' line for tester's signal to navcom. The 500 must come from the drill, not from navcom"

code=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://navcom:9080/ratings/0 2>/dev/null)
[[ "$code" == "200" ]] || fail "an ordinary signal straight to navcom returned '$code', expected 200"

echo "PASS: the drill on navcom now only hits end-user: tester (500 FI), and every other signal gets its star ratings again"
