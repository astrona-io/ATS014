#!/usr/bin/env bash
# Section 070 capstone. Confirms a still-deny-by-default mesh with: one external
# TLS-only host registered and originated from the sidecar, one non-Kubernetes
# workload brought in as MESH_INTERNAL with identity, and a third endpoint
# still refused.

set -u

NS="integrations"
fail() { echo "FAIL: $*"; exit 1; }

PARTNER=$(cat /tmp/partner-ip 2>/dev/null || kubectl -n outside-mesh get pod partner-api -o jsonpath='{.status.podIP}' 2>/dev/null)
BLOCKED=$(cat /tmp/blocked-ip 2>/dev/null || kubectl -n outside-mesh get pod blocked-api -o jsonpath='{.status.podIP}' 2>/dev/null)
VM=$(cat /tmp/vm-ip 2>/dev/null || kubectl -n "$NS" get pod legacy-vm -o jsonpath='{.status.podIP}' 2>/dev/null)
[[ -n "$PARTNER" && -n "$BLOCKED" && -n "$VM" ]] || fail "could not determine one or more endpoint addresses"

tester_code() {
  kubectl -n "$NS" exec deploy/tester -- \
    curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$1" 2>/dev/null
}
tester_body() {
  kubectl -n "$NS" exec deploy/tester -- curl -s --max-time 15 "$1" 2>/dev/null
}

