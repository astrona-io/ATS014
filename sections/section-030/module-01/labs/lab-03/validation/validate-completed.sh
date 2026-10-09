#!/usr/bin/env bash
# Confirms the probe DestinationRule sends requests to each pod in turn (simple
# ROUND_ROBIN at host level, no consistentHash anywhere), that the shuttle's
# sidecar proxy really holds a round robin cluster for the probe, that the
# deployments were left alone, and - the part that matters - that live requests
# from the shuttle reach all four probe pods.

set -u

NS="starfleet"
SVC="probe"
FQDN="probe.starfleet.svc.cluster.local"
CLUSTER="outbound|8000||$FQDN"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is still what the lab handed over -------------------
for d in probe-v1 probe-v2 shuttle; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the deployments alone: the fix belongs in the DestinationRule"
done

deploy_count=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$deploy_count" -eq 3 ]] || fail "$NS holds $deploy_count deployments, expected exactly 3 - do not add or remove deployments"

v1=$(kubectl -n "$NS" get deployment probe-v1 -o jsonpath='{.spec.replicas}' 2>/dev/null)
v2=$(kubectl -n "$NS" get deployment probe-v2 -o jsonpath='{.spec.replicas}' 2>/dev/null)
[[ "$v1" == "3" && "$v2" == "1" ]] || fail "probe-v1 runs $v1 replicas and probe-v2 runs $v2, expected 3 and 1. Do not scale the deployments - change how the proxy picks a pod"

selector=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.selector}' 2>/dev/null)
[[ "$selector" == *'"app":"probe"'* ]] || fail "the probe Service selector is '$selector', expected it to keep selecting app=probe"

# --- 1. the DestinationRule ---------------------------------------------------
kubectl -n "$NS" get destinationrule "$SVC" >/dev/null 2>&1 \
  || fail "DestinationRule '$SVC' not found in $NS - the load balancer policy lives in the probe's DestinationRule"

dr_host=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.host}' 2>/dev/null)
case "$dr_host" in
  "$SVC"|"$SVC.$NS"|"$SVC.$NS.svc"|"$FQDN") ;;
  *) fail "DestinationRule host is '$dr_host', expected $SVC (short or full name)" ;;
esac

dr_json=$(kubectl -n "$NS" get destinationrule "$SVC" -o json 2>/dev/null)
if grep -q '"consistentHash"' <<<"$dr_json"; then
  fail "the DestinationRule still uses consistentHash. Hashing pins requests to one pod; this task needs every pod to take requests in turn. Replace it with simple: ROUND_ROBIN"
fi

simple=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.trafficPolicy.loadBalancer.simple}' 2>/dev/null)
[[ "$simple" == "ROUND_ROBIN" ]] || fail "the host-level trafficPolicy.loadBalancer.simple is '${simple:-unset}', expected ROUND_ROBIN"

# --- 2. the shuttle's proxy holds a round robin cluster ----------------------
# Round robin is Envoy's default, so the cluster dump shows no lbPolicy line for
# it. Any other lbPolicy (RING_HASH, LEAST_REQUEST, RANDOM) means it is not.
policy=""
for attempt in $(seq 1 15); do
  cluster_json=$(istioctl proxy-config cluster deploy/shuttle -n "$NS" --fqdn "$FQDN" -o json 2>/dev/null)
  if [[ -z "$cluster_json" ]] || ! grep -q "\"$CLUSTER\"" <<<"$cluster_json"; then
    policy="missing"
  else
    other=$(grep -o '"lbPolicy": "[A-Z_]*"' <<<"$cluster_json" | head -1 | grep -o '[A-Z_]*"$' | tr -d '"')
    policy="${other:-ROUND_ROBIN}"
  fi
  [[ "$policy" == "ROUND_ROBIN" ]] && break
  sleep 2
done
[[ "$policy" == "ROUND_ROBIN" ]] || fail "the shuttle's proxy uses lbPolicy '${policy:-unknown}' for $CLUSTER, expected round robin. If you just applied the fix, wait a few seconds and submit again"

# --- 3. live requests reach every probe pod -----------------------------------
pods=$(kubectl -n "$NS" get pods -l app=probe --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
pod_count=$(wc -w <<<"$pods" | tr -d ' ')
[[ "$pod_count" -eq 4 ]] || fail "found $pod_count running probe pods, expected 4"

answers=""
for i in $(seq 1 16); do
  a=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 5 "http://$SVC:8000/hostname" 2>/dev/null | grep -o 'probe-[a-z0-9-]*' | head -1)
  answers+="${a:-none} "
done

for p in $pods; do
  n=$(grep -o "$p" <<<"$answers" | wc -l | tr -d ' ')
  [[ "$n" -ge 1 ]] || fail "16 requests from the shuttle never reached pod $p. Responses came from: $answers. An even spread must reach every probe pod"
done

top=$(tr ' ' '\n' <<<"$answers" | grep -v '^$' | sort | uniq -c | sort -rn | head -1 | awk '{print $1}')
[[ "$top" -le 8 ]] || fail "one pod answered $top of 16 requests - that is not an even spread"

echo "PASS: the probe DestinationRule uses simple ROUND_ROBIN with no consistentHash, the shuttle's proxy holds a round robin cluster, and 16 live requests reached all 4 probe pods (most on one pod: $top)"
