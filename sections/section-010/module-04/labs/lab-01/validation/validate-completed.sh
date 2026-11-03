#!/usr/bin/env bash
# Grades the delegated route table: the structure of the three VirtualServices,
# then real requests from the shuttle, then the proxy's route table.

set -u

NS="starfleet"
CLIENT="deploy/shuttle"

fail() { echo "FAIL: $*"; exit 1; }

# Send one request from the shuttle and print "<status> <seconds>".
send_request() {
  kubectl -n "$NS" exec "$CLIENT" -- curl -s -o /dev/null --max-time 12 \
    -w '%{http_code} %{time_total}' "$1" 2>/dev/null
}

# Send one request and print the body.
read_body() {
  kubectl -n "$NS" exec "$CLIENT" -- curl -s --max-time 10 "$1" 2>/dev/null
}

# --- 0. the environment is still what the lab handed over -------------------
for d in probe-v1 probe-v2 shuttle; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS"
done
subsets=$(kubectl -n "$NS" get destinationrule probe -o jsonpath='{.spec.subsets[*].name}' 2>/dev/null)
for s in v1 v2; do
  grep -qw "$s" <<<"$subsets" || fail "the DestinationRule 'probe' no longer has the subset '$s' - leave it unchanged"
done

# --- 1. the delegates --------------------------------------------------------
for d in probe-hostname probe-delay; do
  kubectl -n "$NS" get virtualservice "$d" >/dev/null 2>&1 \
    || fail "VirtualService '$d' not found in $NS"
  hosts=$(kubectl -n "$NS" get virtualservice "$d" -o jsonpath='{.spec.hosts[*]}' 2>/dev/null)
  [[ -z "$hosts" ]] || fail "delegate '$d' has hosts [$hosts] - a delegate has no hosts"
  gateways=$(kubectl -n "$NS" get virtualservice "$d" -o jsonpath='{.spec.gateways[*]}' 2>/dev/null)
  [[ -z "$gateways" ]] || fail "delegate '$d' has gateways [$gateways] - a delegate has no gateways"
done

delay_timeout=$(kubectl -n "$NS" get virtualservice probe-delay -o jsonpath='{.spec.http[0].timeout}' 2>/dev/null)
[[ "$delay_timeout" == "2s" ]] || fail "probe-delay sets timeout '$delay_timeout' on its first rule, expected 2s"
delay_prefix=$(kubectl -n "$NS" get virtualservice probe-delay -o jsonpath='{.spec.http[0].match[0].uri.prefix}' 2>/dev/null)
[[ "$delay_prefix" == "/delay/" ]] || fail "probe-delay matches uri prefix '$delay_prefix', expected /delay/"
delay_subset=$(kubectl -n "$NS" get virtualservice probe-delay -o jsonpath='{.spec.http[0].route[0].destination.subset}' 2>/dev/null)
[[ "$delay_subset" == "v1" ]] || fail "probe-delay routes to subset '$delay_subset', expected v1"
host_subset=$(kubectl -n "$NS" get virtualservice probe-hostname -o jsonpath='{.spec.http[0].route[0].destination.subset}' 2>/dev/null)
[[ "$host_subset" == "v2" ]] || fail "probe-hostname routes to subset '$host_subset', expected v2"

# --- 2. the root -------------------------------------------------------------
kubectl -n "$NS" get virtualservice probe >/dev/null 2>&1 \
  || fail "VirtualService 'probe' not found in $NS"
root_hosts=$(kubectl -n "$NS" get virtualservice probe -o jsonpath='{.spec.hosts[*]}' 2>/dev/null)
case "$root_hosts" in
  probe|probe.starfleet|probe.starfleet.svc|probe.starfleet.svc.cluster.local) ;;
  *) fail "the root VirtualService has hosts [$root_hosts], expected the single host probe" ;;
esac

rules=$(kubectl -n "$NS" get virtualservice probe \
  -o jsonpath='{range .spec.http[*]}{.delegate.name}|{.delegate.namespace}|{.match[0].uri.prefix}|{.route[0].destination.subset};{end}' 2>/dev/null)
expected='probe-hostname|starfleet|/hostname|;probe-delay|starfleet|/delay|;|||v1;'
[[ "$rules" == "$expected" ]] || fail "the root rules are [$rules], expected exactly three: /hostname delegates to probe-hostname, /delay delegates to probe-delay, and a last rule with no match routes to v1"

# --- 3. live traffic ---------------------------------------------------------
# Retry for a while: istiod needs a moment to push the new routes.
ok=0
for attempt in $(seq 1 12); do
  v2=0
  for _ in $(seq 1 10); do
    body=$(read_body "http://probe:8000/hostname")
    grep -q 'probe-v2' <<<"$body" && v2=$((v2 + 1))
  done
  if [[ "$v2" -eq 10 ]]; then ok=1; break; fi
  sleep 5
done
[[ "$ok" -eq 1 ]] || fail "/hostname was answered by probe-v2 only $v2 times out of 10 - it must be 10 of 10"

get_v1=0
for _ in $(seq 1 10); do
  result=$(send_request "http://probe:8000/get")
  [[ "${result%% *}" == "200" ]] && get_v1=$((get_v1 + 1))
done
[[ "$get_v1" -eq 10 ]] || fail "/get returned 200 only $get_v1 times out of 10 - the last rule must send everything else to v1"

code=$(send_request "http://probe:8000/delay/1")
[[ "${code%% *}" == "200" ]] || fail "/delay/1 returned '${code%% *}', expected 200"

result=$(send_request "http://probe:8000/delay/5")
status="${result%% *}"
seconds="${result##* }"
[[ "$status" == "504" ]] || fail "/delay/5 returned '$status', expected 504 from the 2 second timeout"
awk -v t="$seconds" 'BEGIN { exit !(t < 4.5) }' \
  || fail "/delay/5 took $seconds seconds - the 2 second timeout is not applied"

# --- 4. the proxy's route table ---------------------------------------------
routes=$(istioctl proxy-config routes "$CLIENT" -n "$NS" --name 8000 2>/dev/null)
grep -q '/hostname' <<<"$routes" || fail "the shuttle's route table for port 8000 has no /hostname route"
grep -q '/delay' <<<"$routes" || fail "the shuttle's route table for port 8000 has no /delay route"

echo "PASS: the probe route table is split across a root and two delegates, and real requests follow it"
exit 0
