#!/usr/bin/env bash
# Confirms the scout ship class v1 is retired: the flight plan sends jason to
# v3 and everyone else to v2, the docking instructions hold only v2 and v3, no
# route points at a missing subset - and, the part that matters, that the
# patrol ship never saw a failed signal while the change happened.

set -u

NS="starfleet"
SVC="scout"
FQDN="scout.starfleet.svc.cluster.local"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is still what the lab handed over -------------------
for d in bridge-v1 cargo-v1 navcom-v1 scout-v1 scout-v2 scout-v3 shuttle patrol; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Retiring a ship class is done in the rules, not by removing ships"
done

deploy_count=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$deploy_count" -eq 8 ]] || fail "$NS holds $deploy_count deployments, expected exactly 8 - do not add or remove ships"

for v in v1 v2 v3; do
  lbl=$(kubectl -n "$NS" get deployment "scout-$v" -o jsonpath='{.spec.template.metadata.labels.version}' 2>/dev/null)
  [[ "$lbl" == "$v" ]] || fail "deployment scout-$v now labels its pods version='$lbl', expected '$v'. Do not relabel the ships"
done

# --- 1. the flight plan ---------------------------------------------------------
vs_count=$(kubectl get virtualservice -A -o jsonpath='{range .items[*]}{.spec.hosts[*]}{"\n"}{end}' 2>/dev/null \
  | grep -cE "^($SVC|$FQDN)$")
[[ "$vs_count" -eq 1 ]] || fail "found $vs_count VirtualService objects for $SVC, expected exactly one. Keep one flight plan per beacon"

kubectl -n "$NS" get virtualservice "$SVC" >/dev/null 2>&1 \
  || fail "VirtualService '$SVC' not found in $NS - keep the flight plan where it was"

rules=$(kubectl -n "$NS" get virtualservice "$SVC" \
  -o jsonpath='{range .spec.http[*]}{.match[0].headers.end-user.exact}|{.route[0].destination.subset};{end}' 2>/dev/null)
dests=$(kubectl -n "$NS" get virtualservice "$SVC" \
  -o jsonpath='{range .spec.http[*]}{range .route[*]}d{end};{end}' 2>/dev/null)
[[ "$rules" == "jason|v3;|v2;" && "$dests" == "d;d;" ]] || fail "the VirtualService rules are '$rules'. Expected exactly two rules with one destination each: end-user=jason to subset v3 first, then a catch-all to subset v2"

# --- 2. the docking instructions ------------------------------------------------
names=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.subsets[*].name}' 2>/dev/null | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')
[[ "$names" == "v2 v3" ]] || fail "DestinationRule subsets are [$names], expected exactly v2 and v3. Retiring v1 means removing its subset too - after no route uses it"

for s in v2 v3; do
  lbl=$(kubectl -n "$NS" get destinationrule "$SVC" \
    -o jsonpath="{.spec.subsets[?(@.name=='$s')].labels.version}" 2>/dev/null)
  [[ "$lbl" == "$s" ]] || fail "subset '$s' selects version='$lbl', expected version='$s'"
done

# --- 3. no route points at a missing subset ------------------------------------
if istioctl analyze -n "$NS" 2>&1 | grep -q 'IST0101'; then
  fail "istioctl analyze reports IST0101: a route still points at a subset or host that does not exist"
fi

# --- 4. live signals --------------------------------------------------------------
versions() {  # $@ = extra curl args; prints the scout versions of 10 signals
  local i
  for i in $(seq 1 10); do
    kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 10 "$@" "http://$SVC:9080/reviews/0" 2>/dev/null \
      | grep -o 'scout-v[0-9]' || echo "no-answer"
  done | sort | uniq -c | awk '{print $2"="$1}' | tr '\n' ' ' | sed 's/ $//'
}

for i in $(seq 1 20); do
  kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 5 -H "end-user: jason" \
    "http://$SVC:9080/reviews/0" 2>/dev/null | grep -q 'scout-v3' && break
  sleep 2
done

jason=$(versions -H "end-user: jason")
[[ "$jason" == "scout-v3=10" ]] || fail "10 signals as jason gave [$jason], expected all 10 from scout-v3"

others=$(versions)
[[ "$others" == "scout-v2=10" ]] || fail "10 signals without a label gave [$others], expected all 10 from scout-v2"

# --- 5. the patrol never saw a failed signal ---------------------------------
log=$(kubectl -n "$NS" logs deploy/patrol -c istio-proxy 2>/dev/null)
total=$(grep -c '"GET /reviews/0' <<<"$log")
[[ "$total" -ge 20 ]] || fail "the patrol's flight log has only $total signals - the patrol must keep flying during your change. Do not stop or restart it in the last minute before you submit"

failed=$(grep '"GET /reviews/0' <<<"$log" | grep -cE '" (5[0-9][0-9]) ')
if [[ "$failed" -gt 0 ]]; then
  flag=$(grep '"GET /reviews/0' <<<"$log" | grep -E '" (5[0-9][0-9]) ' | head -1 | grep -oE '5[0-9][0-9] [A-Z]+')
  fail "the patrol logged $failed failed signals during your change (first one: $flag). A route pointed at a subset that was already gone. Change the flight plan first, wait until the shuttle's proxy has it, then remove the v1 subset. To try again, restart the patrol with: kubectl rollout restart deploy/patrol -n $NS"
fi

echo "PASS: v1 is retired - jason flies to scout-v3, everyone else to scout-v2, the DestinationRule holds only v2 and v3, no route points at a missing subset, and the patrol logged $total signals without a single failure"
exit 0
