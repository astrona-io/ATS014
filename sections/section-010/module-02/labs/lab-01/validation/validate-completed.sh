#!/usr/bin/env bash
# Confirms a namespace-wide Sidecar in sidecar-demo scopes egress to its own
# namespace, istio-system and sidecar-other; that sidecar-third really left the
# proxy's config and is unreachable; that the permitted destinations still work;
# and that nothing was deleted to make that true.

set -u

NS="sidecar-demo"
OK_NS="sidecar-other"
DENY_NS="sidecar-third"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. nothing was removed to fake the result ------------------------------
for ns in "$NS" "$OK_NS" "$DENY_NS"; do
  kubectl get namespace "$ns" >/dev/null 2>&1 || fail "namespace $ns not found - it must not be deleted"
done

check_ready() {
  local ns="$1" d="$2"
  local r
  r=$(kubectl -n "$ns" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$r" && "$r" -ge 1 ]] || fail "$ns/$d - deployment missing or has no ready replicas. The target must stay running; scoping is what stops the traffic"
}
check_ready "$NS" tester
check_ready "$NS" local-backend
check_ready "$OK_NS" httpbin
check_ready "$DENY_NS" httpbin

for ns in "$OK_NS" "$DENY_NS"; do
  kubectl -n "$ns" get service httpbin >/dev/null 2>&1 || fail "$ns/httpbin service not found - it must be left in place"
done

# --- 1. the Sidecar object ---------------------------------------------------
kubectl -n "$NS" get sidecar default >/dev/null 2>&1 \
  || fail "Sidecar 'default' not found in $NS"

sel=$(kubectl -n "$NS" get sidecar default -o jsonpath='{.spec.workloadSelector}' 2>/dev/null)
if [[ -n "$sel" && "$sel" != "{}" ]]; then
  fail "Sidecar 'default' has a workloadSelector ($sel) - it must apply to the whole namespace, so leave the selector out"
fi

sc_count=$(kubectl -n "$NS" get sidecar -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$sc_count" -eq 1 ]] || fail "$NS holds $sc_count Sidecar resources, expected exactly 1 - two namespace-wide resources is undefined behaviour, not a merge"

hosts=$(kubectl -n "$NS" get sidecar default -o jsonpath='{.spec.egress[*].hosts[*]}' 2>/dev/null)
[[ -n "$hosts" ]] || fail "Sidecar 'default' has no egress hosts"

want_own=0 want_istio=0 want_other=0 saw_wildcard=0 saw_deny=0
for h in $hosts; do
  case "$h" in
    "./*"|"$NS/*")                 want_own=1 ;;
    "istio-system/*")              want_istio=1 ;;
    "$OK_NS/*"|"$OK_NS/httpbin"*)  want_other=1 ;;
    "*/*")                         saw_wildcard=1 ;;
    "$DENY_NS/"*)                  saw_deny=1 ;;
  esac
done

[[ "$want_own"   -eq 1 ]] || fail "egress hosts are [$hosts] - the proxy's own namespace is missing. Use './*'"
[[ "$want_istio" -eq 1 ]] || fail "egress hosts are [$hosts] - 'istio-system/*' is missing. Without it the proxy loses control plane and telemetry destinations"
[[ "$want_other" -eq 1 ]] || fail "egress hosts are [$hosts] - '$OK_NS/*' is missing, so the namespace you were told to keep reachable is scoped out"
[[ "$saw_wildcard" -eq 0 ]] || fail "egress hosts include '*/*', which is the unscoped default written down - nothing has been narrowed"
[[ "$saw_deny" -eq 0 ]] || fail "egress hosts include a $DENY_NS entry - that namespace must be scoped out"

# --- 2. the proxy really received it ----------------------------------------
clusters=$(istioctl proxy-config cluster deploy/tester -n "$NS" 2>/dev/null)
[[ -n "$clusters" ]] || fail "could not read the tester proxy's cluster config"

if grep -q "$DENY_NS" <<<"$clusters"; then
  fail "the tester proxy still holds clusters for $DENY_NS - the Sidecar exists but the scoping did not take effect. Check the namespace and give the push a few seconds"
fi
grep -q "$OK_NS" <<<"$clusters" \
  || fail "the tester proxy has no cluster for $OK_NS - it was scoped out along with $DENY_NS"
grep -q "local-backend" <<<"$clusters" \
  || fail "the tester proxy has no cluster for local-backend in its own namespace - './*' is missing or wrong"

cluster_lines=$(wc -l <<<"$clusters" | tr -d ' ')
[[ "$cluster_lines" -lt 60 ]] \
  || fail "the tester proxy still carries $cluster_lines cluster rows, which does not look scoped"

# --- 3. live traffic ---------------------------------------------------------
code_for() {
  kubectl -n "$NS" exec deploy/tester -- \
    curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$1" 2>/dev/null
}

ok_code=$(code_for "http://httpbin.${OK_NS}:8000/get")
[[ "$ok_code" == "200" ]] \
  || fail "http://httpbin.${OK_NS}:8000/get returned '$ok_code', expected 200 - the namespace you were told to keep reachable is not"

local_code=$(code_for "http://local-backend:8000/get")
[[ "$local_code" == "200" ]] \
  || fail "http://local-backend:8000/get returned '$local_code', expected 200 - the proxy's own namespace must stay reachable"

deny_code=$(code_for "http://httpbin.${DENY_NS}:8000/get")
if [[ "$deny_code" == "200" ]]; then
  fail "http://httpbin.${DENY_NS}:8000/get still returns 200 - $DENY_NS was not scoped out"
fi

echo "PASS: namespace-wide Sidecar scopes $NS to './*', 'istio-system/*' and '$OK_NS/*'; the proxy dropped to ${cluster_lines} cluster rows with no $DENY_NS entry; $OK_NS and the local namespace still answer 200 while $DENY_NS returns '$deny_code' with its workload still running"
exit 0
