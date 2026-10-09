#!/usr/bin/env bash
# Confirms the freighter ServiceEntry works again, as a service inside the mesh:
# the shuttle's proxy holds exactly the two freighter addresses behind
# freighter.starfleet.mesh, live requests by name reach both freighter pods, the
# ServiceEntry is MESH_INTERNAL and STATIC and selects app=freighter, and the
# entries, the stand-in pods and the DestinationRule were left as handed over.

set -u

NS="starfleet"
HOST="freighter.starfleet.mesh"
CLUSTER="outbound|8080||${HOST}"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is still what the lab handed over -------------------
for d in shuttle freighter-vm-1 freighter-vm-2; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the deployments alone: the fix belongs in the Istio objects"
done

VM1=$(kubectl -n "$NS" get pod -l ship=freighter-vm-1 -o jsonpath='{.items[0].status.podIP}' 2>/dev/null)
VM2=$(kubectl -n "$NS" get pod -l ship=freighter-vm-2 -o jsonpath='{.items[0].status.podIP}' 2>/dev/null)
[[ -n "$VM1" && -n "$VM2" ]] || fail "could not read the addresses of the freighter-vm-1 and freighter-vm-2 pods"

for s in freighter-vm-1 freighter-vm-2; do
  cn=$(kubectl -n "$NS" get pod -l ship="$s" -o jsonpath='{.items[0].spec.containers[*].name} {.items[0].spec.initContainers[*].name}' 2>/dev/null)
  grep -qw istio-proxy <<<"$cn" \
    && fail "$s now has an istio-proxy sidecar. The freighter pods stand in for virtual machines outside the mesh: bring them in with WorkloadEntry, not by injecting them"
done

if [[ -n "$(kubectl -n "$NS" get svc -o name 2>/dev/null | grep -i freighter)" ]]; then
  fail "a Kubernetes Service for the freighter pods exists in $NS. Remove it: the freighter pods must reach the mesh through the ServiceEntry and its WorkloadEntry objects"
fi

tls=$(kubectl -n "$NS" get destinationrule freighter -o jsonpath='{.spec.trafficPolicy.tls.mode}' 2>/dev/null)
[[ "$tls" == "DISABLE" ]] \
  || fail "the DestinationRule 'freighter' with tls mode DISABLE is missing or changed (found '$tls'). Leave it in place: the stand-ins have no sidecar and cannot answer mutual TLS"

# --- 1. the WorkloadEntry objects --------------------------------------------
check_entry() {
  local name="$1" want_ip="$2" addr sa
  kubectl -n "$NS" get workloadentry "$name" >/dev/null 2>&1 \
    || fail "WorkloadEntry '$name' not found in $NS - keep both entries, they are how the mesh knows the freighter pods"
  addr=$(kubectl -n "$NS" get workloadentry "$name" -o jsonpath='{.spec.address}' 2>/dev/null)
  sa=$(kubectl -n "$NS" get workloadentry "$name" -o jsonpath='{.spec.serviceAccount}' 2>/dev/null)
  [[ "$addr" == "$want_ip" ]] \
    || fail "WorkloadEntry '$name' has address '$addr', but its freighter pod has $want_ip. Leave the addresses as they were"
  [[ "$sa" == "freighter" ]] \
    || fail "WorkloadEntry '$name' has serviceAccount '$sa', expected freighter. It is the machine's identity - leave it as it was"
}
check_entry freighter-vm-1 "$VM1"
check_entry freighter-vm-2 "$VM2"

# --- 2. the ServiceEntry -----------------------------------------------------
kubectl -n "$NS" get serviceentry freighter >/dev/null 2>&1 \
  || fail "ServiceEntry 'freighter' not found in $NS - fix it, do not delete it"
