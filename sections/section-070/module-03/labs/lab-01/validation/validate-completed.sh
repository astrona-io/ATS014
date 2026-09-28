#!/usr/bin/env bash
# Confirms two WorkloadEntry objects with identity, a MESH_INTERNAL ServiceEntry
# selecting both by label, a matching WorkloadGroup template, and that the host
# resolves by name to both endpoints with traffic reaching them.

set -u

NS="vm-demo"
HOST="legacy.vm-demo.svc"
CLUSTER="outbound|8080||legacy.vm-demo.svc"

fail() { echo "FAIL: $*"; exit 1; }

VM1=$(cat /tmp/vm1-ip 2>/dev/null || kubectl -n "$NS" get pod legacy-vm-1 -o jsonpath='{.status.podIP}' 2>/dev/null)
VM2=$(cat /tmp/vm2-ip 2>/dev/null || kubectl -n "$NS" get pod legacy-vm-2 -o jsonpath='{.status.podIP}' 2>/dev/null)
[[ -n "$VM1" && -n "$VM2" ]] || fail "could not determine the stand-in machine addresses"

# --- 0. the environment is intact -------------------------------------------
r=$(kubectl -n "$NS" get deployment tester -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ -n "$r" && "$r" -ge 1 ]] || fail "tester - deployment missing or has no ready replicas"
for p in legacy-vm-1 legacy-vm-2; do
  ph=$(kubectl -n "$NS" get pod "$p" -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$ph" == "Running" ]] || fail "$NS/$p is '$ph', expected Running"
  cn=$(kubectl -n "$NS" get pod "$p" -o jsonpath='{.spec.initContainers[*].name} {.spec.containers[*].name}' 2>/dev/null)
  grep -qw istio-proxy <<<"$cn" \
    && fail "$p now has an istio-proxy sidecar. The point is to bring an UNINJECTED workload into the mesh with a WorkloadEntry, not to inject it"
done
if kubectl -n "$NS" get svc -o name 2>/dev/null | grep -qE 'legacy'; then
  fail "a Service for the legacy workloads exists in $NS. That would register them through the back door - the task is to declare them with WorkloadEntry"
fi
kubectl -n "$NS" get serviceaccount legacy-sa >/dev/null 2>&1 \
  || fail "ServiceAccount legacy-sa not found in $NS"

# --- 1. the two WorkloadEntry objects ---------------------------------------
check_entry() {
  local name="$1" want_ip="$2"
  kubectl -n "$NS" get workloadentry "$name" >/dev/null 2>&1 \
    || fail "WorkloadEntry '$name' not found in $NS"

  local addr lbl sa
  addr=$(kubectl -n "$NS" get workloadentry "$name" -o jsonpath='{.spec.address}' 2>/dev/null)
  lbl=$(kubectl -n "$NS" get workloadentry "$name" -o jsonpath='{.spec.labels.app}' 2>/dev/null)
  sa=$(kubectl -n "$NS" get workloadentry "$name" -o jsonpath='{.spec.serviceAccount}' 2>/dev/null)

  [[ "$addr" == "$want_ip" ]] \
    || fail "WorkloadEntry '$name' has address '$addr', expected $want_ip"
  [[ "$lbl" == "legacy-backend" ]] \
    || fail "WorkloadEntry '$name' has label app='$lbl', expected legacy-backend - this is what the ServiceEntry selector matches"
  [[ "$sa" == "legacy-sa" ]] \
    || fail "WorkloadEntry '$name' has serviceAccount '$sa', expected legacy-sa. Without it the workload has no mesh identity and no policy can name it"
}
check_entry legacy-vm-1 "$VM1"
check_entry legacy-vm-2 "$VM2"

# --- 2. the ServiceEntry ------------------------------------------------------
kubectl -n "$NS" get serviceentry legacy >/dev/null 2>&1 \
  || fail "ServiceEntry 'legacy' not found in $NS"

hosts=$(kubectl -n "$NS" get serviceentry legacy -o jsonpath='{.spec.hosts[*]}' 2>/dev/null)
grep -qw "$HOST" <<<"$hosts" || fail "the ServiceEntry hosts are [$hosts] - $HOST is missing"

loc=$(kubectl -n "$NS" get serviceentry legacy -o jsonpath='{.spec.location}' 2>/dev/null)
[[ "$loc" == "MESH_INTERNAL" ]] \
  || fail "location is '$loc', expected MESH_INTERNAL. MESH_EXTERNAL would route correctly and give the workloads no identity, no mTLS and no AuthorizationPolicy coverage"

res=$(kubectl -n "$NS" get serviceentry legacy -o jsonpath='{.spec.resolution}' 2>/dev/null)
[[ "$res" == "STATIC" ]] \
  || fail "resolution is '$res', expected STATIC. Selecting WorkloadEntry objects means the addresses are declared, so there is nothing to resolve"

pnum=$(kubectl -n "$NS" get serviceentry legacy -o jsonpath='{.spec.ports[0].number}' 2>/dev/null)
pproto=$(kubectl -n "$NS" get serviceentry legacy -o jsonpath='{.spec.ports[0].protocol}' 2>/dev/null)
[[ "$pnum" == "8080" ]]   || fail "the ServiceEntry port number is '$pnum', expected 8080"
[[ "$pproto" == "HTTP" ]] || fail "the ServiceEntry port protocol is '$pproto', expected HTTP"

wsel=$(kubectl -n "$NS" get serviceentry legacy \
  -o jsonpath='{.spec.workloadSelector.labels.app}' 2>/dev/null)
[[ "$wsel" == "legacy-backend" ]] \
  || fail "the workloadSelector matches app='$wsel', expected legacy-backend. A mismatch gives a host with zero endpoints and no validation error"

# --- 3. the WorkloadGroup ----------------------------------------------------
kubectl -n "$NS" get workloadgroup legacy >/dev/null 2>&1 \
  || fail "WorkloadGroup 'legacy' not found in $NS"
glbl=$(kubectl -n "$NS" get workloadgroup legacy -o jsonpath='{.spec.metadata.labels.app}' 2>/dev/null)
gsa=$(kubectl -n "$NS" get workloadgroup legacy -o jsonpath='{.spec.template.serviceAccount}' 2>/dev/null)
gport=$(kubectl -n "$NS" get workloadgroup legacy -o jsonpath='{.spec.template.ports.http}' 2>/dev/null)
[[ "$glbl" == "legacy-backend" ]] || fail "the WorkloadGroup template labels app='$glbl', expected legacy-backend"
[[ "$gsa" == "legacy-sa" ]]       || fail "the WorkloadGroup template serviceAccount is '$gsa', expected legacy-sa"
[[ "$gport" == "8080" ]]          || fail "the WorkloadGroup template port http is '$gport', expected 8080"

# --- 4. the registry has both endpoints -------------------------------------
clusters=$(istioctl proxy-config cluster deploy/tester -n "$NS" 2>/dev/null)
grep -q "$HOST" <<<"$clusters" \
  || fail "$HOST does not appear in the tester proxy's cluster list - the ServiceEntry never reached the sidecar"

eps=$(istioctl proxy-config endpoints deploy/tester -n "$NS" --cluster "$CLUSTER" 2>/dev/null)
n=$(grep -cE "${VM1}:8080|${VM2}:8080" <<<"$eps")
[[ "$n" -eq 2 ]] \
  || fail "the cluster for $HOST has $n of the 2 expected endpoints. Both WorkloadEntry objects must carry the label the workloadSelector matches"

# --- 5. live traffic by NAME -------------------------------------------------
code=$(kubectl -n "$NS" exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}' --max-time 15 "http://${HOST}:8080/get" 2>/dev/null)
[[ "$code" == "200" ]] \
  || fail "GET http://${HOST}:8080/get returned '$code', expected 200. The hostname only resolves because the ServiceEntry registered it"

echo "PASS: two WorkloadEntry objects (${VM1}, ${VM2}) carry app=legacy-backend and serviceAccount legacy-sa; a MESH_INTERNAL/STATIC ServiceEntry selects both and gives them the name ${HOST}; the cluster holds 2 endpoints, a WorkloadGroup template matches, and traffic reaches the machines by name"
exit 0
