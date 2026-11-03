#!/usr/bin/env bash
# Confirms that the probe DestinationRule sets the connection pool values, that
# the shuttle's proxy really holds them (cluster JSON), that nothing else was
# changed, and - the part that matters - that live requests still work.

set -u

NS="starfleet"
FQDN="probe.starfleet.svc.cluster.local"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is still what the lab handed over -------------------
for d in shuttle probe-zone-a probe-zone-b; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Keep every deployment running"
done
deploy_count=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$deploy_count" -eq 3 ]] || fail "$NS holds $deploy_count deployments, expected exactly 3 - do not add or remove deployments"
selector=$(kubectl -n "$NS" get service probe -o jsonpath='{.spec.selector}' 2>/dev/null)
[[ "$selector" == '{"app":"probe"}' ]] || fail "the probe Service selector is '$selector', expected {\"app\":\"probe\"} - leave the Service alone"

# --- 1. one DestinationRule, no VirtualService --------------------------------
kubectl -n "$NS" get destinationrule probe >/dev/null 2>&1 \
  || fail "DestinationRule 'probe' not found in $NS"
dr_count=$(kubectl -n "$NS" get destinationrule -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$dr_count" -eq 1 ]] || fail "$NS holds $dr_count DestinationRules, expected exactly 1 (named probe)"
vs_count=$(kubectl -n "$NS" get virtualservice -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$vs_count" -eq 0 ]] || fail "$NS holds a VirtualService. This task needs none"
host=$(kubectl -n "$NS" get destinationrule probe -o jsonpath='{.spec.host}' 2>/dev/null)
case "$host" in
  probe|"$FQDN") ;;
  *) fail "the DestinationRule host is '$host', expected probe" ;;
esac
od=$(kubectl -n "$NS" get destinationrule probe -o jsonpath='{.spec.trafficPolicy.outlierDetection}' 2>/dev/null)
[[ -z "$od" ]] || fail "the DestinationRule sets outlierDetection. This task is only about the connection pool - remove it"
subsets=$(kubectl -n "$NS" get destinationrule probe -o jsonpath='{.spec.subsets}' 2>/dev/null)
[[ -z "$subsets" ]] || fail "the DestinationRule defines subsets. This task needs none"

# --- 2. the shuttle's proxy holds every value --------------------------------
# The proxy prints durations as strings ("2s") and keepalive times as whole
# seconds. Whitespace is removed so that the grep does not depend on layout.
cluster_json() {
  istioctl proxy-config cluster deploy/shuttle -n "$NS" --fqdn "$FQDN" --port 8000 -o json 2>/dev/null | tr -d ' \n\t'
}
checks=('"connectTimeout":"2s"' '"idleTimeout":"90s"' '"maxConnectionDuration":"600s"' '"keepaliveProbes":4' '"keepaliveTime":60' '"keepaliveInterval":10')
missing=""
for attempt in $(seq 1 30); do
  json=$(cluster_json)
  missing=""
  for c in "${checks[@]}"; do
    grep -qF "$c" <<<"$json" || missing="$missing $c"
  done
  [[ -z "$missing" ]] && break
  sleep 2
done
[[ -z "$missing" ]] || fail "the shuttle's proxy does not hold these values for $FQDN:$missing. Check the field names, which block they are in (tcp or http) and their values"

# --- 3. live requests --------------------------------------------------------
sleep 2
bad=0
for i in $(seq 1 10); do
  code=""
  for t in 1 2 3; do
    code=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://probe:8000/hostname 2>/dev/null) && break
    sleep 1
  done
  [[ "$code" == "200" ]] || bad=$((bad + 1))
done
[[ "$bad" -eq 0 ]] || fail "$bad of 10 requests from the shuttle to the probe did not return 200"

echo "PASS: the proxy holds connectTimeout 2s, idleTimeout 90s, maxConnectionDuration 600s and the TCP keepalive values, and all 10 requests returned 200"
exit 0
