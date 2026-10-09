#!/usr/bin/env bash
# Confirms both faults: navcom delays every request by 2s (delay), and the
# probe fails every request with 503 (abort). Live requests prove it: jason's
# request through scout v2 still succeeds about 2s late with DI in the access
# log of scout v2's sidecar proxy, and a request to the probe fails at once with
# FI in the shuttle's access log and never reaches the probe.

set -u

NS="starfleet"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the deployments are still what the lab created ------------------------
for d in bridge-v1 cargo-v1 navcom-v1 scout-v1 scout-v2 scout-v3 probe-v1 probe-v2 shuttle; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Do not change the deployments: fault injection belongs in VirtualServices"
done

# --- 1. the scout VirtualService is unchanged -----------------------------------
first=$(kubectl -n "$NS" get virtualservice scout -o jsonpath='{.spec.http[0].match[0].headers.end-user.exact}|{.spec.http[0].route[0].destination.subset}' 2>/dev/null)
[[ "$first" == "jason|v2" ]] || fail "the scout VirtualService no longer sends end-user: jason to subset v2 (found '$first'). Leave it as it was: it sends jason's requests to scout v2, which calls navcom"

# --- 2. the delay fault on navcom ------------------------------------------------
kubectl -n "$NS" get virtualservice navcom >/dev/null 2>&1 \
  || fail "VirtualService 'navcom' not found in $NS. The delay fault goes on the VirtualService of the Service you want to make slow: navcom"
delay=$(kubectl -n "$NS" get virtualservice navcom -o jsonpath='{.spec.http[0].fault.delay.fixedDelay}' 2>/dev/null)
[[ "$delay" == "2s" ]] || fail "navcom's first rule has delay '$delay', expected fault.delay.fixedDelay: 2s"
pct=$(kubectl -n "$NS" get virtualservice navcom -o jsonpath='{.spec.http[0].fault.delay.percentage.value}' 2>/dev/null)
[[ -z "$pct" || "$pct" == "100" ]] || fail "navcom's delay applies to $pct percent of requests, expected every request (100)"
nabort=$(kubectl -n "$NS" get virtualservice navcom -o jsonpath='{.spec.http[*].fault.abort}' 2>/dev/null)
[[ -z "$nabort" ]] || fail "navcom's VirtualService also has an abort. navcom should only be slow, not failing"
nsub=$(kubectl -n "$NS" get virtualservice navcom -o jsonpath='{.spec.http[0].route[0].destination.subset}' 2>/dev/null)
[[ "$nsub" == "v1" ]] || fail "navcom's rule routes to subset '$nsub', expected v1"

# --- 3. the abort fault on the probe --------------------------------------------
kubectl -n "$NS" get virtualservice probe >/dev/null 2>&1 \
  || fail "VirtualService 'probe' not found in $NS. The abort fault goes on the VirtualService of the Service you want to make fail: probe"
status=$(kubectl -n "$NS" get virtualservice probe -o jsonpath='{.spec.http[0].fault.abort.httpStatus}' 2>/dev/null)
[[ "$status" == "503" ]] || fail "the probe's first rule aborts with '$status', expected fault.abort.httpStatus: 503"
pct=$(kubectl -n "$NS" get virtualservice probe -o jsonpath='{.spec.http[0].fault.abort.percentage.value}' 2>/dev/null)
[[ -z "$pct" || "$pct" == "100" ]] || fail "the probe's abort applies to $pct percent of requests, expected every request (100)"
pdelay=$(kubectl -n "$NS" get virtualservice probe -o jsonpath='{.spec.http[*].fault.delay}' 2>/dev/null)
[[ -z "$pdelay" ]] || fail "the probe's VirtualService also has a delay. The probe should fail at once, not slowly"

# --- 4. live: jason's request is slow but succeeds ------------------------------
ok=""
for i in $(seq 1 20); do
  read -r code t <<<"$(kubectl -n "$NS" exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}" \
    --max-time 10 -H "end-user: jason" http://scout:9080/reviews/0 2>/dev/null)"
  if [[ "$code" == "200" ]] && python3 -c "import sys; sys.exit(0 if 1.8 <= float('$t') <= 4.0 else 1)"; then ok=1; break; fi
  sleep 3
done
[[ -n "$ok" ]] || fail "jason's request to scout returned '$code' after ${t}s, expected 200 after about 2s. A delay fault holds the request and then sends it on: the response must still succeed"
jt="$t"

found=""
for i in $(seq 1 10); do
  if kubectl -n "$NS" logs deploy/scout-v2 -c istio-proxy --tail=20 2>/dev/null | grep 'GET /ratings/0' | grep -q '" 200 DI '; then found=1; break; fi
  sleep 2
done
[[ -n "$found" ]] || fail "scout v2's access log shows no '200 DI' line for its request to navcom. The delay must be applied by the caller's sidecar proxy, in scout v2"

# --- 5. live: the probe fails at once and never receives the request -----------
mark="drill-check-$RANDOM$RANDOM"
ok=""
for i in $(seq 1 20); do
  read -r code t <<<"$(kubectl -n "$NS" exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}" \
    --max-time 10 "http://probe:8000/get?$mark" 2>/dev/null)"
  if [[ "$code" == "503" ]] && python3 -c "import sys; sys.exit(0 if float('$t') < 1.0 else 1)"; then ok=1; break; fi
  sleep 3
done
[[ -n "$ok" ]] || fail "a request to the probe returned '$code' after ${t}s, expected 503 at once. An abort fault returns the error without waiting"
pt="$t"

found=""
for i in $(seq 1 10); do
  if kubectl -n "$NS" logs deploy/shuttle -c istio-proxy --tail=40 2>/dev/null | grep "$mark" | grep -q '" 503 FI '; then found=1; break; fi
  sleep 2
done
[[ -n "$found" ]] || fail "the shuttle's access log shows no '503 FI' line for the request to the probe. The abort must be applied by the caller's own sidecar proxy"

arrived=$(kubectl -n "$NS" logs -l app=probe -c istio-proxy --tail=200 2>/dev/null | grep -c "$mark")
[[ "$arrived" -eq 0 ]] || fail "the probe received $arrived of the aborted requests. An abort fault must stop the request before it leaves the shuttle pod"

echo "PASS: navcom is delayed 2s and the probe aborted with 503; jason gets 200 after ${jt}s with DI in scout v2's access log, and the probe request fails with 503 FI after ${pt}s without ever reaching the probe"
