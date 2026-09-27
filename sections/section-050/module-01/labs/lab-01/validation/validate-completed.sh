#!/usr/bin/env bash
# Confirms a header-scoped fault affects only marked requests, that unmarked
# traffic is untouched, that the fault lives on the callee's VirtualService but
# is enforced in the caller's proxy, and that a 7s delay against a 3s timeout
# makes the timeout fire.

set -u

NS="fault-demo"
VS="notification"

fail() { echo "FAIL: $*"; exit 1; }

run_curl() {
  kubectl -n "$NS" run "vt$RANDOM" --rm -i --restart=Never --image=curlimages/curl --quiet -- \
    curl -s -o /dev/null -w '%{http_code} %{time_total}' --max-time 30 "$@" 2>/dev/null \
    | tail -1
}

# --- 0. the environment is intact -------------------------------------------
for d in booking-service-v1 notification-service-v1; do
  r=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$r" && "$r" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas"
done

# --- 1. the fault is on the right host --------------------------------------
kubectl -n "$NS" get virtualservice "$VS" >/dev/null 2>&1 \
  || fail "VirtualService '$VS' not found in $NS"

hosts=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.hosts[*]}' 2>/dev/null)
grep -qE '(^| )notification-service' <<<"$hosts" \
  || fail "the VirtualService hosts are [$hosts] - the fault belongs on the host you want to pretend is broken, which is notification-service"

for other in $(kubectl -n "$NS" get virtualservice -o name 2>/dev/null); do
  oh=$(kubectl -n "$NS" get "$other" -o jsonpath='{.spec.hosts[*]}' 2>/dev/null)
  of=$(kubectl -n "$NS" get "$other" -o jsonpath='{.spec.http[*].fault}' 2>/dev/null)
  if grep -qE '(^| )booking-service' <<<"$oh" && [[ -n "$of" ]]; then
    fail "$other injects a fault on host booking-service. That delays the INBOUND request from your client - a different experiment. The fault belongs on notification-service"
  fi
done

# --- 2. rule 1: scoped, with both faults and the timeout --------------------
hv=$(kubectl -n "$NS" get virtualservice "$VS" \
  -o jsonpath='{.spec.http[0].match[0].headers.end-user.exact}' 2>/dev/null)
[[ "$hv" == "tester" ]] \
  || fail "the FIRST http rule does not match header end-user: \"tester\" (found '$hv'). An unscoped fault breaks everyone else's traffic"

fd=$(kubectl -n "$NS" get virtualservice "$VS" \
  -o jsonpath='{.spec.http[0].fault.delay.fixedDelay}' 2>/dev/null)
[[ "$fd" == "7s" ]] || fail "the fault delay fixedDelay is '$fd', expected 7s"

dp=$(kubectl -n "$NS" get virtualservice "$VS" \
  -o jsonpath='{.spec.http[0].fault.delay.percentage.value}' 2>/dev/null)
case "$dp" in 100|100.0|"") ;; *) fail "the delay percentage is '$dp', expected 100" ;; esac

fa=$(kubectl -n "$NS" get virtualservice "$VS" \
  -o jsonpath='{.spec.http[0].fault.abort.httpStatus}' 2>/dev/null)
[[ "$fa" == "500" ]] || fail "the fault abort httpStatus is '$fa', expected 500"

ft=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[0].timeout}' 2>/dev/null)
[[ "$ft" == "3s" ]] || fail "the first rule's timeout is '$ft', expected 3s"

# --- 3. rule 2: unscoped, clean ---------------------------------------------
m2=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[1].match}' 2>/dev/null)
[[ -z "$m2" ]] || fail "the SECOND http rule carries a match block ($m2) - it must be the catch-all for everyone else"

f2=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[1].fault}' 2>/dev/null)
[[ -z "$f2" ]] || fail "the SECOND http rule carries a fault ($f2) - unscoped traffic must be untouched"

t2=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[1].timeout}' 2>/dev/null)
[[ -z "$t2" ]] || fail "the SECOND http rule carries a timeout ('$t2') - the task asks for no timeout on the catch-all"

extra=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[2]}' 2>/dev/null)
[[ -z "$extra" ]] || fail "the VirtualService has more than 2 http rules - the specification asks for exactly two"

# --- 4. the fault is in the CALLER's proxy ----------------------------------
routes=$(istioctl proxy-config routes deploy/booking-service-v1 -n "$NS" -o json 2>/dev/null)
[[ -n "$routes" ]] || fail "could not read the booking-service proxy's route config"
grep -qi '"fault"' <<<"$routes" \
  || fail "booking-service's proxy holds no fault filter - the VirtualService exists but never reached the caller's sidecar"

# --- 5. unmarked traffic is untouched ---------------------------------------
for i in 1 2 3 4 5; do
  res=$(run_curl -X POST http://booking-service/book)
  code=${res%% *}; took=${res##* }
  [[ "$code" == "200" ]] \
    || fail "an unmarked POST /book returned '$code', expected 200. The fault is not scoped - check that the header match is on the FIRST rule and that a clean catch-all follows it"
  slow=$(python3 -c "print(1 if ${took:-0} > 1.5 else 0)" 2>/dev/null)
  [[ "$slow" == "0" ]] \
    || fail "an unmarked POST /book took ${took}s, which suggests the delay is affecting unscoped traffic too"
done

# --- 6. marked traffic hits the timeout -------------------------------------
res=$(run_curl -H "end-user: tester" -X POST http://booking-service/book)
code=${res%% *}; took=${res##* }
[[ "$code" != "200" ]] \
  || fail "a POST /book with end-user: tester returned 200. The fault did not apply - note that booking-service must forward the header to the second hop for the match to fire"

inwindow=$(python3 -c "print(1 if 2.0 <= ${took:-0} <= 6.0 else 0)" 2>/dev/null)
[[ "$inwindow" == "1" ]] \
  || fail "the faulted request took ${took}s, expected roughly 3s. A 7s delay behind a 3s timeout should be cut off at the timeout - if it took ~7s the timeout is missing, and if it was instant the delay is not applying"

# --- 7. the UT flag proves the timeout fired --------------------------------
sleep 2
ut=$(kubectl -n "$NS" logs -l app=booking-service -c istio-proxy --tail=60 2>/dev/null \
  | grep -c ' 504 UT ')
[[ "$ut" -gt 0 ]] \
  || fail "no ' 504 UT ' line in booking-service's proxy log. The injected delay should have driven the route timeout; without UT the request ended some other way"

echo "PASS: fault scoped to end-user=tester on the notification-service VirtualService and enforced in booking-service's proxy; the marked request was cut off at ${took}s with a 504 UT while five unmarked requests returned 200 quickly"
exit 0
