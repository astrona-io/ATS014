#!/usr/bin/env bash
# Section 050 capstone. Confirms two independently scoped chaos experiments on
# one host: an abort that a retry policy cannot rescue (3 FI-flagged attempts),
# a delay that drives a timeout (UT), and a clean catch-all that leaves
# everybody else's traffic untouched.

set -u

NS="orders"
VS="notification"

fail() { echo "FAIL: $*"; exit 1; }

run_curl() {
  # A long-lived client Deployment, not an ephemeral `kubectl run` pod: in an
  # injected namespace the sidecar keeps a run-once pod alive after curl exits,
  # so its captured output is unreliable.
  kubectl -n "$NS" exec deploy/tester -- \
    curl -s -o /dev/null -w '%{http_code} %{time_total}' --max-time 30 "$@" 2>/dev/null \
    | tail -1
}
caller_log_count() {
  kubectl -n "$NS" logs -l app=booking-service -c istio-proxy --tail=-1 2>/dev/null | grep -c -- "$1"
}

# --- 0. the environment is intact -------------------------------------------
for d in booking-service-v1 notification-service-v1 tester; do
  r=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$r" && "$r" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas"
done

# --- 1. the object is on the right host -------------------------------------
kubectl -n "$NS" get virtualservice "$VS" >/dev/null 2>&1 \
  || fail "VirtualService '$VS' not found in $NS"
hosts=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.hosts[*]}' 2>/dev/null)
grep -qE '(^| )notification-service' <<<"$hosts" \
  || fail "the VirtualService hosts are [$hosts] - the faults belong on notification-service, the host being made to fail"

# --- 2. rule 1: abort + retries ---------------------------------------------
h0=$(kubectl -n "$NS" get virtualservice "$VS" \
  -o jsonpath='{.spec.http[0].match[0].headers.x-chaos.exact}' 2>/dev/null)
[[ "$h0" == "abort" ]] \
  || fail "the FIRST http rule does not match x-chaos: \"abort\" (found '$h0')"

a0=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[0].fault.abort.httpStatus}' 2>/dev/null)
[[ "$a0" == "503" ]] || fail "rule 1 abort httpStatus is '$a0', expected 503"

ra=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[0].retries.attempts}' 2>/dev/null)
rp=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[0].retries.perTryTimeout}' 2>/dev/null)
ro=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[0].retries.retryOn}' 2>/dev/null)
t0=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[0].timeout}' 2>/dev/null)
[[ "$ra" == "2" ]]  || fail "rule 1 retries.attempts is '$ra', expected 2"
[[ "$rp" == "1s" ]] || fail "rule 1 perTryTimeout is '$rp', expected 1s"
grep -q 'gateway-error' <<<"$ro" || fail "rule 1 retryOn is '$ro', which does not include gateway-error"
[[ "$t0" == "5s" ]] || fail "rule 1 timeout is '$t0', expected 5s"

# --- 3. rule 2: delay + timeout, no retries ---------------------------------
h1=$(kubectl -n "$NS" get virtualservice "$VS" \
  -o jsonpath='{.spec.http[1].match[0].headers.x-chaos.exact}' 2>/dev/null)
[[ "$h1" == "delay" ]] || fail "the SECOND http rule does not match x-chaos: \"delay\" (found '$h1')"

d1=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[1].fault.delay.fixedDelay}' 2>/dev/null)
[[ "$d1" == "7s" ]] || fail "rule 2 delay fixedDelay is '$d1', expected 7s"
t1=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[1].timeout}' 2>/dev/null)
[[ -z "$t1" ]] \
  || fail "rule 2 carries a timeout ('$t1'). Next to the delay it is inert - the fault filter holds the request before the router starts timing it. The 2s timeout belongs on the booking-service object, one hop up"

bt=$(kubectl -n "$NS" get virtualservice booking -o jsonpath='{.spec.http[0].timeout}' 2>/dev/null) \
  || fail "VirtualService 'booking' not found in $NS - the 2s timeout belongs on the booking-service host"
[[ "$bt" == "2s" ]] || fail "the booking-service VirtualService timeout is '$bt', expected 2s"
r1=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[1].retries}' 2>/dev/null)
[[ -z "$r1" ]] || fail "rule 2 carries a retries block ($r1) - the task asks for none on the delay experiment"

