#!/usr/bin/env bash
# Grades the capstone: the structure of the objects, then real requests from the
# shuttle in starfleet, dock and depot.

set -u

NS="starfleet"
FQDN="probe.starfleet.svc.cluster.local"

fail() { echo "FAIL: $*"; exit 1; }

# Print "<status> <seconds>" for one request from the shuttle in namespace $1 to URL $2.
# Extra arguments go to curl.
send_request() {
  local namespace="$1" url="$2"
  shift 2
  kubectl -n "$namespace" exec deploy/shuttle -- curl -s -o /dev/null --max-time 12 \
    -w '%{http_code} %{time_total}' "$@" "$url" 2>/dev/null
}

# Count which probe version answered 10 requests. Extra arguments go to curl.
count_versions() {
  local namespace="$1" url="$2"
  shift 2
  for _ in $(seq 1 10); do
    kubectl -n "$namespace" exec deploy/shuttle -- curl -s --max-time 10 "$@" "$url" 2>/dev/null \
      | grep -o 'probe-v[0-9]' | head -1
  done | sort | uniq -c | tr -s ' ' | tr '\n' ';'
}

# Print the exportTo list of an object, sorted, with "starfleet" written as ".".
export_list() {
  kubectl -n "$NS" get "$1" probe -o jsonpath='{.spec.exportTo[*]}' 2>/dev/null \
    | tr ' ' '\n' | sed 's/^starfleet$/./' | sort | tr '\n' ' ' | sed 's/ $//'
}

# --- 0. the environment is still what the lab handed over -------------------
for d in probe-v1 probe-v2; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS"
done
for n in starfleet dock depot; do
  ready=$(kubectl -n "$n" get deployment shuttle -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "the shuttle in $n is missing or not ready"
done
for n in dock depot; do
  other=$(kubectl -n "$n" get virtualservice,destinationrule -o name 2>/dev/null)
  [[ -z "$other" ]] || fail "namespace $n holds Istio objects [$other] - all objects go in $NS"
done

# --- 1. the DestinationRule --------------------------------------------------
kubectl -n "$NS" get destinationrule probe >/dev/null 2>&1 || fail "DestinationRule 'probe' not found in $NS"
for s in v1 v2; do
  label=$(kubectl -n "$NS" get destinationrule probe \
    -o jsonpath="{.spec.subsets[?(@.name=='$s')].labels.version}" 2>/dev/null)
  [[ "$label" == "$s" ]] || fail "DestinationRule subset '$s' selects version='$label', expected version='$s'"
done
dr_export=$(export_list destinationrule)
[[ "$dr_export" == ". dock" ]] || fail "the DestinationRule exportTo is [$dr_export], expected exactly the own namespace and dock"

# --- 2. the root VirtualService ----------------------------------------------
kubectl -n "$NS" get virtualservice probe >/dev/null 2>&1 || fail "VirtualService 'probe' not found in $NS"
vs_export=$(export_list virtualservice)
[[ "$vs_export" == ". dock" ]] || fail "the root VirtualService exportTo is [$vs_export], expected exactly the own namespace and dock"
root_hosts=$(kubectl -n "$NS" get virtualservice probe -o jsonpath='{.spec.hosts[*]}' 2>/dev/null)
case "$root_hosts" in
  probe|probe.starfleet|probe.starfleet.svc|probe.starfleet.svc.cluster.local) ;;
  *) fail "the root VirtualService has hosts [$root_hosts], expected the single host probe" ;;
esac
rules=$(kubectl -n "$NS" get virtualservice probe \
  -o jsonpath='{range .spec.http[*]}{.delegate.name}|{.delegate.namespace}|{.match[0].uri.prefix}|{.route[0].destination.subset};{end}' 2>/dev/null)
expected='probe-hostname|starfleet|/hostname|;probe-delay|starfleet|/delay|;|||v1;'
[[ "$rules" == "$expected" ]] || fail "the root rules are [$rules], expected exactly three: /hostname delegates to probe-hostname, /delay delegates to probe-delay, and a last rule with no match routes to v1"

