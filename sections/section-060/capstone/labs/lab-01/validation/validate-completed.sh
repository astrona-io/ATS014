#!/usr/bin/env bash
# Section 060 capstone. Confirms all three ingress APIs serving three apps at
# once: native Gateway + VirtualService, a Kubernetes Ingress with TLS in the
# gateway namespace, and a Gateway API Gateway with its own separate proxy.

set -u

NS="edge"
PF_SHARED="" PF_TLS="" PF_MODERN=""

fail() { cleanup; echo "FAIL: $*"; exit 1; }
cleanup() {
  for p in "$PF_SHARED" "$PF_TLS" "$PF_MODERN"; do
    [[ -n "$p" ]] && kill "$p" 2>/dev/null
  done
}
trap cleanup EXIT

cond() {
  kubectl -n "$NS" get "$1" "$2" -o jsonpath="{range $3[?(@.type=='$4')]}{.status}{end}" 2>/dev/null
}

# --- 0. the environment is intact -------------------------------------------
for d in native-app legacy-app modern-app; do
  r=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$r" && "$r" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas"
done

# ============================ A: native Istio ===============================
kubectl -n "$NS" get gateway.networking.istio.io native-gw >/dev/null 2>&1 \
  || fail "Istio Gateway 'native-gw' not found in $NS (networking.istio.io/v1)"

sel=$(kubectl -n "$NS" get gateway.networking.istio.io native-gw \
  -o jsonpath='{.spec.selector.istio}' 2>/dev/null)
[[ "$sel" == "ingressgateway" ]] \
  || fail "native-gw selector istio='$sel', expected 'ingressgateway'"

nh=$(kubectl -n "$NS" get gateway.networking.istio.io native-gw \
  -o jsonpath='{.spec.servers[*].hosts[*]}' 2>/dev/null)
grep -qw 'native.ica.local' <<<"$nh" || fail "native-gw hosts are [$nh] - native.ica.local missing"

kubectl -n "$NS" get virtualservice native >/dev/null 2>&1 \
  || fail "VirtualService 'native' not found in $NS"
vgw=$(kubectl -n "$NS" get virtualservice native -o jsonpath='{.spec.gateways[*]}' 2>/dev/null)
[[ -n "$vgw" ]] \
  || fail "VirtualService 'native' has no 'gateways' field - without it the routes attach to 'mesh' and the gateway 404s"
grep -qE "(^| )(native-gw|${NS}/native-gw)( |$)" <<<"$vgw" \
  || fail "VirtualService 'native' binds to [$vgw], which does not name native-gw"

# ============================ B: Kubernetes Ingress =========================
kubectl get ingressclass istio >/dev/null 2>&1 || fail "IngressClass 'istio' not found"
ctrl=$(kubectl get ingressclass istio -o jsonpath='{.spec.controller}' 2>/dev/null)
[[ "$ctrl" == "istio.io/ingress-controller" ]] \
  || fail "IngressClass 'istio' controller is '$ctrl', expected istio.io/ingress-controller"

kubectl -n "$NS" get ingress legacy >/dev/null 2>&1 || fail "Ingress 'legacy' not found in $NS"
cls=$(kubectl -n "$NS" get ingress legacy -o jsonpath='{.spec.ingressClassName}' 2>/dev/null)
if [[ "$cls" != "istio" ]]; then
  ann=$(kubectl -n "$NS" get ingress legacy \
    -o jsonpath='{.metadata.annotations.kubernetes\.io/ingress\.class}' 2>/dev/null)
  [[ "$ann" == "istio" ]] || fail "the Ingress selects class '$cls' (annotation '$ann'), expected istio"
fi

pt=$(kubectl -n "$NS" get ingress legacy \
  -o jsonpath='{.spec.rules[0].http.paths[0].pathType}' 2>/dev/null)
[[ "$pt" == "Prefix" ]] || fail "the Ingress path has pathType '$pt', expected Prefix"

if ! kubectl -n istio-system get secret legacy-credential >/dev/null 2>&1; then
  if kubectl -n "$NS" get secret legacy-credential >/dev/null 2>&1; then
    fail "secret 'legacy-credential' is in $NS but not in istio-system. The GATEWAY pod loads the certificate and can only read secrets from its own namespace"
  fi
  fail "secret 'legacy-credential' not found in istio-system"
fi

# ============================ C: Gateway API ================================
kubectl -n "$NS" get gateway.gateway.networking.k8s.io modern-gw >/dev/null 2>&1 \
  || fail "Gateway API Gateway 'modern-gw' not found in $NS (gateway.networking.k8s.io/v1)"

gcn=$(kubectl -n "$NS" get gateway.gateway.networking.k8s.io modern-gw \
  -o jsonpath='{.spec.gatewayClassName}' 2>/dev/null)
[[ "$gcn" == "istio" ]] || fail "modern-gw gatewayClassName is '$gcn', expected istio"

kubectl -n "$NS" get deployment modern-gw-istio >/dev/null 2>&1 \
  || fail "Deployment 'modern-gw-istio' not found in $NS. A Gateway API Gateway CREATES its own proxy in its own namespace"
