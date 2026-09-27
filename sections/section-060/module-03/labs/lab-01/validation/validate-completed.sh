#!/usr/bin/env bash
# Confirms a Gateway API Gateway creates its own proxy in its own namespace,
# that allowedRoutes uses a Selector permitting a labelled namespace, that both
# HTTPRoutes (one of them cross-namespace) report Accepted and ResolvedRefs,
# and that live traffic reaches both backends through the new gateway.

set -u

GWNS="gwapi-demo"
TEAMNS="gwapi-team"
GW="shared-gateway"
PF=""

fail() { [[ -n "$PF" ]] && kill "$PF" 2>/dev/null; echo "FAIL: $*"; exit 1; }
cleanup() { [[ -n "$PF" ]] && kill "$PF" 2>/dev/null; }
trap cleanup EXIT

cond() {  # cond <ns> <kind> <name> <jsonpath-to-conditions> <type>
  kubectl -n "$1" get "$2" "$3" \
    -o jsonpath="{range $4[?(@.type=='$5')]}{.status}{end}" 2>/dev/null
}

# --- 0. the environment is intact -------------------------------------------
kubectl -n "$GWNS" get deployment booking-service-v1 >/dev/null 2>&1 \
  || fail "booking-service-v1 not found in $GWNS"
kubectl -n "$TEAMNS" get deployment catalog-service-v1 >/dev/null 2>&1 \
  || fail "catalog-service-v1 not found in $TEAMNS"
kubectl get gatewayclass istio >/dev/null 2>&1 \
  || fail "GatewayClass 'istio' not found - the Gateway API CRDs or Istio's controller registration is missing"

# --- 1. the Gateway ----------------------------------------------------------
kubectl -n "$GWNS" get gateway "$GW" >/dev/null 2>&1 \
  || fail "Gateway '$GW' not found in $GWNS"

gcn=$(kubectl -n "$GWNS" get gateway "$GW" -o jsonpath='{.spec.gatewayClassName}' 2>/dev/null)
[[ "$gcn" == "istio" ]] || fail "the Gateway's gatewayClassName is '$gcn', expected istio"

lname=$(kubectl -n "$GWNS" get gateway "$GW" -o jsonpath='{.spec.listeners[0].name}' 2>/dev/null)
lport=$(kubectl -n "$GWNS" get gateway "$GW" -o jsonpath='{.spec.listeners[0].port}' 2>/dev/null)
lproto=$(kubectl -n "$GWNS" get gateway "$GW" -o jsonpath='{.spec.listeners[0].protocol}' 2>/dev/null)
lhost=$(kubectl -n "$GWNS" get gateway "$GW" -o jsonpath='{.spec.listeners[0].hostname}' 2>/dev/null)
[[ "$lname" == "http" ]]  || fail "the listener name is '$lname', expected http"
[[ "$lport" == "80" ]]    || fail "the listener port is '$lport', expected 80"
[[ "$lproto" == "HTTP" ]] || fail "the listener protocol is '$lproto', expected HTTP"
[[ -z "$lhost" ]] \
  || fail "the listener sets hostname '$lhost'. The task asks for no hostname, so the listener accepts any host and the routes decide"

from=$(kubectl -n "$GWNS" get gateway "$GW" \
  -o jsonpath='{.spec.listeners[0].allowedRoutes.namespaces.from}' 2>/dev/null)
[[ "$from" == "Selector" ]] \
  || fail "allowedRoutes.namespaces.from is '$from', expected Selector. 'All' would work but is not a deliberate grant; 'Same' would block the cross-namespace route entirely"

sellbl=$(kubectl -n "$GWNS" get gateway "$GW" \
  -o jsonpath='{.spec.listeners[0].allowedRoutes.namespaces.selector.matchLabels.gateway-access}' 2>/dev/null)
[[ "$sellbl" == "true" ]] \
  || fail "the allowedRoutes selector does not match label gateway-access=\"true\" (found '$sellbl')"

# --- 2. the namespace is labelled -------------------------------------------
nslbl=$(kubectl get namespace "$TEAMNS" -o jsonpath='{.metadata.labels.gateway-access}' 2>/dev/null)
[[ "$nslbl" == "true" ]] \
  || fail "namespace $TEAMNS has gateway-access='$nslbl', expected 'true'. Without the label the selector does not match and its route cannot attach"

# --- 3. the Gateway created its own data plane ------------------------------
kubectl -n "$GWNS" get deployment "${GW}-istio" >/dev/null 2>&1 \
  || fail "Deployment ${GW}-istio not found in $GWNS. A Gateway API Gateway CREATES its own proxy in its own namespace - it does not configure istio-ingressgateway"
