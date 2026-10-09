#!/usr/bin/env bash
# Confirms the probe's retry policy re-sends only 503: at most 2 retries, a
# 1-second limit per try, and a route timeout that leaves room for all tries.
# Then counts, at the probe itself, how often each signal really arrived:
# a 503 three times, a 500 and a 502 exactly once.

set -u

NS="starfleet"

fail() { echo "FAIL: $*"; exit 1; }

to_ms() {
  local v="$1"
  case "$v" in
    *ms) python3 -c "print(int(float('${v%ms}')))" 2>/dev/null ;;
    *s)  python3 -c "print(int(float('${v%s}')*1000))" 2>/dev/null ;;
    *m)  python3 -c "print(int(float('${v%m}')*60000))" 2>/dev/null ;;
    *)   echo "" ;;
  esac
}

# --- 0. the ships are still what the lab handed over ---------------------------
for d in probe-v1 probe-v2 shuttle; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the ships alone: the fix belongs in the flight plan"
done

# --- 1. the flight plan -------------------------------------------------------------
kubectl -n "$NS" get virtualservice probe >/dev/null 2>&1 || fail "VirtualService 'probe' not found in $NS"
n=$(kubectl -n "$NS" get virtualservice probe -o jsonpath='{.spec.http[*].route[0].destination.host}' | wc -w | tr -d ' ')
[[ "$n" -eq 1 ]] || fail "the probe flight plan has $n rules, expected exactly 1 rule that routes to the probe"

attempts=$(kubectl -n "$NS" get virtualservice probe -o jsonpath='{.spec.http[0].retries.attempts}')
[[ "$attempts" == "2" ]] || fail "retries.attempts is '$attempts', expected 2 (two retries after the first try)"

retry_on=$(kubectl -n "$NS" get virtualservice probe -o jsonpath='{.spec.http[0].retries.retryOn}')
case ",$retry_on," in
  *",5xx,"*|*",gateway-error,"*) fail "retryOn is '$retry_on'. '5xx' and 'gateway-error' also re-send other errors. Retry only the exact status code 503" ;;
esac
grep -qE '(^|,)503(,|$)' <<<"$retry_on" || fail "retryOn is '$retry_on', expected the exact status code \"503\""

per=$(kubectl -n "$NS" get virtualservice probe -o jsonpath='{.spec.http[0].retries.perTryTimeout}')
per_ms=$(to_ms "$per")
[[ -n "$per_ms" && "$per_ms" -le 1000 && "$per_ms" -gt 0 ]] || fail "retries.perTryTimeout is '$per', expected at most 1s"

to=$(kubectl -n "$NS" get virtualservice probe -o jsonpath='{.spec.http[0].timeout}')
to_ms_v=$(to_ms "$to")
need=$(( (attempts + 1) * per_ms ))
[[ -n "$to_ms_v" ]] || fail "the probe rule has no timeout ('$to'). Set a route timeout that leaves room for all three tries"
[[ "$to_ms_v" -ge "$need" ]] || fail "the route timeout $to is shorter than (attempts + 1) x perTryTimeout = ${need}ms. The abort window would cut the retries short"

# --- 2. count the signals at the probe ---------------------------------------------
count_at_probe() {  # $1 status code; prints how many copies of one tagged signal reached the probe
  local tag="grader$RANDOM$RANDOM"
  kubectl -n "$NS" exec deploy/shuttle -- curl -s -o /dev/null --max-time 15 "http://probe:8000/status/$1?t=$tag" >/dev/null 2>&1
  sleep 5
  kubectl -n "$NS" logs -l app=probe -c istio-proxy --since=60s --tail=-1 2>/dev/null | grep -c "$tag"
}

ok=""
for i in $(seq 1 10); do
  c503=$(count_at_probe 503)
  [[ "$c503" == "3" ]] && { ok=1; break; }
  sleep 3
done
[[ -n "$ok" ]] || fail "one signal to /status/503 reached the probe $c503 times, expected 3 (the first try and 2 retries). Check that the policy has reached the shuttle's proxy"

c500=$(count_at_probe 500)
[[ "$c500" == "1" ]] || fail "one signal to /status/500 reached the probe $c500 times, expected 1. A 500 is an app bug: it must not be retried"
c502=$(count_at_probe 502)
[[ "$c502" == "1" ]] || fail "one signal to /status/502 reached the probe $c502 times, expected 1. Only 503 may be retried"

echo "PASS: the probe flight plan retries only 503 (attempts $attempts, perTryTimeout $per, timeout $to); at the probe a 503 arrived 3 times, a 500 and a 502 once each"