hosts=$(kubectl -n "$NS" get serviceentry freighter -o jsonpath='{.spec.hosts[*]}' 2>/dev/null)
[[ "$hosts" == "$HOST" ]] || fail "the ServiceEntry hosts are [$hosts], expected exactly $HOST"
pnum=$(kubectl -n "$NS" get serviceentry freighter -o jsonpath='{.spec.ports[0].number}' 2>/dev/null)
pproto=$(kubectl -n "$NS" get serviceentry freighter -o jsonpath='{.spec.ports[0].protocol}' 2>/dev/null)
[[ "$pnum" == "8080" && "$pproto" == "HTTP" ]] \
  || fail "the ServiceEntry port is $pnum/$pproto, expected 8080/HTTP"

# --- 3. live behaviour: the shuttle's proxy and real requests -----------------
# Behaviour first: on the starting state this is the first thing that fails.
eps=""; n=0
for _ in $(seq 1 10); do
  eps=$(istioctl proxy-config endpoints deploy/shuttle -n "$NS" --cluster "$CLUSTER" 2>/dev/null)
  n=$(grep -cE "^(${VM1}|${VM2}):8080 " <<<"$eps")
  [[ "$n" -eq 2 ]] && break
  sleep 3
done
total=$(grep -c ":8080 " <<<"$eps")
if [[ "$n" -ne 2 || "$total" -ne 2 ]]; then
  fail "the shuttle's proxy has $total endpoint(s) behind $HOST, $n of them freighter addresses; expected exactly the two freighter pods (${VM1} and ${VM2}). Run 'istioctl proxy-config endpoints deploy/shuttle -n $NS --cluster \"$CLUSTER\"' and compare the ServiceEntry's workloadSelector labels with the labels on each WorkloadEntry"
fi

ok=0; seen1=0; seen2=0
for _ in $(seq 1 20); do
  body=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 5 "http://${HOST}:8080/hostname" 2>/dev/null)
  grep -q '"hostname"' <<<"$body" && ok=$((ok+1))
  grep -q 'freighter-vm-1' <<<"$body" && seen1=1
  grep -q 'freighter-vm-2' <<<"$body" && seen2=1
done
[[ "$ok" -eq 20 ]] \
  || fail "only $ok of 20 requests to http://${HOST}:8080/hostname were answered. Read the shuttle's access log: kubectl logs -n $NS deploy/shuttle -c istio-proxy --tail=5"
[[ "$seen1" -eq 1 && "$seen2" -eq 1 ]] \
  || fail "20 requests by name never reached both freighter pods (freighter-vm-1 seen: $seen1, freighter-vm-2 seen: $seen2)"

# --- 4. a service inside the mesh, not an external one -----------------------
loc=$(kubectl -n "$NS" get serviceentry freighter -o jsonpath='{.spec.location}' 2>/dev/null)
[[ "$loc" == "MESH_INTERNAL" ]] \
  || fail "requests work, but the ServiceEntry location is '$loc'. The freighter machines belong to the mesh: MESH_EXTERNAL treats them as external services, with no identity and no mutual TLS once they get a sidecar. Set location: MESH_INTERNAL"
res=$(kubectl -n "$NS" get serviceentry freighter -o jsonpath='{.spec.resolution}' 2>/dev/null)
[[ "$res" == "STATIC" ]] \
  || fail "the ServiceEntry resolution is '$res', expected STATIC: the WorkloadEntry objects already hold the addresses"
wsel=$(kubectl -n "$NS" get serviceentry freighter -o jsonpath='{.spec.workloadSelector.labels}' 2>/dev/null)
[[ "$wsel" == '{"app":"freighter"}' ]] \
  || fail "the ServiceEntry workloadSelector is $wsel, expected exactly app=freighter"
for name in freighter-vm-1 freighter-vm-2; do
  lbl=$(kubectl -n "$NS" get workloadentry "$name" -o jsonpath='{.spec.labels.app}' 2>/dev/null)
  [[ "$lbl" == "freighter" ]] || fail "WorkloadEntry '$name' carries app='$lbl', expected freighter"
done

echo "PASS: freighter.starfleet.mesh is a MESH_INTERNAL, STATIC ServiceEntry selecting app=freighter; the shuttle's proxy holds both freighter pods (${VM1}, ${VM2}) and 20 of 20 requests by name were answered by both of them"
exit 0
