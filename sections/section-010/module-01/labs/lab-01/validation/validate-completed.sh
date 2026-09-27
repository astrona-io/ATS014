#!/usr/bin/env bash
# Confirms the DestinationRule defines v1/v2 over the version label, the
# VirtualService exists for the right host, the workloads were left alone, and
# - the part that actually matters - that live traffic proves every rule is
# reachable and the default did not swallow the specific cases.

set -u

NS="routing-demo"
SVC="notification-service"
V1='["EMAIL"]'
V2='["EMAIL","SMS"]'

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is still what the lab handed over -------------------
for d in notification-service-v1 notification-service-v2 tester; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS"
done

deploy_count=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$deploy_count" -eq 3 ]] || fail "$NS holds $deploy_count deployments, expected exactly 3 - do not add or remove workloads"

selector=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.selector}' 2>/dev/null)
[[ -n "$selector" ]] || fail "$SVC - service not found in $NS"
if grep -q 'version' <<<"$selector"; then
  fail "the $SVC Service selector is $selector - it must keep selecting on app only. Routing between versions is Istio's job, not the Service's"
fi

# --- 1. DestinationRule defines the subsets ---------------------------------
kubectl -n "$NS" get destinationrule "$SVC" >/dev/null 2>&1 \
  || fail "DestinationRule '$SVC' not found in $NS - without it no subset name resolves"

dr_host=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.host}' 2>/dev/null)
case "$dr_host" in
  "$SVC"|"$SVC.$NS"|"$SVC.$NS.svc"|"$SVC.$NS.svc.cluster.local") ;;
  *) fail "DestinationRule host is '$dr_host', expected $SVC (short or fully qualified)" ;;
esac

subset_names=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.subsets[*].name}' 2>/dev/null)
for s in v1 v2; do
  grep -qw "$s" <<<"$subset_names" || fail "DestinationRule subsets are [$subset_names] - subset '$s' is missing"
done

for s in v1 v2; do
  lbl=$(kubectl -n "$NS" get destinationrule "$SVC" \
    -o jsonpath="{.spec.subsets[?(@.name=='$s')].labels.version}" 2>/dev/null)
  [[ "$lbl" == "$s" ]] || fail "subset '$s' selects on version='$lbl', expected version='$s'"
done

# a subset whose labels match no pod is legal config and a silent 503 later
for s in v1 v2; do
  pods=$(kubectl -n "$NS" get pods -l "app=$SVC,version=$s" \
    --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')
  [[ "$pods" -ge 1 ]] || fail "subset '$s' selects no running pod - the labels do not match reality"
done

# --- 2. VirtualService exists for the right host ----------------------------
kubectl -n "$NS" get virtualservice "$SVC" >/dev/null 2>&1 \
  || fail "VirtualService '$SVC' not found in $NS"

vs_hosts=$(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{.spec.hosts[*]}' 2>/dev/null)
if ! grep -qE "(^| )$SVC(\.$NS(\.svc(\.cluster\.local)?)?)?( |$)" <<<"$vs_hosts"; then
  fail "VirtualService hosts are [$vs_hosts] - none of them name $SVC"
fi

rule_count=$(kubectl -n "$NS" get virtualservice "$SVC" -o jsonpath='{.spec.http[*]}' 2>/dev/null | grep -o 'route' | wc -l | tr -d ' ')
[[ "$rule_count" -ge 4 ]] || fail "the VirtualService has fewer than 4 http rules - three match rules plus a default are required"

# --- 3. the proxy actually received it --------------------------------------
if ! istioctl proxy-config routes "deploy/tester" -n "$NS" 2>/dev/null | grep -q "$SVC"; then
  fail "the tester proxy has no route for $SVC - the VirtualService exists but never reached the sidecar"
fi

# --- 4. live traffic: the part that proves rule ORDER ------------------------
curl_from_tester() {
  kubectl -n "$NS" exec deploy/tester -- curl -s --max-time 10 "$@" 2>/dev/null
}

# 4a. default traffic must reach v1 EVERY time (20 samples, not 1)
default_answers=$(kubectl -n "$NS" exec deploy/tester -- sh -c \
  'for i in $(seq 1 20); do curl -s --max-time 10 -X POST http://notification-service/notify; echo; done' 2>/dev/null | sort -u)
if [[ -z "$default_answers" ]]; then
  fail "no response to a default POST /notify - check that the route resolves to a subset with endpoints"
fi
if [[ "$default_answers" != "$V1" ]]; then
  fail "20 default requests returned [$(tr '\n' ' ' <<<"$default_answers")], expected only $V1. Either the default rule does not send to v1, or no default rule exists and traffic is still load balancing across both versions"
fi

# 4b. header rule
hdr=$(curl_from_tester -X POST -H "testing: true" http://notification-service/notify)
[[ "$hdr" == "$V2" ]] || fail "a request with header 'testing: true' returned '$hdr', expected $V2. If it returned $V1 the default rule is above the header rule and is swallowing it"

# 4c. URI prefix rule
uri=$(curl_from_tester -X POST http://notification-service/notify/beta)
[[ "$uri" == "$V2" ]] || fail "POST /notify/beta returned '$uri', expected $V2. If it returned $V1 the default rule is above the URI rule"

# 4d. query parameter rule
qry=$(curl_from_tester -X POST 'http://notification-service/notify?version=2')
[[ "$qry" == "$V2" ]] || fail "POST /notify?version=2 returned '$qry', expected $V2. If it returned $V1 the default rule is above the query rule, or the rule was written with uri instead of queryParams - the uri value stops at the '?'"

# 4e. a near-miss must NOT match: wrong header value falls through to v1
near=$(curl_from_tester -X POST -H "testing: yes" http://notification-service/notify)
[[ "$near" == "$V1" ]] || fail "a request with header 'testing: yes' returned '$near', expected $V1. The header rule must match the exact value 'true', not merely the presence of the header"

echo "PASS: subsets v1/v2 defined over the version label, header / URI-prefix / query rules all reach v2, a near-miss and all default traffic reach v1, and the rules are in an order that leaves every one of them reachable"
exit 0
