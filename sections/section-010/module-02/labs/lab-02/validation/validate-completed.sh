#!/usr/bin/env bash
# Confirms the shuttle's own Sidecar (shuttle-only) was repaired rather than
# removed: it still selects only the shuttle, keeps REGISTRY_ONLY, and lists
# its own planet, istio-system and outpost again. The planet default must be
# unchanged. Then - the part that matters - the shuttle's proxy really holds
# the outpost and istio-system destinations, and a live signal to the probe
# travels through the probe's own cluster, not through a passthrough.

set -u

NS="starfleet"
REMOTE="outpost"
PROBE_FQDN="probe.outpost.svc.cluster.local"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is still what the lab handed over -------------------
for d in shuttle cargo-v1; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the ships alone: the fix belongs in a Sidecar"
done
for d in probe-v1 probe-v2; do
  ready=$(kubectl -n "$REMOTE" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $REMOTE. Leave the probe alone"
done
lbl=$(kubectl -n "$NS" get deployment shuttle -o jsonpath='{.spec.template.metadata.labels.app}' 2>/dev/null)
[[ "$lbl" == "shuttle" ]] || fail "the shuttle's pods are now labelled app='$lbl', expected 'shuttle'. Do not relabel the ship to escape its Sidecar - fix the Sidecar"

# --- 1. the planet default is unchanged --------------------------------------
kubectl -n "$NS" get sidecar default >/dev/null 2>&1 \
  || fail "the planet default Sidecar 'default' is missing from $NS - it was correct, leave it in place"
sel=$(kubectl -n "$NS" get sidecar default -o jsonpath='{.spec.workloadSelector}' 2>/dev/null)
[[ -z "$sel" ]] || fail "the planet default now has a workloadSelector ($sel). It must stay planet-wide"
hosts=$(kubectl -n "$NS" get sidecar default -o jsonpath='{.spec.egress[*].hosts[*]}' 2>/dev/null | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')
[[ "$hosts" == "./* istio-system/* outpost/*" ]] || fail "the planet default lists [$hosts], expected exactly ./*, istio-system/* and outpost/*. It was correct - change only shuttle-only"
mode=$(kubectl -n "$NS" get sidecar default -o jsonpath='{.spec.outboundTrafficPolicy.mode}' 2>/dev/null)
[[ "$mode" == "REGISTRY_ONLY" ]] || fail "the planet default's outboundTrafficPolicy is '$mode', expected REGISTRY_ONLY. Leave it unchanged"

# --- 2. shuttle-only still exists, still selects the shuttle -----------------
kubectl -n "$NS" get sidecar shuttle-only >/dev/null 2>&1 \
  || fail "the Sidecar 'shuttle-only' is gone. The task is to repair it, not to delete it: the shuttle must keep its own Sidecar"
app=$(kubectl -n "$NS" get sidecar shuttle-only -o jsonpath='{.spec.workloadSelector.labels.app}' 2>/dev/null)
[[ "$app" == "shuttle" ]] || fail "shuttle-only selects app='$app', expected app: shuttle. It must stay a selector Sidecar for the shuttle only"
mode=$(kubectl -n "$NS" get sidecar shuttle-only -o jsonpath='{.spec.outboundTrafficPolicy.mode}' 2>/dev/null)
[[ "$mode" == "REGISTRY_ONLY" ]] || fail "shuttle-only's outboundTrafficPolicy is '$mode', expected REGISTRY_ONLY. A selector Sidecar inherits nothing from the planet default, so it must state the policy itself"

count=$(kubectl -n "$NS" get sidecar -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$count" -eq 2 ]] || fail "$NS holds $count Sidecar objects, expected exactly 2 (default and shuttle-only). Extra Sidecars that select the same ship are undefined"

sc_hosts=" $(kubectl -n "$NS" get sidecar shuttle-only -o jsonpath='{.spec.egress[*].hosts[*]}' 2>/dev/null) "
grep -q ' \./\* ' <<<"$sc_hosts" \
  || fail "shuttle-only no longer lists ./* - the shuttle would lose its own planet, including the cargo ship"
grep -q ' istio-system/\* ' <<<"$sc_hosts" \
  || fail "shuttle-only does not list istio-system/*. A selector Sidecar replaces the planet default and inherits nothing, so it must list istio-system/* itself"
grep -qE " (outpost/\*|outpost/$PROBE_FQDN|\*/$PROBE_FQDN) " <<<"$sc_hosts" \
  || fail "shuttle-only does not list the outpost planet (for example outpost/*). The planet default lists it, but the shuttle's own Sidecar replaces that list completely"

# --- 3. the shuttle's proxy holds the destinations ---------------------------
ok=""
for i in $(seq 1 30); do
  cl=$(istioctl proxy-config cluster deploy/shuttle -n "$NS" 2>/dev/null)
  if grep -q "$PROBE_FQDN" <<<"$cl" && grep -q "istiod.istio-system.svc.cluster.local" <<<"$cl"; then ok=1; break; fi
  sleep 2
done
[[ -n "$ok" ]] || fail "the shuttle's proxy still has no destination for $PROBE_FQDN and istiod.istio-system (istioctl proxy-config cluster deploy/shuttle -n $NS). Check the hosts in shuttle-only"

# --- 4. live signals ------------------------------------------------------------
code=""
for i in $(seq 1 20); do
  code=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://probe.$REMOTE:8000/get" 2>/dev/null)
  [[ "$code" == "200" ]] && break
  sleep 2
done
[[ "$code" == "200" ]] || fail "the shuttle's signal to http://probe.$REMOTE:8000/get got '$code', expected 200. If it is 000, the probe is still off the shuttle's star chart and falls into the black hole"

sleep 2
line=$(kubectl -n "$NS" logs deploy/shuttle -c istio-proxy --tail=20 2>/dev/null | grep "probe.$REMOTE:8000" | tail -1)
grep -q "outbound|8000||$PROBE_FQDN" <<<"$line" \
  || fail "the shuttle's flight log does not show the signal leaving through outbound|8000||$PROBE_FQDN. Found: ${line:-no log line}"

cargo=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://cargo:9080/details/0" 2>/dev/null)
[[ "$cargo" == "200" ]] || fail "the shuttle's signal to the cargo ship got '$cargo', expected 200. The shuttle must keep its own planet (./*)"

echo "PASS: shuttle-only still selects only the shuttle with REGISTRY_ONLY, now lists its own planet, istio-system and outpost, the planet default is unchanged, and the shuttle reaches the probe through its own cluster and the cargo ship on its own planet"
exit 0
