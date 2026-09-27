#!/usr/bin/env bash
# Confirms a POST rule with retries disabled sits above a catch-all read rule
# that retries on gateway errors, that the read timeout genuinely covers the
# full retry budget, and that live traffic produces 4 server-side attempts for a
# retried read and exactly 1 for a POST.

set -u

NS="resilience-demo"
VS="httpbin"

fail() { echo "FAIL: $*"; exit 1; }

# count requests reaching the SERVER for a path, around one client call
server_attempts() {
  local path="$1"; shift
  local before after
  before=$(kubectl -n "$NS" logs deploy/httpbin -c istio-proxy --tail=-1 2>/dev/null | grep -c -- "$path")
  kubectl -n "$NS" exec deploy/tester -- \
    curl -s -o /dev/null --max-time 30 "$@" "http://httpbin:8000${path}" >/dev/null 2>&1
  sleep 3
  after=$(kubectl -n "$NS" logs deploy/httpbin -c istio-proxy --tail=-1 2>/dev/null | grep -c -- "$path")
  echo $((after - before))
}

# --- 0. the environment is intact -------------------------------------------
for d in httpbin tester; do
  r=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$r" && "$r" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas"
done

# --- 1. the VirtualService shape --------------------------------------------
kubectl -n "$NS" get virtualservice "$VS" >/dev/null 2>&1 \
  || fail "VirtualService '$VS' not found in $NS"

m=$(kubectl -n "$NS" get virtualservice "$VS" \
  -o jsonpath='{.spec.http[0].match[0].method.exact}' 2>/dev/null)
[[ "$m" == "POST" ]] \
  || fail "the FIRST http rule does not match method POST (found '$m'). Rules are evaluated top down and the catch-all read rule would swallow everything if it came first"

post_attempts_cfg=$(kubectl -n "$NS" get virtualservice "$VS" \
  -o jsonpath='{.spec.http[0].retries.attempts}' 2>/dev/null)
[[ "$post_attempts_cfg" == "0" ]] \
  || fail "the POST rule has retries.attempts='$post_attempts_cfg', expected 0. Leaving the retries block out is NOT the same thing - Istio applies a default policy of 2 attempts on connection-level failures"

post_timeout=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[0].timeout}' 2>/dev/null)
[[ "$post_timeout" == "3s" ]] || fail "the POST rule's timeout is '$post_timeout', expected 3s"

read_match=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[1].match}' 2>/dev/null)
[[ -z "$read_match" ]] \
  || fail "the SECOND http rule carries a match block ($read_match) - it must be the catch-all default"

a=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[1].retries.attempts}' 2>/dev/null)
p=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[1].retries.perTryTimeout}' 2>/dev/null)
ro=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[1].retries.retryOn}' 2>/dev/null)
t=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[1].timeout}' 2>/dev/null)

[[ "$a" == "3" ]]  || fail "the read rule has retries.attempts='$a', expected 3"
[[ "$p" == "1s" ]] || fail "the read rule has perTryTimeout='$p', expected 1s"
grep -q 'gateway-error' <<<"$ro" \
  || fail "the read rule has retryOn='$ro', which does not include gateway-error"
[[ -n "$t" ]] || fail "the read rule has no timeout - the task requires one large enough for the whole retry budget"

# --- 2. the budget arithmetic ------------------------------------------------
secs() { printf '%s' "${1%s}"; }
tsec=$(secs "$t"); psec=$(secs "$p")
case "$tsec" in ''|*[!0-9.]*) fail "could not parse the read timeout '$t' as seconds - use a plain value like 5s" ;; esac
need=$(python3 -c "print((${a} + 1) * ${psec})" 2>/dev/null)
ok=$(python3 -c "print(1 if ${tsec} >= ${need} else 0)" 2>/dev/null)
[[ "$ok" == "1" ]] \
  || fail "the read timeout is ${t} but (attempts + 1) x perTryTimeout = ${need}s. A timeout shorter than the budget silently truncates the retries and the caller gets a 504 instead of a retried result"

# --- 3. the proxy received it ------------------------------------------------
routes=$(istioctl proxy-config routes deploy/tester -n "$NS" -o json 2>/dev/null)
grep -q 'numRetries' <<<"$routes" \
  || fail "the tester proxy holds no retry policy - the VirtualService exists but never reached the sidecar"

# --- 4. live behaviour: the read path retries -------------------------------
n=$(server_attempts /status/503)
[[ "$n" -eq 4 ]] \
  || fail "a GET /status/503 produced $n request(s) at the server, expected 4 (the original plus 3 retries). If it was 1, retryOn does not cover a 503 - gateway-error means 502/503/504. If it was fewer than 4, the timeout is truncating the retries"

# --- 5. live behaviour: the write path does not ------------------------------
n=$(server_attempts /status/503 -X POST)
[[ "$n" -eq 1 ]] \
  || fail "a POST /status/503 produced $n requests at the server, expected exactly 1. Either the POST rule is not first, or its retries are not disabled with attempts: 0"

# --- 6. live behaviour: the read timeout fires ------------------------------
res=$(kubectl -n "$NS" exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code} %{time_total}' --max-time 30 http://httpbin:8000/delay/10 2>/dev/null)
code=${res%% *}; took=${res##* }
[[ "$code" == "504" ]] \
  || fail "GET /delay/10 returned '$code', expected 504 - the read rule's timeout should fire"

near=$(python3 -c "print(1 if ${took} >= ${tsec} * 0.8 else 0)" 2>/dev/null)
[[ "$near" == "1" ]] \
  || fail "GET /delay/10 returned 504 after only ${took}s, but the configured timeout is ${t}. That suggests the deadline is shorter than you think or the retries are being cut off early"

echo "PASS: POST rule (timeout ${post_timeout}, attempts 0) sits above the catch-all read rule (timeout ${t}, attempts ${a} x ${p} on ${ro}); a retried read produced 4 server attempts, a POST produced 1, and /delay/10 timed out at ${took}s with a 504"
exit 0
