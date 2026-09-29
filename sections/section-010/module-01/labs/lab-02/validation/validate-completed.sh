#!/usr/bin/env bash
# Confirms the VirtualService reshapes requests as specified: a 301 for the
# legacy prefix that never reaches a pod, a prefix rewrite onto v2 that is
# present in the COMPILED route (no access log can show it), a stamped response
# header, a stripped request header, and CORS for exactly one origin - all
# proven with live traffic from the tester pod.

set -u

NS="routing-demo"
SVC="notification-service"
V1='["EMAIL"]'
V2='["EMAIL","SMS"]'
ORIGIN="https://shop.example.com"

fail() { echo "FAIL: $*"; exit 1; }
curl_t() { kubectl -n "$NS" exec deploy/tester -- curl -s "$@"; }

# --- 0. the environment is still what the lab handed over -------------------
for d in notification-service-v1 notification-service-v2 tester; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS"
done

deploy_count=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$deploy_count" -eq 3 ]] || fail "$NS holds $deploy_count deployments, expected exactly 3 - do not add or remove workloads"

selector=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.selector}' 2>/dev/null)
[[ -n "$selector" ]] || fail "$SVC - service not found in $NS"
grep -q 'version' <<<"$selector" && \
  fail "the $SVC Service selector is $selector - it must keep selecting on app only"

# --- 1. subsets exist and select real pods ----------------------------------
kubectl -n "$NS" get destinationrule "$SVC" >/dev/null 2>&1 \
  || fail "DestinationRule '$SVC' not found in $NS - without it subset 'v2' does not resolve"

subset_names=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.subsets[*].name}' 2>/dev/null)
for s in v1 v2; do
  grep -qw "$s" <<<"$subset_names" || fail "DestinationRule subsets are [$subset_names] - subset '$s' is missing"
  lbl=$(kubectl -n "$NS" get destinationrule "$SVC" \
    -o jsonpath="{.spec.subsets[?(@.name=='$s')].labels.version}" 2>/dev/null)
  [[ "$lbl" == "$s" ]] || fail "subset '$s' selects on version='$lbl', expected version='$s'"
  pods=$(kubectl -n "$NS" get pods -l "app=$SVC,version=$s" \
    --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')
  [[ "$pods" -ge 1 ]] || fail "subset '$s' selects no running pod - the labels do not match reality"
done

kubectl -n "$NS" get virtualservice "$SVC" >/dev/null 2>&1 \
  || fail "VirtualService '$SVC' not found in $NS"

# --- 2. /legacy is redirected, not routed -----------------------------------
code=$(curl_t -o /dev/null -w '%{http_code}' "http://$SVC/legacy/anything")
[[ "$code" == "301" ]] || fail "GET /legacy/anything returned $code, expected 301 - a redirect rule must answer it"

loc=$(curl_t -o /dev/null -w '%{redirect_url}' "http://$SVC/legacy/anything")
grep -q '/notify' <<<"$loc" || fail "the redirect sent Location '$loc', expected it to point at /notify"

# nothing may reach a pod for a redirected request
before=$(kubectl -n "$NS" logs -l "app=$SVC" -c istio-proxy --tail=-1 2>/dev/null | grep -c '/legacy')
curl_t -o /dev/null "http://$SVC/legacy/anything" >/dev/null 2>&1
sleep 2
after=$(kubectl -n "$NS" logs -l "app=$SVC" -c istio-proxy --tail=-1 2>/dev/null | grep -c '/legacy')
[[ "$after" -eq "$before" ]] \
  || fail "a /legacy request reached a backend pod - a redirect must be answered by the proxy, never forwarded"

# --- 3. /beta is rewritten, and lands on v2 ---------------------------------
body=$(curl_t "http://$SVC/beta/notify")
[[ "$body" == "$V2" ]] || fail "GET /beta/notify answered $body, expected $V2 - the /beta rule must route to subset v2"

# the rewrite is invisible in access logs by design; the compiled route is the proof
routes=$(istioctl proxy-config routes deploy/tester -n "$NS" -o json 2>/dev/null)
[[ -n "$routes" ]] || fail "could not read the tester proxy's route configuration"
grep -q 'prefixRewrite' <<<"$routes" \
  || fail "no prefixRewrite in the tester's compiled routes - the /beta rule is routing but not rewriting"
rewrite_val=$(grep -o '"prefixRewrite": *"[^"]*"' <<<"$routes" | head -1 | sed 's/.*: *"//;s/"//')
[[ "$rewrite_val" == "/" ]] \
  || fail "prefixRewrite is '$rewrite_val', expected '/' so that /beta/notify becomes /notify"

# --- 4. default traffic still reaches v1 ------------------------------------
for _ in 1 2 3 4 5; do
  body=$(curl_t -X POST "http://$SVC/notify")
  [[ "$body" == "$V1" ]] || fail "an ordinary POST /notify answered $body, expected $V1 - the default rule must route to v1"
done

# --- 5. the response header is stamped --------------------------------------
hdrs=$(curl_t -D - -o /dev/null -X POST "http://$SVC/notify")
grep -qi '^x-served-by:[[:space:]]*notification' <<<"$hdrs" \
  || fail "response to POST /notify carries no 'x-served-by: notification' header"

hdrs_beta=$(curl_t -D - -o /dev/null "http://$SVC/beta/notify")
grep -qi '^x-served-by:[[:space:]]*notification' <<<"$hdrs_beta" \
  || fail "the /beta route does not stamp 'x-served-by' - the header applies to every response leaving this service"

# --- 6. the internal request header is stripped -----------------------------
grep -q '"x-internal-token"' <<<"$routes" \
  || fail "no request-header removal of 'x-internal-token' in the compiled routes"

# --- 7. CORS for exactly one origin -----------------------------------------
cors=$(curl_t -D - -o /dev/null -H "Origin: $ORIGIN" -X POST "http://$SVC/notify")
grep -qi "^access-control-allow-origin:[[:space:]]*$ORIGIN" <<<"$cors" \
  || fail "a request from Origin $ORIGIN got no matching access-control-allow-origin header"

other=$(curl_t -D - -o /dev/null -H "Origin: https://evil.example.com" -X POST "http://$SVC/notify")
grep -qi '^access-control-allow-origin:' <<<"$other" \
  && fail "an unlisted origin received an access-control-allow-origin header - allowOrigins must match exactly one origin"

echo "PASS: redirect, rewrite onto v2, response header, header removal and CORS all verified with live traffic"