kubectl -n "$NS" get service modern-gw-istio >/dev/null 2>&1 \
  || fail "Service 'modern-gw-istio' not found in $NS"
mr=$(kubectl -n "$NS" get deployment modern-gw-istio -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ -n "$mr" && "$mr" -ge 1 ]] || fail "modern-gw-istio has no ready replicas"

acc=$(cond gateway.gateway.networking.k8s.io modern-gw '.status.conditions' Accepted)
prog=$(cond gateway.gateway.networking.k8s.io modern-gw '.status.conditions' Programmed)
[[ "$acc" == "True" ]]  || fail "modern-gw reports Accepted=$acc"
[[ "$prog" == "True" ]] || fail "modern-gw reports Programmed=$prog"

kubectl -n "$NS" get httproute modern >/dev/null 2>&1 || fail "HTTPRoute 'modern' not found in $NS"
ra=$(cond httproute modern '.status.parents[0].conditions' Accepted)
rr=$(cond httproute modern '.status.parents[0].conditions' ResolvedRefs)
[[ "$ra" == "True" ]] || fail "HTTPRoute 'modern' reports Accepted=$ra on its parent"
[[ "$rr" == "True" ]] || fail "HTTPRoute 'modern' reports ResolvedRefs=$rr - check the backend name and port"

# ============================ live traffic ==================================
# Pick a free local port instead of a fixed one, and wait for the forward to
# actually bind. A fixed port collides when two labs are graded at the same time
# on one machine, and every probe then returns 000 for reasons that have nothing
# to do with the student's configuration.
free_port() {
  python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
}
wait_bound() {
  local port="$1" i
  for i in $(seq 1 40); do
    if python3 -c "import socket,sys; s=socket.socket(); sys.exit(0 if s.connect_ex(('127.0.0.1',$port))==0 else 1)" 2>/dev/null; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

PF_HTTP_PORT=$(free_port)
PF_TLS_PORT=$(free_port)
PF_MODERN_PORT=$(free_port)
kubectl -n istio-system port-forward svc/istio-ingressgateway ${PF_HTTP_PORT}:80  >/dev/null 2>&1 & PF_SHARED=$!
kubectl -n istio-system port-forward svc/istio-ingressgateway ${PF_TLS_PORT}:443 >/dev/null 2>&1 & PF_TLS=$!
kubectl -n "$NS"        port-forward svc/modern-gw-istio      ${PF_MODERN_PORT}:80  >/dev/null 2>&1 & PF_MODERN=$!
sleep 6
wait_bound "${PF_HTTP_PORT}" || fail "the local port-forward to the gateway never came up"
wait_bound "${PF_TLS_PORT}" || fail "the local port-forward to the gateway never came up"
wait_bound "${PF_MODERN_PORT}" || fail "the local port-forward to the gateway never came up"

shared_http() { curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H "Host: $1" "http://localhost:${PF_HTTP_PORT}$2" 2>/dev/null; }
shared_https(){ curl -sk -o /dev/null -w '%{http_code}' --max-time 10 --resolve "$1:${PF_TLS_PORT}:127.0.0.1" "https://$1:${PF_TLS_PORT}$2" 2>/dev/null; }
modern_http() { curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H "Host: $1" "http://localhost:${PF_MODERN_PORT}$2" 2>/dev/null; }

# Retry while the three data planes come up. Each has to receive its route, and
# the TLS one also has to fetch and load its credential, before it answers.
wait_200() {
  local fn="$1" host="$2" path="$3" i code
  for i in $(seq 1 30); do
    code=$("$fn" "$host" "$path")
    [[ "$code" == "200" ]] && { echo "$code"; return; }
    sleep 2
  done
  echo "$code"
}

c=$(wait_200 shared_http native.ica.local /api)
[[ "$c" == "200" ]] \
  || fail "GET /api with Host native.ica.local through istio-ingressgateway returned '$c', expected 200"

c=$(wait_200 shared_https legacy.ica.local /api)
[[ "$c" == "200" ]] \
  || fail "GET /api with Host legacy.ica.local over HTTPS returned '$c', expected 200. A '000' means the HTTPS listener never came up - check the secret's namespace"

c=$(wait_200 modern_http modern.ica.local /api)
[[ "$c" == "200" ]] \
  || fail "GET /api with Host modern.ica.local through modern-gw-istio returned '$c', expected 200"

# the two data planes must be separate
c=$(shared_http modern.ica.local /api)
[[ "$c" == "200" ]] \
  && fail "modern.ica.local is served by istio-ingressgateway too. The Gateway API object has its own proxy; if the shared gateway also serves it, an extra native Gateway or Ingress is duplicating the route"

echo "PASS: three APIs serving three apps at once - native Gateway+VirtualService (native.ica.local, HTTP 200), Kubernetes Ingress with TLS from istio-system (legacy.ica.local, HTTPS 200), and a Gateway API Gateway with its own modern-gw-istio proxy in $NS (modern.ica.local, 200), with the two data planes correctly separate"
exit 0
