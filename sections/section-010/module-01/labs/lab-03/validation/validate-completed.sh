#!/usr/bin/env bash
# Confirms the scout DestinationRule defines exactly v1, v2 and v3 over the
# pods' version label, that every subset has pods behind it in the shuttle's
# proxy, that the VirtualService was left alone, and - the part
# that matters - that live requests reach the right scout version.

set -u

NS="starfleet"
SVC="scout"
FQDN="scout.starfleet.svc.cluster.local"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is still what the lab handed over -------------------
for d in bridge-v1 cargo-v1 navcom-v1 scout-v1 scout-v2 scout-v3 shuttle; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the deployments alone: the fix belongs in the DestinationRule"
done

deploy_count=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$deploy_count" -eq 7 ]] || fail "$NS holds $deploy_count deployments, expected exactly 7 - do not add or remove deployments"

for v in v1 v2 v3; do
  lbl=$(kubectl -n "$NS" get deployment "scout-$v" -o jsonpath='{.spec.template.metadata.labels.version}' 2>/dev/null)
  [[ "$lbl" == "$v" ]] || fail "deployment scout-$v now labels its pods version='$lbl', expected '$v'. Do not relabel the pods - fix the DestinationRule instead"
done

selector=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.selector}' 2>/dev/null)
[[ -n "$selector" ]] || fail "Service $SVC not found in $NS"
if grep -q 'version' <<<"$selector"; then
  fail "the $SVC Service selector is $selector - it must keep selecting on app only"
fi

# --- 1. the DestinationRule ---------------------------------------------------
kubectl -n "$NS" get destinationrule "$SVC" >/dev/null 2>&1 \
  || fail "DestinationRule '$SVC' not found in $NS - the VirtualService needs it to resolve subset names"

dr_host=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.host}' 2>/dev/null)
case "$dr_host" in
  "$SVC"|"$SVC.$NS"|"$SVC.$NS.svc"|"$FQDN") ;;
  *) fail "DestinationRule host is '$dr_host', expected $SVC (short or full name)" ;;
esac

names=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.subsets[*].name}' 2>/dev/null | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')
[[ "$names" == "v1 v2 v3" ]] || fail "DestinationRule subsets are [$names], expected exactly v1, v2 and v3"

for s in v1 v2 v3; do
  lbl=$(kubectl -n "$NS" get destinationrule "$SVC" \
    -o jsonpath="{.spec.subsets[?(@.name=='$s')].labels.version}" 2>/dev/null)
  [[ "$lbl" == "$s" ]] || fail "subset '$s' selects version='$lbl', but the scout-$s pods carry version=$s. A subset whose labels match no pod is accepted and fails later with 503 UH"
done

# --- 2. the VirtualService was left unchanged --------------------------------
kubectl -n "$NS" get virtualservice "$SVC" >/dev/null 2>&1 \
  || fail "VirtualService '$SVC' not found in $NS - it was correct, leave it in place"
vs_hosts=$(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{.spec.hosts[*]}' 2>/dev/null)
[[ "$vs_hosts" == "$SVC" ]] || fail "VirtualService hosts changed to [$vs_hosts] - leave the VirtualService unchanged"
rules=$(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{range .spec.http[*]}{.match[0].headers.end-user.exact}|{.route[0].destination.subset};{end}' 2>/dev/null)
[[ "$rules" == "jason|v2;|v1;" ]] || fail "the VirtualService rules changed (found '$rules'). It must still send end-user=jason to v2 and everything else to v1 - the fault is in the DestinationRule"

# --- 3. every subset has endpoints in the shuttle's proxy --------------------
for s in v1 v2 v3; do
  ok=""
  for i in $(seq 1 30); do
    if istioctl proxy-config endpoints deploy/shuttle -n "$NS" \
         --cluster "outbound|9080|$s|$FQDN" 2>/dev/null | grep -q HEALTHY; then
      ok=1; break
    fi
    sleep 2
  done
  [[ -n "$ok" ]] || fail "the shuttle's proxy has no healthy endpoint in the '$s' cluster (outbound|9080|$s|$FQDN). Check the subset's labels against the pods' labels"
done

# --- 4. live requests -----------------------------------------------------------
versions() {  # $@ = extra curl args; prints the scout versions of 10 requests
  local i
  for i in $(seq 1 10); do
    kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 10 "$@" "http://$SVC:9080/reviews/0" 2>/dev/null \
      | grep -o 'scout-v[0-9]' || echo "no-answer"
  done | sort | uniq -c | awk '{print $2"="$1}' | tr '\n' ' ' | sed 's/ $//'
}

settle() {  # wait until jason's requests stop failing
  local i
  for i in $(seq 1 30); do
    kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 5 -H "end-user: jason" \
      "http://$SVC:9080/reviews/0" 2>/dev/null | grep -q 'scout-v2' && return 0
    sleep 2
  done
}
settle

jason=$(versions -H "end-user: jason")
[[ "$jason" == "scout-v2=10" ]] || fail "10 requests as jason gave [$jason], expected all 10 from scout-v2. If they failed, the v2 subset still selects no pod (503 UH in the shuttle's access log)"

others=$(versions)
[[ "$others" == "scout-v1=10" ]] || fail "10 requests without the end-user header gave [$others], expected all 10 from scout-v1"

echo "PASS: subsets v1, v2 and v3 each select their own scout pods, every subset has a healthy endpoint in the shuttle's proxy, the VirtualService is unchanged, jason reaches scout-v2 and everyone else scout-v1"
exit 0