# --- 4. rule 3: clean catch-all ---------------------------------------------
m2=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[2].match}' 2>/dev/null)
[[ -z "$m2" ]] || fail "the THIRD http rule carries a match block ($m2) - it must be the catch-all"
for f in fault timeout retries; do
  v=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath="{.spec.http[2].$f}" 2>/dev/null)
  [[ -z "$v" ]] || fail "the THIRD http rule carries a $f ('$v') - unscoped traffic must be completely untouched"
done
extra=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[3]}' 2>/dev/null)
[[ -z "$extra" ]] || fail "the VirtualService has more than 3 http rules - the specification asks for exactly three"

# --- 5. the faults are in the CALLER's proxy --------------------------------
routes=$(istioctl proxy-config routes deploy/booking-service-v1 -n "$NS" -o json 2>/dev/null)
[[ -n "$routes" ]] || fail "could not read booking-service's route config"
# Istio 1.30 writes the fault filter into typedPerFilterConfig under the key
# "envoy.filters.http.fault"; older dumps used a bare "fault". Accept either.
grep -qiE '"(envoy\.filters\.http\.)?fault"' <<<"$routes" \
  || fail "booking-service's proxy holds no fault filter - the VirtualService never reached the caller's sidecar"

# --- 6. unmarked traffic is untouched ---------------------------------------
for i in 1 2 3 4 5; do
  res=$(run_curl -X POST http://booking-service/book)
  code=${res%% *}; took=${res##* }
  [[ "$code" == "200" ]] \
    || fail "an unmarked POST /book returned '$code', expected 200. One of the chaos rules is not scoped, or the catch-all is not last"
  slow=$(python3 -c "print(1 if ${took:-0} > 1.5 else 0)" 2>/dev/null)
  [[ "$slow" == "0" ]] || fail "an unmarked POST /book took ${took}s - a delay is leaking into unscoped traffic"
done

# --- 7. experiment 1: the abort is NOT retried, because it never reaches the router --
before_fi=$(caller_log_count ' FI ')
res=$(run_curl -H "x-chaos: abort" -X POST http://booking-service/book)
code=${res%% *}
[[ "$code" != "200" ]] \
  || fail "a request with x-chaos: abort returned 200. The fault did not apply - booking-service must forward the header to the second hop for the match to fire"
sleep 3
after_fi=$(caller_log_count ' FI ')
attempts=$((after_fi - before_fi))
# One attempt, not three. The fault filter runs before the router and answers
# the request itself, so the router's retry policy is never consulted. This is
# the result the experiment exists to produce.
[[ "$attempts" -eq 1 ]] \
  || fail "the aborted request produced $attempts FI-flagged attempts in booking-service's proxy log, expected exactly 1. An injected abort is a local reply from the fault filter, which sits before the router, so the retry policy never runs"

# --- 8. experiment 2: the delay drives the timeout --------------------------
# The timeout is enforced by the CLIENT's proxy, so that is where UT is logged.
client_ut() {
  kubectl -n "$NS" logs deploy/tester -c istio-proxy --tail=-1 2>/dev/null | grep -c ' 504 UT '
}
before_ut=$(client_ut)
res=$(run_curl -H "x-chaos: delay" -X POST http://booking-service/book)
code=${res%% *}; took=${res##* }
[[ "$code" != "200" ]] || fail "a request with x-chaos: delay returned 200 - the delay rule did not apply"
inwindow=$(python3 -c "print(1 if 1.2 <= ${took:-0} <= 5.0 else 0)" 2>/dev/null)
[[ "$inwindow" == "1" ]] \
  || fail "the delayed request took ${took}s, expected roughly 2s. A 7s delay behind a 2s timeout should be cut off at the timeout"
sleep 2
after_ut=$(client_ut)
[[ $((after_ut - before_ut)) -gt 0 ]] \
  || fail "no new ' 504 UT ' line in the client proxy's log for the delay experiment - the route timeout on booking-service did not fire"

echo "PASS: three scoped rules on the notification-service VirtualService; the abort experiment produced ${attempts} FI-flagged attempt (the retry policy never ran, because the fault filter answered before the router), the delay experiment was cut off at ${took}s with a 504 UT, and five unmarked requests returned 200 quickly"
exit 0