# --- 0. environment intact, mesh still locked down --------------------------
r=$(kubectl -n "$NS" get deployment tester -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ -n "$r" && "$r" -ge 1 ]] || fail "tester - deployment missing or has no ready replicas"
for nsp in "$NS/legacy-vm" outside-mesh/partner-api outside-mesh/blocked-api; do
  n=${nsp%%/*}; p=${nsp##*/}
  ph=$(kubectl -n "$n" get pod "$p" -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$ph" == "Running" ]] || fail "$nsp is '$ph', expected Running"
done
if kubectl -n outside-mesh get svc -o name 2>/dev/null | grep -q .; then
  fail "a Service exists in outside-mesh - that registers an endpoint through the back door"
fi
cn=$(kubectl -n "$NS" get pod legacy-vm -o jsonpath='{.spec.initContainers[*].name} {.spec.containers[*].name}' 2>/dev/null)
grep -qw istio-proxy <<<"$cn" && fail "legacy-vm now has a sidecar - it must stay uninjected and be declared instead"

mode=$(kubectl -n istio-system get cm istio -o jsonpath='{.data.mesh}' 2>/dev/null \
  | grep -A2 outboundTrafficPolicy | grep -o 'REGISTRY_ONLY' | head -1)
[[ "$mode" == "REGISTRY_ONLY" ]] \
  || fail "the mesh is no longer REGISTRY_ONLY. Do not relax the mesh policy - the task is three precise grants"

# ======================= A: the partner API =================================
kubectl -n "$NS" get serviceentry partner >/dev/null 2>&1 || fail "ServiceEntry 'partner' not found in $NS"

ph=$(kubectl -n "$NS" get serviceentry partner -o jsonpath='{.spec.hosts[*]}' 2>/dev/null)
grep -qw 'partner.example.com' <<<"$ph" || fail "the partner ServiceEntry hosts are [$ph]"
pa=$(kubectl -n "$NS" get serviceentry partner -o jsonpath='{.spec.addresses[*]}' 2>/dev/null)
grep -q "$PARTNER" <<<"$pa" || fail "the partner ServiceEntry addresses are [$pa] - $PARTNER is missing"
grep -q "$BLOCKED" <<<"$pa" && fail "the partner ServiceEntry addresses include the blocked endpoint $BLOCKED"

pl=$(kubectl -n "$NS" get serviceentry partner -o jsonpath='{.spec.location}' 2>/dev/null)
pr=$(kubectl -n "$NS" get serviceentry partner -o jsonpath='{.spec.resolution}' 2>/dev/null)
pe=$(kubectl -n "$NS" get serviceentry partner -o jsonpath='{.spec.exportTo[*]}' 2>/dev/null)
[[ "$pl" == "MESH_EXTERNAL" ]] || fail "the partner ServiceEntry location is '$pl', expected MESH_EXTERNAL"
[[ "$pr" == "STATIC" ]]        || fail "the partner ServiceEntry resolution is '$pr', expected STATIC"
[[ "$pe" == "." ]]             || fail "the partner ServiceEntry exportTo is [$pe], expected [\".\"]"

pp() { kubectl -n "$NS" get serviceentry partner -o jsonpath="{.spec.ports[?(@.number==$1)].protocol}" 2>/dev/null; }
[[ "$(pp 8080)" == "HTTP" ]]  || fail "partner port 8080 is '$(pp 8080)', expected HTTP"
[[ "$(pp 8443)" == "HTTPS" ]] || fail "partner port 8443 is '$(pp 8443)', expected HTTPS"

mport=$(kubectl -n "$NS" get virtualservice partner -o jsonpath='{.spec.http[0].match[0].port}' 2>/dev/null)
dport=$(kubectl -n "$NS" get virtualservice partner -o jsonpath='{.spec.http[0].route[0].destination.port.number}' 2>/dev/null)
[[ "$mport" == "8080" ]] || fail "the partner VirtualService matches port '$mport', expected 8080"
[[ "$dport" == "8443" ]] || fail "the partner VirtualService routes to port '$dport', expected 8443"

toptls=$(kubectl -n "$NS" get destinationrule partner -o jsonpath='{.spec.trafficPolicy.tls.mode}' 2>/dev/null)
[[ -z "$toptls" ]] \
  || fail "the partner DestinationRule sets tls at the TOP level of trafficPolicy (mode '$toptls'). That applies to port 8080 too and breaks the plaintext side"
plp=$(kubectl -n "$NS" get destinationrule partner -o jsonpath='{.spec.trafficPolicy.portLevelSettings[0].port.number}' 2>/dev/null)
plm=$(kubectl -n "$NS" get destinationrule partner -o jsonpath='{.spec.trafficPolicy.portLevelSettings[0].tls.mode}' 2>/dev/null)
pls=$(kubectl -n "$NS" get destinationrule partner -o jsonpath='{.spec.trafficPolicy.portLevelSettings[0].tls.sni}' 2>/dev/null)
[[ "$plp" == "8443" ]]                 || fail "portLevelSettings port is '$plp', expected 8443"
[[ "$plm" == "SIMPLE" ]]               || fail "the port 8443 tls mode is '$plm', expected SIMPLE"
[[ "$pls" == "partner.example.com" ]]  || fail "the port 8443 tls sni is '$pls', expected partner.example.com"

code=$(tester_code "http://${PARTNER}:8080/")
[[ "$code" == "200" ]] \
  || fail "GET http://${PARTNER}:8080/ returned '$code', expected 200. The endpoint speaks only TLS, so a failure means plaintext was sent"
body=$(tester_body "http://${PARTNER}:8080/")
grep -q 'scheme=https' <<<"$body" \
  || fail "the partner endpoint reported '$body', expected 'scheme=https' - TLS was not originated"

# ======================= B: your machine ====================================
kubectl -n "$NS" get workloadentry legacy-vm >/dev/null 2>&1 || fail "WorkloadEntry 'legacy-vm' not found in $NS"
wa=$(kubectl -n "$NS" get workloadentry legacy-vm -o jsonpath='{.spec.address}' 2>/dev/null)
wl=$(kubectl -n "$NS" get workloadentry legacy-vm -o jsonpath='{.spec.labels.app}' 2>/dev/null)
ws=$(kubectl -n "$NS" get workloadentry legacy-vm -o jsonpath='{.spec.serviceAccount}' 2>/dev/null)
[[ "$wa" == "$VM" ]]         || fail "the WorkloadEntry address is '$wa', expected $VM"
[[ "$wl" == "legacy" ]]      || fail "the WorkloadEntry label app is '$wl', expected legacy"
[[ "$ws" == "legacy-sa" ]] \
  || fail "the WorkloadEntry serviceAccount is '$ws', expected legacy-sa. Without it the workload has no mesh identity"

kubectl -n "$NS" get serviceentry legacy >/dev/null 2>&1 || fail "ServiceEntry 'legacy' not found in $NS"
ll=$(kubectl -n "$NS" get serviceentry legacy -o jsonpath='{.spec.location}' 2>/dev/null)
lr=$(kubectl -n "$NS" get serviceentry legacy -o jsonpath='{.spec.resolution}' 2>/dev/null)
lw=$(kubectl -n "$NS" get serviceentry legacy -o jsonpath='{.spec.workloadSelector.labels.app}' 2>/dev/null)
[[ "$ll" == "MESH_INTERNAL" ]] \
  || fail "the legacy ServiceEntry location is '$ll', expected MESH_INTERNAL. MESH_EXTERNAL routes correctly and gives the workload no identity"
[[ "$lr" == "STATIC" ]]   || fail "the legacy ServiceEntry resolution is '$lr', expected STATIC"
[[ "$lw" == "legacy" ]]   || fail "the legacy workloadSelector matches app='$lw', expected legacy"

code=$(tester_code "http://legacy.${NS}.svc:8080/get")
[[ "$code" == "200" ]] \
  || fail "GET http://legacy.${NS}.svc:8080/get returned '$code', expected 200. The hostname only resolves because the ServiceEntry registered it"

# ======================= C: the blocked endpoint ============================
code=$(tester_code "http://${BLOCKED}:8080/get")
[[ "$code" == "200" ]] \
  && fail "GET http://${BLOCKED}:8080/get returned 200 - blocked-api must stay refused"

echo "PASS: mesh still REGISTRY_ONLY; partner.example.com registered with both ports and TLS originated from the sidecar (endpoint reported scheme=https to a plain http:// call); legacy-vm brought in as MESH_INTERNAL with identity legacy-sa and reachable at legacy.${NS}.svc; blocked-api still refused"
exit 0
