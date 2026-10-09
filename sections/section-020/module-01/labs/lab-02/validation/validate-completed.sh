#!/usr/bin/env bash
# Confirms the scout flight plan (VirtualService) is one weighted route that
# sends v1 60, v2 30 and v3 10, that the shuttle's proxy holds those weights,
# that the docking instructions and the ships were left alone, and - the part
# that matters - that 200 live signals really split in those shares.

set -u

NS="starfleet"
SVC="scout"
FQDN="scout.starfleet.svc.cluster.local"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is still what the lab handed over -------------------
for d in bridge-v1 cargo-v1 navcom-v1 scout-v1 scout-v2 scout-v3 shuttle; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the ships alone: the task is the flight plan"
done

deploy_count=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$deploy_count" -eq 7 ]] || fail "$NS holds $deploy_count deployments, expected exactly 7 - do not add or remove ships"

for v in v1 v2 v3; do
  replicas=$(kubectl -n "$NS" get deployment "scout-$v" -o jsonpath='{.spec.replicas}' 2>/dev/null)
  [[ "$replicas" == "1" ]] || fail "scout-$v runs $replicas replicas, expected 1. The share of signals is set by weights, not by the number of pods - do not scale the ships"
done

# --- 1. the DestinationRule is unchanged -------------------------------------
names=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.subsets[*].name}' 2>/dev/null | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')
[[ "$names" == "v1 v2 v3" ]] || fail "DestinationRule '$SVC' subsets are [$names], expected exactly v1, v2 and v3. The docking instructions were correct - leave them as they were"
for s in v1 v2 v3; do
  lbl=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath="{.spec.subsets[?(@.name=='$s')].labels.version}" 2>/dev/null)
  [[ "$lbl" == "$s" ]] || fail "subset '$s' now selects version='$lbl', expected '$s'. Leave the DestinationRule unchanged"
done

# --- 2. the VirtualService ---------------------------------------------------
kubectl -n "$NS" get virtualservice "$SVC" >/dev/null 2>&1 \
  || fail "VirtualService '$SVC' not found in $NS - change the existing flight plan, do not delete it"

vs_count=$(kubectl get virtualservice -A -o jsonpath='{range .items[*]}{.spec.hosts[*]}{"\n"}{end}' 2>/dev/null | grep -cE "^($SVC|$FQDN)( |$)")
[[ "$vs_count" -eq 1 ]] || fail "found $vs_count VirtualService objects for the scout, expected exactly one. Two flight plans for one beacon have no set order"

rule_count=$(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{range .spec.http[*]}x{end}' 2>/dev/null | wc -c | tr -d ' ')
[[ "$rule_count" -eq 1 ]] || fail "the flight plan has $rule_count http rules, expected exactly one. Put all three destinations in one route list"

has_match=$(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{.spec.http[0].match}' 2>/dev/null)
[[ -z "$has_match" ]] || fail "the http rule has a match block ($has_match). The split must apply to every scout signal, so the rule needs no match"

split=$(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{range .spec.http[0].route[*]}{.destination.subset}={.weight};{end}' 2>/dev/null \
  | tr ';' '\n' | sed '/^$/d' | sed 's/=$/=no weight/' | sort | tr '\n' ' ' | sed 's/ $//')
[[ "$split" == "v1=60 v2=30 v3=10" ]] || fail "the route sends [$split], expected v1=60 v2=30 v3=10. Give every destination a weight next to (not inside) 'destination', in one route list"

for d in $(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{.spec.http[0].route[*].destination.host}' 2>/dev/null); do
  case "$d" in "$SVC"|"$SVC.$NS"|"$SVC.$NS.svc"|"$FQDN") ;;
    *) fail "a destination points at host '$d', expected the scout ($SVC)";; esac
done

# --- 3. the shuttle's proxy holds the weights --------------------------------
got=""
for i in $(seq 1 30); do
  got=$(istioctl proxy-config routes deploy/shuttle -n "$NS" --name 9080 -o json 2>/dev/null \
    | tr -d ' \n' | grep -oE '"name":"outbound\|9080\|v[0-9]\|scout\.starfleet\.svc\.cluster\.local","weight":[0-9]+' \
    | sed -E 's/.*\|(v[0-9])\|.*"weight":([0-9]+)/\1=\2/' | sort | tr '\n' ' ' | sed 's/ $//')
  [[ "$got" == "v1=60 v2=30 v3=10" ]] && break
  sleep 2
done
[[ "$got" == "v1=60 v2=30 v3=10" ]] || fail "the shuttle's proxy holds the weights [$got], expected v1=60 v2=30 v3=10. The flight plan has not reached the proxy - check its namespace and host name"

# --- 4. 200 live signals -------------------------------------------------------
counts=$(kubectl -n "$NS" exec deploy/shuttle -- sh -c \
  'for i in $(seq 1 200); do curl -s --max-time 5 http://scout:9080/reviews/0 | grep -o "scout-v[0-9]" || echo none; done' 2>/dev/null \
  | sort | uniq -c)
n() { awk -v v="$1" '$2==v {print $1}' <<<"$counts" | head -1; }
v1=$(n scout-v1); v2=$(n scout-v2); v3=$(n scout-v3)
v1=${v1:-0}; v2=${v2:-0}; v3=${v3:-0}
summary="v1=$v1 v2=$v2 v3=$v3 of 200"
(( v1 >= 90 && v1 <= 150 )) || fail "200 signals gave [$summary]. v1 should get about 120 (60%)"
(( v2 >= 36 && v2 <= 84 ))  || fail "200 signals gave [$summary]. v2 should get about 60 (30%)"
(( v3 >= 6 && v3 <= 40 ))   || fail "200 signals gave [$summary]. v3 should get about 20 (10%)"

echo "PASS: one flight plan sends the scout v1 60, v2 30 and v3 10, the shuttle's proxy holds those weights, the docking instructions and ships are unchanged, and 200 live signals split $summary"
exit 0
