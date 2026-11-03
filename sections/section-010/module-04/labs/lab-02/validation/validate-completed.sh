#!/usr/bin/env bash
# Grades the exportTo repair: the two exportTo lists, then real requests from
# the shuttle in each namespace, then the cluster lists of the dock and depot proxies.

set -u

NS="starfleet"
FQDN="probe.starfleet.svc.cluster.local"

fail() { echo "FAIL: $*"; exit 1; }

# Print the pod name versions of 10 requests from the shuttle in namespace $1 to URL $2.
count_versions() {
  for _ in $(seq 1 10); do
    kubectl -n "$1" exec deploy/shuttle -- curl -s --max-time 10 "$2" 2>/dev/null \
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

# --- 1. the objects and their exportTo lists --------------------------------
kubectl -n "$NS" get virtualservice probe >/dev/null 2>&1 || fail "VirtualService 'probe' not found in $NS"
kubectl -n "$NS" get destinationrule probe >/dev/null 2>&1 || fail "DestinationRule 'probe' not found in $NS"

vs_export=$(export_list virtualservice)
[[ "$vs_export" == ". dock" ]] || fail "the VirtualService exportTo is [$vs_export], expected exactly the own namespace and dock"
dr_export=$(export_list destinationrule)
[[ "$dr_export" == ". dock" ]] || fail "the DestinationRule exportTo is [$dr_export], expected exactly the own namespace and dock (a hidden DestinationRule gives 503 NC in dock)"

vs_subsets=$(kubectl -n "$NS" get virtualservice probe -o jsonpath='{.spec.http[*].route[*].destination.subset}' 2>/dev/null)
[[ "$vs_subsets" == "v2" ]] || fail "the VirtualService routes to [$vs_subsets], expected only v2"
dr_subsets=$(kubectl -n "$NS" get destinationrule probe -o jsonpath='{.spec.subsets[*].name}' 2>/dev/null)
for s in v1 v2; do
  grep -qw "$s" <<<"$dr_subsets" || fail "the DestinationRule no longer has the subset '$s'"
done

for n in dock depot; do
  other=$(kubectl -n "$n" get virtualservice,destinationrule -o name 2>/dev/null)
  [[ -z "$other" ]] || fail "namespace $n holds Istio objects [$other] - fix the exportTo lists instead"
done

# --- 2. live traffic ---------------------------------------------------------
# Retry for a while: istiod needs a moment to push the changes.
ok=0
for attempt in $(seq 1 12); do
  dock_result=$(count_versions dock "http://$FQDN:8000/hostname")
  [[ "$dock_result" == " 10 probe-v2;" ]] && { ok=1; break; }
  sleep 5
done
[[ "$ok" -eq 1 ]] || fail "10 requests from the shuttle in dock were answered as [$dock_result] - expected 10 from probe-v2"

star_result=$(count_versions starfleet "http://probe:8000/hostname")
[[ "$star_result" == " 10 probe-v2;" ]] || fail "10 requests from the shuttle in starfleet were answered as [$star_result] - expected 10 from probe-v2"

v1_seen=0
for _ in $(seq 1 30); do
  body=$(kubectl -n depot exec deploy/shuttle -- curl -s --max-time 10 "http://$FQDN:8000/hostname" 2>/dev/null)
  grep -q 'probe-v1' <<<"$body" && v1_seen=$((v1_seen + 1))
done
[[ "$v1_seen" -ge 1 ]] || fail "30 requests from the shuttle in depot never reached probe-v1 - depot must keep the default behaviour"

# --- 3. what the proxies in dock and depot received --------------------------
dock_clusters=$(istioctl proxy-config clusters deploy/shuttle -n dock --fqdn "$FQDN" 2>/dev/null)
grep -q 'v2' <<<"$dock_clusters" || fail "the proxy in dock has no cluster for the subset v2 of $FQDN - the DestinationRule is not exported to dock"
depot_clusters=$(istioctl proxy-config clusters deploy/shuttle -n depot --fqdn "$FQDN" 2>/dev/null)
if grep -q 'v2' <<<"$depot_clusters"; then
  fail "the proxy in depot has a cluster for the subset v2 - the DestinationRule is exported to depot"
fi

echo "PASS: the VirtualService and the DestinationRule reach dock and starfleet only, and depot is unchanged"
exit 0
