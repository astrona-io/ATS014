#!/usr/bin/env bash
# Confirms the probe's shields (DestinationRule) were left alone, that the
# flight plan (VirtualService) still retries signals that never reached the
# probe but no longer retries the probe's own 5xx answers, and - the part that
# matters - that 5 failing signals reach the probe exactly 5 times.

set -u

NS="starfleet"
SVC="probe"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the ships are still what the lab handed over -------------------------
for d in shuttle probe-v1 probe-v2; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the ships alone: the fix belongs in the flight plan"
done
deploy_count=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$deploy_count" -eq 3 ]] || fail "$NS holds $deploy_count deployments, expected exactly 3 - do not add or remove ships"

# --- 1. the shields are unchanged --------------------------------------------
kubectl -n "$NS" get destinationrule "$SVC" >/dev/null 2>&1 \
  || fail "DestinationRule '$SVC' not found in $NS. Keep the shields: this mission is about the retry policy, not the connection pool"
mc=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.trafficPolicy.connectionPool.tcp.maxConnections}')
pr=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.trafficPolicy.connectionPool.http.http1MaxPendingRequests}')
mr=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.trafficPolicy.connectionPool.http.maxRequestsPerConnection}')
[[ "$mc" == "1" && "$pr" == "1" && "$mr" == "1" ]] \
  || fail "the probe DestinationRule now has maxConnections=$mc, http1MaxPendingRequests=$pr, maxRequestsPerConnection=$mr. Keep all three at 1: the shields are not the problem"

# --- 2. the flight plan ------------------------------------------------------
vs_count=$(kubectl get virtualservice -A -o json 2>/dev/null | python3 -c '
import json,sys
n=0
for v in json.load(sys.stdin)["items"]:
    hosts=v.get("spec",{}).get("hosts",[])
    ns=v["metadata"]["namespace"]
    for h in hosts:
        if h in ("probe.starfleet.svc.cluster.local","probe.starfleet","probe.starfleet.svc") or (h=="probe" and ns=="starfleet"):
            n+=1; break
print(n)')
[[ "$vs_count" -eq 1 ]] || fail "found $vs_count VirtualService objects for the probe, expected exactly one (named '$SVC' in $NS). Change the existing flight plan instead of adding a second one"
kubectl -n "$NS" get virtualservice "$SVC" >/dev/null 2>&1 \
  || fail "VirtualService '$SVC' not found in $NS. Keep the flight plan and change its retry policy"

attempts=$(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{.spec.http[0].retries.attempts}')
retry_on=$(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{.spec.http[0].retries.retryOn}')
dest=$(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{.spec.http[0].route[0].destination.host}')
case "$dest" in probe|probe.starfleet|probe.starfleet.svc|probe.starfleet.svc.cluster.local) ;;
  *) fail "the flight plan sends signals to '$dest', expected the probe" ;; esac
[[ -n "$attempts" ]] || fail "the flight plan has no retry policy any more. Keep retries: signals that never reach the probe (connect-failure) should still get a second try"
[[ "$attempts" -ge 1 && "$attempts" -le 2 ]] \
  || fail "retries.attempts is $attempts. A struggling probe should get at most 2 extra tries per signal: set attempts to 1 or 2"
grep -q 'connect-failure' <<<"$retry_on" \
  || fail "retryOn is '$retry_on'. Keep retrying signals that never reached the probe: include connect-failure"
for bad in 5xx gateway-error retriable-status-codes 503; do
  if grep -qw -- "$bad" <<<"$retry_on"; then
    fail "retryOn still contains '$bad', so every 503 the probe answers is sent to it again. Retry only what never reached the probe, for example connect-failure,refused-stream"
  fi
done

# --- 3. live: 5 failing signals reach the probe exactly 5 times --------------
received() {
  t=0
  for p in $(kubectl get pod -n "$NS" -l app=probe -o name); do
    n=$(kubectl logs -n "$NS" "$p" -c istio-proxy 2>/dev/null | grep -c '"GET /status/503 HTTP/1.1".*inbound|')
    t=$((t+n))
  done
  echo "$t"
}

got=""
for try in 1 2 3 4 5 6; do
  before=$(received)
  codes=$(kubectl exec -n "$NS" deploy/shuttle -- sh -c \
    'for i in 1 2 3 4 5; do curl -s -o /dev/null -w "%{http_code} " http://probe:8000/status/503; done' 2>/dev/null)
  sleep 3
  after=$(received)
  got=$((after - before))
  if [[ "$got" -eq 5 ]]; then break; fi
  sleep 5
done
grep -q '503 503 503 503 503' <<<"$codes" || fail "the 5 test signals to /status/503 answered '$codes', expected five 503s. The probe should still answer them; only the retries should change"
[[ "$got" -eq 5 ]] \
  || fail "5 failing signals reached the probe $got times, expected exactly 5. The flight plan still sends the probe's own 503 answers again: remove 5xx-style values from retryOn"

echo "PASS: the shields are unchanged, the flight plan retries only connection failures (attempts=$attempts, retryOn=$retry_on), and 5 failing signals reached the probe exactly 5 times"
