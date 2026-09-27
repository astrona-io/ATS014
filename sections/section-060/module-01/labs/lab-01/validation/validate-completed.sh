#!/usr/bin/env bash
# Confirms one Gateway opens an HTTP listener for exactly two hosts, that two
# VirtualServices are BOUND to it and route by host, that the gateway proxy
# really holds both routes, and that unknown or crossed hosts are rejected.

set -u

NS="ingress-demo"
GW="public-gateway"
PF_PID=""

fail() { [[ -n "$PF_PID" ]] && kill "$PF_PID" 2>/dev/null; echo "FAIL: $*"; exit 1; }
cleanup() { [[ -n "$PF_PID" ]] && kill "$PF_PID" 2>/dev/null; }
trap cleanup EXIT

# --- 0. the environment is intact -------------------------------------------
for d in booking-service-v1 catalog-service-v1; do
  r=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$r" && "$r" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas"
done
gwr=$(kubectl -n istio-system get deployment istio-ingressgateway -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ -n "$gwr" && "$gwr" -ge 1 ]] || fail "istio-ingressgateway is not ready in istio-system"

# --- 1. the Gateway ----------------------------------------------------------
kubectl -n "$NS" get gateway "$GW" >/dev/null 2>&1 \
  || fail "Gateway '$GW' not found in $NS"

sel=$(kubectl -n "$NS" get gateway "$GW" -o jsonpath='{.spec.selector.istio}' 2>/dev/null)
[[ "$sel" == "ingressgateway" ]] \
  || fail "the Gateway selector istio='$sel', expected 'ingressgateway'. The selector is a POD label selector and must match the running gateway"

port=$(kubectl -n "$NS" get gateway "$GW" -o jsonpath='{.spec.servers[0].port.number}' 2>/dev/null)
proto=$(kubectl -n "$NS" get gateway "$GW" -o jsonpath='{.spec.servers[0].port.protocol}' 2>/dev/null)
[[ "$port" == "80" ]]    || fail "the Gateway server port is '$port', expected 80"
[[ "$proto" == "HTTP" ]] || fail "the Gateway server protocol is '$proto', expected HTTP. TCP would give you a byte pipe with no host routing"

hosts=$(kubectl -n "$NS" get gateway "$GW" -o jsonpath='{.spec.servers[*].hosts[*]}' 2>/dev/null)
for h in booking.ica.local catalog.ica.local; do
  grep -qw "$h" <<<"$hosts" || fail "the Gateway hosts are [$hosts] - '$h' is missing"
done
grep -qE '(^| )\*( |$)' <<<"$hosts" \
  && fail "the Gateway hosts include '*'. The listener must accept only the two named hosts, so an unknown host is rejected"

# --- 2. both VirtualServices are BOUND --------------------------------------
check_vs() {
  local name="$1" host="$2" prefix="$3" dest="$4"
  kubectl -n "$NS" get virtualservice "$name" >/dev/null 2>&1 \
    || fail "VirtualService '$name' not found in $NS"

  local vh gws pfx dh
  vh=$(kubectl -n "$NS" get virtualservice "$name" -o jsonpath='{.spec.hosts[*]}' 2>/dev/null)
  grep -qw "$host" <<<"$vh" || fail "VirtualService '$name' hosts are [$vh] - '$host' is missing"

  gws=$(kubectl -n "$NS" get virtualservice "$name" -o jsonpath='{.spec.gateways[*]}' 2>/dev/null)
  [[ -n "$gws" ]] \
    || fail "VirtualService '$name' has no 'gateways' field. Without it the routes attach to 'mesh' - sidecars only - and the gateway keeps returning 404"
  grep -qE "(^| )($GW|${NS}/$GW)( |$)" <<<"$gws" \
    || fail "VirtualService '$name' binds to gateways [$gws], which does not name $GW"

  pfx=$(kubectl -n "$NS" get virtualservice "$name" -o jsonpath='{.spec.http[0].match[0].uri.prefix}' 2>/dev/null)
  [[ "$pfx" == "$prefix" ]] || fail "VirtualService '$name' matches uri prefix '$pfx', expected '$prefix'"

  dh=$(kubectl -n "$NS" get virtualservice "$name" -o jsonpath='{.spec.http[0].route[0].destination.host}' 2>/dev/null)
  case "$dh" in
    "$dest"|"$dest.$NS"|"$dest.$NS.svc"|"$dest.$NS.svc.cluster.local") ;;
    *) fail "VirtualService '$name' routes to host '$dh', expected $dest" ;;
  esac
}
check_vs booking booking.ica.local /book  booking-service
check_vs catalog catalog.ica.local /items catalog-service

# --- 3. the gateway proxy really holds both routes --------------------------
routes=$(istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system 2>/dev/null)
[[ -n "$routes" ]] || fail "could not read the ingress gateway's route config"
for h in booking.ica.local catalog.ica.local; do
  grep -q "$h" <<<"$routes" \
    || fail "host '$h' does not appear in the gateway's route table. The VirtualService exists but never attached - check its 'gateways' field and that its hosts overlap the Gateway's"
done

# --- 4. live traffic through a port-forward ---------------------------------
kubectl -n istio-system port-forward svc/istio-ingressgateway 18080:80 >/dev/null 2>&1 &
PF_PID=$!
sleep 4

code_for() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H "Host: $1" "http://localhost:18080$2" 2>/dev/null
}

c=$(code_for booking.ica.local /book)
[[ "$c" == "200" ]] || fail "GET /book with Host booking.ica.local returned '$c', expected 200"

c=$(code_for catalog.ica.local /items)
[[ "$c" == "200" ]] || fail "GET /items with Host catalog.ica.local returned '$c', expected 200"

c=$(code_for unknown.ica.local /book)
[[ "$c" == "200" ]] \
  && fail "GET /book with Host unknown.ica.local returned 200. The listener must accept only the two named hosts - check that the Gateway hosts do not include '*'"

c=$(code_for catalog.ica.local /book)
[[ "$c" == "200" ]] \
  && fail "GET /book with Host catalog.ica.local returned 200. Each host must carry only its own routes"

echo "PASS: Gateway '$GW' opens an HTTP/80 listener for booking.ica.local and catalog.ica.local only; both VirtualServices are bound to it and appear in the gateway's route table; each host serves its own path with 200 while an unknown host and a crossed host are rejected"
exit 0