# --- 3. the delegates --------------------------------------------------------
for d in probe-hostname probe-delay; do
  kubectl -n "$NS" get virtualservice "$d" >/dev/null 2>&1 || fail "VirtualService '$d' not found in $NS"
  hosts=$(kubectl -n "$NS" get virtualservice "$d" -o jsonpath='{.spec.hosts[*]}' 2>/dev/null)
  [[ -z "$hosts" ]] || fail "delegate '$d' has hosts [$hosts] - a delegate has no hosts"
  gateways=$(kubectl -n "$NS" get virtualservice "$d" -o jsonpath='{.spec.gateways[*]}' 2>/dev/null)
  [[ -z "$gateways" ]] || fail "delegate '$d' has gateways [$gateways] - a delegate has no gateways"
done
hostname_rules=$(kubectl -n "$NS" get virtualservice probe-hostname \
  -o jsonpath="{range .spec.http[*]}{.match[0].headers['x-canary'].exact}|{.route[0].destination.subset};{end}" 2>/dev/null)
[[ "$hostname_rules" == 'true|v2;|v1;' ]] || fail "probe-hostname rules are [$hostname_rules], expected: header x-canary=true to v2, then everything else to v1"
delay_rules=$(kubectl -n "$NS" get virtualservice probe-delay \
  -o jsonpath="{range .spec.http[*]}{.match[0].headers['x-canary'].exact}|{.timeout}|{.route[0].destination.subset};{end}" 2>/dev/null)
[[ "$delay_rules" == 'true|6s|v2;|2s|v1;' ]] || fail "probe-delay rules are [$delay_rules], expected: header x-canary=true with 6s to v2, then everything else with 2s to v1"

# --- 4. live traffic from starfleet and dock ---------------------------------
# Retry for a while: istiod needs a moment to push the changes.
ok=0
for attempt in $(seq 1 12); do
  result=$(count_versions dock "http://$FQDN:8000/hostname" -H 'x-canary: true')
  [[ "$result" == " 10 probe-v2;" ]] && { ok=1; break; }
  sleep 5
done
[[ "$ok" -eq 1 ]] || fail "10 requests from dock with the header were answered as [$result] - expected 10 from probe-v2"

for client in starfleet dock; do
  if [[ "$client" == "starfleet" ]]; then base="http://probe:8000"; else base="http://$FQDN:8000"; fi

  result=$(count_versions "$client" "$base/hostname" -H 'x-canary: true')
  [[ "$result" == " 10 probe-v2;" ]] || fail "$client: 10 requests to /hostname with the header were answered as [$result], expected 10 from probe-v2"
  result=$(count_versions "$client" "$base/hostname")
  [[ "$result" == " 10 probe-v1;" ]] || fail "$client: 10 requests to /hostname without the header were answered as [$result], expected 10 from probe-v1"

  result=$(send_request "$client" "$base/delay/4" -H 'x-canary: true')
  [[ "${result%% *}" == "200" ]] || fail "$client: /delay/4 with the header returned '${result%% *}', expected 200 (timeout 6s)"
  result=$(send_request "$client" "$base/delay/4")
  [[ "${result%% *}" == "504" ]] || fail "$client: /delay/4 without the header returned '${result%% *}', expected 504 (timeout 2s)"
  awk -v t="${result##* }" 'BEGIN { exit !(t < 3.5) }' \
    || fail "$client: /delay/4 without the header took ${result##* } seconds - the 2 second timeout is not applied"
  result=$(send_request "$client" "$base/delay/1")
  [[ "${result%% *}" == "200" ]] || fail "$client: /delay/1 without the header returned '${result%% *}', expected 200"
done

# --- 5. depot must be unaffected ---------------------------------------------
result=$(send_request depot "http://$FQDN:8000/delay/4")
[[ "${result%% *}" == "200" ]] || fail "depot: /delay/4 returned '${result%% *}', expected 200 - depot must not receive the 2 second timeout"

v1_seen=0
for _ in $(seq 1 30); do
  body=$(kubectl -n depot exec deploy/shuttle -- curl -s --max-time 10 -H 'x-canary: true' "http://$FQDN:8000/hostname" 2>/dev/null)
  grep -q 'probe-v1' <<<"$body" && v1_seen=$((v1_seen + 1))
done
[[ "$v1_seen" -ge 1 ]] || fail "depot: 30 requests with the header never reached probe-v1 - depot must not receive the canary rules"

echo "PASS: the delegated canary works from starfleet and dock, and depot is unchanged"
exit 0
