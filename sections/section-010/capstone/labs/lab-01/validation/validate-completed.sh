#!/usr/bin/env bash
# Section 010 capstone. Confirms the routing half (subsets, three match rules,
# a reachable default, a near-miss falling through) and the scoping half (a
# namespace-wide Sidecar keeping the local namespace, istio-system and partners
# while archive leaves the config and becomes unreachable) both hold at once,
# with every workload left intact.

set -u

NS="storefront"
SVC="catalog"
OK_NS="partners"
DENY_NS="archive"
V1='["EMAIL"]'
V2='["EMAIL","SMS"]'

fail() { echo "FAIL: $*"; exit 1; }

curl_shopper() {
  kubectl -n "$NS" exec deploy/shopper -- curl -s --max-time 10 "$@" 2>/dev/null
}
code_shopper() {
  kubectl -n "$NS" exec deploy/shopper -- \
    curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$1" 2>/dev/null
}

# --- 0. the environment is intact -------------------------------------------
check_ready() {
  local ns="$1" d="$2" r
  r=$(kubectl -n "$ns" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$r" && "$r" -ge 1 ]] || fail "$ns/$d - deployment missing or has no ready replicas"
}
check_ready "$NS" catalog-v1
check_ready "$NS" catalog-v2
check_ready "$NS" shopper
check_ready "$OK_NS" pricing
check_ready "$DENY_NS" coldstore

dcount=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$dcount" -eq 3 ]] || fail "$NS holds $dcount deployments, expected exactly 3"

selector=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.selector}' 2>/dev/null)
[[ -n "$selector" ]] || fail "$SVC service not found in $NS"
grep -q 'version' <<<"$selector" \
  && fail "the $SVC Service selector is $selector - it must keep selecting on app only"

# --- 1. routing: subsets -----------------------------------------------------
kubectl -n "$NS" get destinationrule "$SVC" >/dev/null 2>&1 \
  || fail "DestinationRule '$SVC' not found in $NS"

for s in v1 v2; do
  lbl=$(kubectl -n "$NS" get destinationrule "$SVC" \
    -o jsonpath="{.spec.subsets[?(@.name=='$s')].labels.version}" 2>/dev/null)
  [[ "$lbl" == "$s" ]] || fail "subset '$s' selects on version='$lbl', expected version='$s'"
  pods=$(kubectl -n "$NS" get pods -l "app=$SVC,version=$s" \
    --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')
  [[ "$pods" -ge 1 ]] || fail "subset '$s' selects no running pod"
done

kubectl -n "$NS" get virtualservice "$SVC" >/dev/null 2>&1 \
  || fail "VirtualService '$SVC' not found in $NS"

# --- 2. routing: live traffic proves order -----------------------------------
defaults=$(kubectl -n "$NS" exec deploy/shopper -- sh -c \
  'for i in $(seq 1 20); do curl -s --max-time 10 -X POST http://catalog:8000/notify; echo; done' 2>/dev/null | sort -u)
[[ -n "$defaults" ]] || fail "no response to a default POST /notify - check the route resolves to a subset with endpoints"
[[ "$defaults" == "$V1" ]] \
  || fail "20 default requests returned [$(tr '\n' ' ' <<<"$defaults")], expected only $V1. Either the default rule does not send to v1, or there is no default rule and traffic still load balances across both versions"

hdr=$(curl_shopper -X POST -H "x-channel: mobile" http://catalog:8000/notify)
[[ "$hdr" == "$V2" ]] \
  || fail "header 'x-channel: mobile' returned '$hdr', expected $V2. If it returned $V1 the default rule sits above the header rule"

uri=$(curl_shopper -X POST http://catalog:8000/notify/preview)
[[ "$uri" == "$V2" ]] \
  || fail "POST /notify/preview returned '$uri', expected $V2. If it returned $V1 the default rule sits above the URI rule"

qry=$(curl_shopper -X POST 'http://catalog:8000/notify?beta=1')
[[ "$qry" == "$V2" ]] \
  || fail "POST /notify?beta=1 returned '$qry', expected $V2. If it returned $V1 the default rule sits above the query rule, or the rule used uri instead of queryParams - the uri value stops at the '?'"

near=$(curl_shopper -X POST -H "x-channel: web" http://catalog:8000/notify)
[[ "$near" == "$V1" ]] \
  || fail "header 'x-channel: web' returned '$near', expected $V1. The header rule must match the value 'mobile', not merely the presence of the header"

# --- 3. scoping: the Sidecar object ------------------------------------------
kubectl -n "$NS" get sidecar default >/dev/null 2>&1 \
  || fail "Sidecar 'default' not found in $NS"

sel=$(kubectl -n "$NS" get sidecar default -o jsonpath='{.spec.workloadSelector}' 2>/dev/null)
[[ -z "$sel" || "$sel" == "{}" ]] \
  || fail "Sidecar 'default' has a workloadSelector ($sel) - it must apply to the whole namespace"

sc=$(kubectl -n "$NS" get sidecar -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$sc" -eq 1 ]] || fail "$NS holds $sc Sidecar resources, expected exactly 1"

hosts=$(kubectl -n "$NS" get sidecar default -o jsonpath='{.spec.egress[*].hosts[*]}' 2>/dev/null)
[[ -n "$hosts" ]] || fail "Sidecar 'default' has no egress hosts"

own=0; istio=0; ok=0
for h in $hosts; do
  case "$h" in
    "./*"|"$NS/*")                 own=1 ;;
    "istio-system/*")              istio=1 ;;
    "$OK_NS/*"|"$OK_NS/pricing"*)  ok=1 ;;
    "*/*")   fail "egress hosts include '*/*', which is the unscoped default written down" ;;
    "$DENY_NS/"*) fail "egress hosts include a $DENY_NS entry - that namespace must be scoped out" ;;
  esac
