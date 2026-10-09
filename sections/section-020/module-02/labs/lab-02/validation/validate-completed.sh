#!/usr/bin/env bash
# Confirms the probe DestinationRule defines v1 and v2 over the pods' version
# label, that the VirtualService still routes every request to v1 and mirrors
# to v2, that the mirror cluster has endpoints in the shuttle's sidecar proxy,
# and - the part that 200 responses to the client can never prove - that
# probe-v2 really receives the copies.

set -u

NS="starfleet"
SVC="probe"
FQDN="probe.starfleet.svc.cluster.local"
MIRROR_CLUSTER="outbound|8000|v2|${FQDN}"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is still what the lab handed over -------------------
for d in probe-v1 probe-v2 shuttle; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the deployments alone: the fix belongs in the DestinationRule"
done

deploy_count=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$deploy_count" -eq 3 ]] || fail "$NS holds $deploy_count deployments, expected exactly 3 - do not add or remove deployments"

for v in v1 v2; do
  lbl=$(kubectl -n "$NS" get deployment "probe-$v" -o jsonpath='{.spec.template.metadata.labels.version}' 2>/dev/null)
  [[ "$lbl" == "$v" ]] || fail "deployment probe-$v now labels its pods version='$lbl', expected '$v'. Do not relabel the pods - fix the DestinationRule instead"
done

selector=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.selector}' 2>/dev/null)
[[ -n "$selector" ]] || fail "Service $SVC not found in $NS"
if grep -q 'version' <<<"$selector"; then
  fail "the $SVC Service selector is $selector - it must keep selecting on app only"
fi

# --- 1. the DestinationRule ---------------------------------------------------
kubectl -n "$NS" get destinationrule "$SVC" >/dev/null 2>&1 \
  || fail "DestinationRule '$SVC' not found in $NS - the mirror needs it to resolve the subset name v2"

dr_host=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.host}' 2>/dev/null)
case "$dr_host" in
  "$SVC"|"$SVC.$NS"|"$SVC.$NS.svc"|"$FQDN") ;;
  *) fail "DestinationRule host is '$dr_host', expected $SVC (short or full name)" ;;
esac

subset_names=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.subsets[*].name}' 2>/dev/null)
for s in v1 v2; do
  grep -qw "$s" <<<"$subset_names" || fail "DestinationRule subsets are [$subset_names] - subset '$s' is missing"
done

for s in v1 v2; do
  lbl=$(kubectl -n "$NS" get destinationrule "$SVC" \
    -o jsonpath="{.spec.subsets[?(@.name=='$s')].labels.version}" 2>/dev/null)
  [[ "$lbl" == "$s" ]] || fail "subset '$s' selects version='$lbl', but the probe-$s pods carry version=$s. A subset whose labels match no pod is accepted, and a mirror to it sends nothing at all"
done

# --- 2. the VirtualService is still the one the lab handed over -------------
vs_count=$(kubectl -n "$NS" get virtualservice -o jsonpath='{range .items[*]}{.spec.hosts[*]}{"\n"}{end}' 2>/dev/null \
  | grep -cE "^($SVC|$FQDN)( |$)")
[[ "$vs_count" -eq 1 ]] || fail "found $vs_count VirtualService objects for $SVC in $NS, expected exactly one"

vs_name=$(kubectl -n "$NS" get virtualservice -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.hosts[*]}{"\n"}{end}' 2>/dev/null \
  | awk -v a="$SVC" -v b="$FQDN" '$2==a || $2==b {print $1; exit}')

route_subsets=$(kubectl -n "$NS" get virtualservice "$vs_name" -o jsonpath='{.spec.http[0].route[*].destination.subset}' 2>/dev/null)
[[ "$route_subsets" == "v1" ]] || fail "the VirtualService routes to [$route_subsets], expected only subset v1. Every response to the client must come from v1 - the fix is in the DestinationRule, not the VirtualService"

mirror_subset=$(kubectl -n "$NS" get virtualservice "$vs_name" -o jsonpath='{.spec.http[0].mirror.subset}' 2>/dev/null)
[[ "$mirror_subset" == "v2" ]] || fail "the VirtualService mirrors to subset '$mirror_subset', expected v2. Keep the mirror pointed at v2"

pct=$(kubectl -n "$NS" get virtualservice "$vs_name" -o jsonpath='{.spec.http[0].mirrorPercentage.value}' 2>/dev/null)
if [[ -n "$pct" ]]; then
  awk -v p="$pct" 'BEGIN{exit !(p>=99.9)}' || fail "mirrorPercentage is $pct, expected 100: every request must be copied"
fi

# --- 3. the shuttle's proxy holds the mirror, and the mirror cluster has endpoints
policy=""
endpoints=0
for i in $(seq 1 20); do
  policy=$(istioctl proxy-config routes deploy/shuttle -n "$NS" -o json 2>/dev/null \
    | grep -A2 '"requestMirrorPolicies"' | grep -o '"cluster": "[^"]*"' | head -1)
  endpoints=$(istioctl proxy-config endpoints deploy/shuttle -n "$NS" --cluster "$MIRROR_CLUSTER" 2>/dev/null \
    | grep -c HEALTHY)
  [[ "$policy" == *"$MIRROR_CLUSTER"* && "$endpoints" -ge 1 ]] && break
  sleep 3
done
[[ "$policy" == *"$MIRROR_CLUSTER"* ]] || fail "the shuttle's proxy holds no mirror policy for $MIRROR_CLUSTER (found: ${policy:-none}). Check that the VirtualService reached the proxy"
[[ "$endpoints" -ge 1 ]] || fail "the mirror cluster $MIRROR_CLUSTER has no healthy endpoints in the shuttle's proxy. The subset's labels select no running probe pod - istioctl analyze reports this as IST0173"

# --- 4. every response to the client comes from v1 ---------------------------
answers=$(for i in $(seq 1 30); do
  kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 5 "http://$SVC:8000/hostname" 2>/dev/null | grep -o 'probe-v[0-9]' || echo none
done | sort | uniq -c)
v1_count=$(awk '$2=="probe-v1"{print $1}' <<<"$answers")
[[ "${v1_count:-0}" -eq 30 ]] || fail "of 30 requests, the shuttle got these responses: $(tr '\n' ' ' <<<"$answers"). Every response must come from probe-v1 - the response to a mirrored copy must never reach the client"

# --- 5. probe-v2 really receives the copies ----------------------------------
copies=0
for attempt in 1 2 3; do
  sleep 4   # let copies from earlier requests arrive before the count window opens
  start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  sleep 1
  for i in $(seq 1 20); do
    kubectl -n "$NS" exec deploy/shuttle -- curl -s -o /dev/null --max-time 5 "http://$SVC:8000/hostname" 2>/dev/null
  done
  sleep 4
  copies=$(kubectl -n "$NS" logs deploy/probe-v2 -c probe --since-time="$start" 2>/dev/null | grep -c 'GET /hostname')
  [[ "$copies" -ge 18 ]] && break
done
[[ "$copies" -ge 1 ]] || fail "probe-v2 received 0 copies of 20 requests. The client gets 200 responses, which proves nothing: probe-v2 still receives no copies"
[[ "$copies" -ge 18 ]] || fail "probe-v2 received only $copies copies of 20 requests, well short of 100%. Check mirrorPercentage"

echo "PASS: subsets v1 and v2 select their probe pods, the VirtualService still routes to v1 and mirrors 100% to v2, the mirror cluster has endpoints, all 30 responses to the client came from probe-v1, and probe-v2 received $copies copies of 20 requests"