kubectl -n "$GWNS" get service "${GW}-istio" >/dev/null 2>&1 \
  || fail "Service ${GW}-istio not found in $GWNS"

ready=$(kubectl -n "$GWNS" get deployment "${GW}-istio" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ -n "$ready" && "$ready" -ge 1 ]] || fail "${GW}-istio has no ready replicas"

# --- 4. Gateway conditions ---------------------------------------------------
acc=$(cond "$GWNS" gateway "$GW" '.status.conditions' Accepted)
prog=$(cond "$GWNS" gateway "$GW" '.status.conditions' Programmed)
[[ "$acc" == "True" ]]  || fail "the Gateway reports Accepted=$acc. Run 'kubectl -n $GWNS describe gateway $GW' - the condition message names the problem"
[[ "$prog" == "True" ]] || fail "the Gateway reports Programmed=$prog. Accepted without Programmed means the YAML is fine but the proxy is not up"

# --- 5. both HTTPRoutes attached --------------------------------------------
check_route() {
  local ns="$1" name="$2" host="$3" prefix="$4" backend="$5"
  kubectl -n "$ns" get httproute "$name" >/dev/null 2>&1 \
    || fail "HTTPRoute '$name' not found in $ns"

  local hn pr bn a r
  hn=$(kubectl -n "$ns" get httproute "$name" -o jsonpath='{.spec.hostnames[*]}' 2>/dev/null)
  grep -qw "$host" <<<"$hn" || fail "HTTPRoute $ns/$name hostnames are [$hn] - '$host' is missing"

  pr=$(kubectl -n "$ns" get httproute "$name" -o jsonpath='{.spec.parentRefs[0].name}' 2>/dev/null)
  [[ "$pr" == "$GW" ]] || fail "HTTPRoute $ns/$name parentRefs[0].name is '$pr', expected $GW"

  bn=$(kubectl -n "$ns" get httproute "$name" -o jsonpath='{.spec.rules[0].backendRefs[0].name}' 2>/dev/null)
  [[ "$bn" == "$backend" ]] || fail "HTTPRoute $ns/$name backendRefs[0].name is '$bn', expected $backend"

  a=$(cond "$ns" httproute "$name" '.status.parents[0].conditions' Accepted)
  r=$(cond "$ns" httproute "$name" '.status.parents[0].conditions' ResolvedRefs)
  [[ "$a" == "True" ]] \
    || fail "HTTPRoute $ns/$name reports Accepted=$a on its parent. For the cross-namespace route this means the Gateway's allowedRoutes does not permit $ns - check the selector and the namespace label"
  [[ "$r" == "True" ]] \
    || fail "HTTPRoute $ns/$name reports ResolvedRefs=$r - a backendRefs target could not be found"
}
check_route "$GWNS"  booking booking.ica.local /book  booking-service
check_route "$TEAMNS" catalog catalog.ica.local /items catalog-service

# the cross-namespace route must name the Gateway's namespace
prns=$(kubectl -n "$TEAMNS" get httproute catalog -o jsonpath='{.spec.parentRefs[0].namespace}' 2>/dev/null)
[[ "$prns" == "$GWNS" ]] \
  || fail "the catalog HTTPRoute's parentRefs[0].namespace is '$prns', expected $GWNS. A cross-namespace parentRef must name the Gateway's namespace"

# --- 6. live traffic through the NEW gateway --------------------------------
kubectl -n "$GWNS" port-forward "svc/${GW}-istio" 18080:80 >/dev/null 2>&1 &
PF=$!
sleep 5

code_for() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H "Host: $1" "http://localhost:18080$2" 2>/dev/null
}

c=$(code_for booking.ica.local /book)
[[ "$c" == "200" ]] || fail "GET /book with Host booking.ica.local returned '$c', expected 200"

c=$(code_for catalog.ica.local /items)
[[ "$c" == "200" ]] \
  || fail "GET /items with Host catalog.ica.local returned '$c', expected 200. The cross-namespace route is attached but traffic is not reaching $TEAMNS/catalog-service"

echo "PASS: Gateway '$GW' created ${GW}-istio in $GWNS and reports Accepted/Programmed; a Selector-based allowedRoutes let the labelled $TEAMNS namespace attach; both HTTPRoutes report Accepted and ResolvedRefs, and both hosts return 200 through the new proxy"
exit 0