done
[[ "$own"   -eq 1 ]] || fail "egress hosts are [$hosts] - the proxy's own namespace is missing. Without './*' the catalog routing you just built cannot work"
[[ "$istio" -eq 1 ]] || fail "egress hosts are [$hosts] - 'istio-system/*' is missing"
[[ "$ok"    -eq 1 ]] || fail "egress hosts are [$hosts] - '$OK_NS/*' is missing"

# --- 4. scoping: the proxy received it ---------------------------------------
clusters=$(istioctl proxy-config cluster deploy/shopper -n "$NS" 2>/dev/null)
[[ -n "$clusters" ]] || fail "could not read the shopper proxy's cluster config"

grep -q "$DENY_NS" <<<"$clusters" \
  && fail "the shopper proxy still holds clusters for $DENY_NS - the scoping did not take effect"
grep -q "$OK_NS" <<<"$clusters" \
  || fail "the shopper proxy has no cluster for $OK_NS - it was scoped out along with $DENY_NS"
grep -q "$SVC" <<<"$clusters" \
  || fail "the shopper proxy has no cluster for $SVC in its own namespace - './*' is missing"

# --- 5. scoping: live reachability -------------------------------------------
ok_code=$(code_shopper "http://pricing.${OK_NS}:8000/get")
[[ "$ok_code" == "200" ]] \
  || fail "http://pricing.${OK_NS}:8000/get returned '$ok_code', expected 200"

deny_code=$(code_shopper "http://coldstore.${DENY_NS}:8000/get")
[[ "$deny_code" == "200" ]] \
  && fail "http://coldstore.${DENY_NS}:8000/get still returns 200 - $DENY_NS was not scoped out"

echo "PASS: catalog subsets defined over the version label; header, URI-prefix and query rules all reach v2 with a near-miss and all default traffic on v1; a namespace-wide Sidecar keeps './*', 'istio-system/*' and '$OK_NS/*'; $OK_NS answers 200 while $DENY_NS returns '$deny_code' with coldstore still running"
exit 0
