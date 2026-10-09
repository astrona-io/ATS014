#!/usr/bin/env bash
# Confirms HTTP routing for the probe works again: the probe Service's port
# 8000 is declared as HTTP (by name or appProtocol) with its numbers and
# selector unchanged, the probe is back in the shuttle's route table, the
# flight plan still uses its `http` rule, and - the part that matters - live
# signals with `x-mission: test` reach probe-v2 and all others reach probe-v1.

set -u

NS="starfleet"
SVC="probe"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is still what the lab handed over -------------------
for d in probe-v1 probe-v2 shuttle; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the ships alone: the fault is in the Service"
done

deploy_count=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$deploy_count" -eq 3 ]] || fail "$NS holds $deploy_count deployments, expected exactly 3 - do not add or remove ships"

for v in v1 v2; do
  lbl=$(kubectl -n "$NS" get deployment "probe-$v" -o jsonpath='{.spec.template.metadata.labels.version}' 2>/dev/null)
  [[ "$lbl" == "$v" ]] || fail "deployment probe-$v now labels its pods version='$lbl', expected '$v'. Do not relabel the ships"
done

# --- 1. the Service port is declared as HTTP, numbers and selector unchanged --
kubectl -n "$NS" get service "$SVC" >/dev/null 2>&1 || fail "Service $SVC not found in $NS - fix the existing Service, do not delete it"

selector=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.selector.app}|{.spec.selector.version}' 2>/dev/null)
[[ "$selector" == "probe|" ]] || fail "the $SVC Service selector changed (app|version = '$selector'). It must keep selecting app=probe only"

nports=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.ports[*].port}' 2>/dev/null | wc -w | tr -d ' ')
[[ "$nports" -eq 1 ]] || fail "the $SVC Service has $nports ports, expected exactly one (port 8000)"

port=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
target=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)
[[ "$port" == "8000" && "$target" == "8080" ]] || fail "the $SVC port is now $port -> $target, expected 8000 -> 8080. Only the protocol declaration is wrong, not the numbers"

pname=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.ports[0].name}' 2>/dev/null)
papp=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.ports[0].appProtocol}' 2>/dev/null)
declared_http=no
[[ "$papp" == "http" ]] && declared_http=yes
if [[ -z "$papp" ]]; then
  [[ "$pname" == "http" || "$pname" == http-* ]] && declared_http=yes
fi
[[ "$declared_http" == "yes" ]] || fail "the $SVC port is named '$pname' (appProtocol '${papp:-unset}'). Istio believes that declaration: it is not HTTP, so the flight plan's http rules are never read. Name the port http (or http-<something>), or set appProtocol: http"

# --- 2. DestinationRule and flight plan are still the ones handed over ---------
kubectl -n "$NS" get destinationrule "$SVC" >/dev/null 2>&1 || fail "DestinationRule '$SVC' not found in $NS - it was correct, leave it in place"
for s in v1 v2; do
  lbl=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath="{.spec.subsets[?(@.name=='$s')].labels.version}" 2>/dev/null)
  [[ "$lbl" == "$s" ]] || fail "DestinationRule subset '$s' selects version='$lbl' - leave the DestinationRule unchanged"
done

kubectl -n "$NS" get virtualservice "$SVC" >/dev/null 2>&1 || fail "VirtualService '$SVC' not found in $NS - the flight plan was correct, leave it in place"
tcp_rules=$(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{.spec.tcp}' 2>/dev/null)
[[ -z "$tcp_rules" ]] || fail "the flight plan now has a tcp list. Keep its http rule: the task is to make the port HTTP again, not to route bytes"
rules=$(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{range .spec.http[*]}{.match[0].headers.x-mission.exact}|{.route[0].destination.subset};{end}' 2>/dev/null)
[[ "$rules" == "test|v2;|v1;" ]] || fail "the flight plan's http rules are now [$rules], expected the original two: x-mission=test to v2, then a catch-all to v1. Leave the flight plan unchanged"

# --- 3. the probe is back in the shuttle's route table ---------------------------
in_routes=no
for i in $(seq 1 30); do
  if istioctl proxy-config routes deploy/shuttle -n "$NS" --name 8000 2>/dev/null | grep -q "probe.$NS.svc.cluster.local"; then
    in_routes=yes; break
  fi
  sleep 2
done
[[ "$in_routes" == "yes" ]] || fail "the probe is not in the shuttle's route table for port 8000 (istioctl proxy-config routes deploy/shuttle -n $NS --name 8000). Its port is still treated as plain TCP"

# --- 4. live signals ---------------------------------------------------------------
versions() {  # $@ = extra curl args; prints the probe versions of 10 signals
  local i
  for i in $(seq 1 10); do
    kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 10 "$@" "http://$SVC:8000/hostname" 2>/dev/null \
      | grep -o 'probe-v[0-9]' || echo "no-answer"
  done | sort | uniq -c | awk '{print $2"="$1}' | tr '\n' ' ' | sed 's/ $//'
}

settle() {  # wait until the endpoints and the route have reached the shuttle
  local i
  for i in $(seq 1 30); do
    kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 5 -H "x-mission: test" \
      "http://$SVC:8000/hostname" 2>/dev/null | grep -q 'probe-v2' && return 0
    sleep 2
  done
}
settle

mission=$(versions -H "x-mission: test")
[[ "$mission" == "probe-v2=10" ]] || fail "10 signals with x-mission: test gave [$mission], expected all 10 from probe-v2. If both versions answer, the http rule is still not being read: check how the probe's port is declared"

others=$(versions)
[[ "$others" == "probe-v1=10" ]] || fail "10 signals without the header gave [$others], expected all 10 from probe-v1"

echo "PASS: the probe's port 8000 is declared as HTTP ($pname${papp:+, appProtocol $papp}), the probe is back in the shuttle's route table, the flight plan's http rule is read, x-mission: test reaches probe-v2 and everyone else probe-v1"
exit 0
