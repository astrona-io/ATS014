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
kubectl -n istio-system port-forward svc/istio-ingressgateway 18080:80  >/dev/null 2>&1 & PF_SHARED=$!
kubectl -n istio-system port-forward svc/istio-ingressgateway 18443:443 >/dev/null 2>&1 & PF_TLS=$!
kubectl -n "$NS"        port-forward svc/modern-gw-istio      18081:80  >/dev/null 2>&1 & PF_MODERN=$!
sleep 6

shared_http() { curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H "Host: $1" "http://localhost:18080$2" 2>/dev/null; }
shared_https(){ curl -sk -o /dev/null -w '%{http_code}' --max-time 10 --resolve "$1:18443:127.0.0.1" "https://$1:18443$2" 2>/dev/null; }
modern_http() { curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H "Host: $1" "http://localhost:18081$2" 2>/dev/null; }

c=$(shared_http native.ica.local /api)
[[ "$c" == "200" ]] \
  || fail "GET /api with Host native.ica.local through istio-ingressgateway returned '$c', expected 200"

c=$(shared_https legacy.ica.local /api)
[[ "$c" == "200" ]] \
  || fail "GET /api with Host legacy.ica.local over HTTPS returned '$c', expected 200. A '000' means the HTTPS listener never came up - check the secret's namespace"

c=$(modern_http modern.ica.local /api)
[[ "$c" == "200" ]] \
  || fail "GET /api with Host modern.ica.local through modern-gw-istio returned '$c', expected 200"

# the two data planes must be separate
c=$(shared_http modern.ica.local /api)
[[ "$c" == "200" ]] \
  && fail "modern.ica.local is served by istio-ingressgateway too. The Gateway API object has its own proxy; if the shared gateway also serves it, an extra native Gateway or Ingress is duplicating the route"

echo "PASS: three APIs serving three apps at once - native Gateway+VirtualService (native.ica.local, HTTP 200), Kubernetes Ingress with TLS from istio-system (legacy.ica.local, HTTPS 200), and a Gateway API Gateway with its own modern-gw-istio proxy in $NS (modern.ica.local, 200), with the two data planes correctly separate"
exit 0
