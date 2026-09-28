#!/usr/bin/env bash
# Confirms an istio IngressClass with the right controller, an Ingress claimed
# by it serving two path types, the TLS secret in the GATEWAY namespace with
# HTTPS working, element-wise Prefix semantics, and no native Istio objects.

set -u

NS="k8s-ingress-demo"
PF_HTTP="" PF_TLS=""

fail() { cleanup; echo "FAIL: $*"; exit 1; }
cleanup() {
  [[ -n "$PF_HTTP" ]] && kill "$PF_HTTP" 2>/dev/null
  [[ -n "$PF_TLS"  ]] && kill "$PF_TLS"  2>/dev/null
}
trap cleanup EXIT

# --- 0. the environment is intact -------------------------------------------
r=$(kubectl -n "$NS" get deployment booking-service-v1 -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ -n "$r" && "$r" -ge 1 ]] || fail "booking-service-v1 - deployment missing or has no ready replicas"
gwr=$(kubectl -n istio-system get deployment istio-ingressgateway -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ -n "$gwr" && "$gwr" -ge 1 ]] || fail "istio-ingressgateway is not ready"

# --- 1. no native Istio objects ---------------------------------------------
for kind in gateway virtualservice; do
  if kubectl -n "$NS" get "$kind" -o name 2>/dev/null | grep -q .; then
    fail "a $kind exists in $NS. This task must be solved with the plain Kubernetes Ingress API only"
  fi
done

# --- 2. the IngressClass -----------------------------------------------------
kubectl get ingressclass istio >/dev/null 2>&1 \
  || fail "IngressClass 'istio' not found. It is cluster-scoped and must exist before an Ingress can select it"

ctrl=$(kubectl get ingressclass istio -o jsonpath='{.spec.controller}' 2>/dev/null)
[[ "$ctrl" == "istio.io/ingress-controller" ]] \
  || fail "IngressClass 'istio' has controller '$ctrl', expected istio.io/ingress-controller. With the wrong string the class exists and nothing implements it"

# --- 3. the Ingress is claimed ----------------------------------------------
kubectl -n "$NS" get ingress booking >/dev/null 2>&1 \
  || fail "Ingress 'booking' not found in $NS"

cls=$(kubectl -n "$NS" get ingress booking -o jsonpath='{.spec.ingressClassName}' 2>/dev/null)
if [[ "$cls" != "istio" ]]; then
  ann=$(kubectl -n "$NS" get ingress booking \
    -o jsonpath='{.metadata.annotations.kubernetes\.io/ingress\.class}' 2>/dev/null)
  [[ "$ann" == "istio" ]] \
    || fail "the Ingress selects class '$cls' (annotation '$ann'), expected istio. An unclaimed Ingress is a valid object that nothing serves"
fi

host=$(kubectl -n "$NS" get ingress booking -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)
[[ "$host" == "booking.ica.local" ]] || fail "the Ingress rule host is '$host', expected booking.ica.local"

# path types
pt_book=$(kubectl -n "$NS" get ingress booking \
  -o jsonpath='{.spec.rules[0].http.paths[?(@.path=="/book")].pathType}' 2>/dev/null)
pt_exact=$(kubectl -n "$NS" get ingress booking \
  -o jsonpath='{.spec.rules[0].http.paths[?(@.path=="/status/200")].pathType}' 2>/dev/null)
[[ "$pt_book" == "Prefix" ]] \
  || fail "the /book path has pathType '$pt_book', expected Prefix"
[[ "$pt_exact" == "Exact" ]] \
  || fail "the /status/200 path has pathType '$pt_exact', expected Exact"

# --- 4. the TLS secret is in the GATEWAY namespace --------------------------
sec=$(kubectl -n "$NS" get ingress booking -o jsonpath='{.spec.tls[0].secretName}' 2>/dev/null)
[[ "$sec" == "booking-credential" ]] \
  || fail "the Ingress tls secretName is '$sec', expected booking-credential"

if ! kubectl -n istio-system get secret booking-credential >/dev/null 2>&1; then
  if kubectl -n "$NS" get secret booking-credential >/dev/null 2>&1; then
    fail "the secret 'booking-credential' is in $NS but not in istio-system. The GATEWAY pod loads the certificate, and a pod can only read secrets from its own namespace - HTTP keeps working while HTTPS silently never comes up"
  fi
  fail "secret 'booking-credential' not found in istio-system"
fi

stype=$(kubectl -n istio-system get secret booking-credential -o jsonpath='{.type}' 2>/dev/null)
[[ "$stype" == "kubernetes.io/tls" ]] \
  || fail "secret booking-credential is of type '$stype', expected kubernetes.io/tls. Create it with 'kubectl create secret tls'"

# --- 5. the route reached the gateway ---------------------------------------
routes=$(istioctl proxy-config routes deploy/istio-ingressgateway -n istio-system 2>/dev/null)
grep -q 'booking.ica.local' <<<"$routes" \
  || fail "booking.ica.local does not appear in the gateway's route table - the Ingress was never translated. Check the class and the controller string"

# --- 6. live traffic ---------------------------------------------------------
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
kubectl -n istio-system port-forward svc/istio-ingressgateway ${PF_HTTP_PORT}:80  >/dev/null 2>&1 & PF_HTTP=$!
kubectl -n istio-system port-forward svc/istio-ingressgateway ${PF_TLS_PORT}:443 >/dev/null 2>&1 & PF_TLS=$!
sleep 5
wait_bound "${PF_HTTP_PORT}" || fail "the local port-forward to the gateway never came up"
wait_bound "${PF_TLS_PORT}" || fail "the local port-forward to the gateway never came up"

http_code() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
    -H "Host: booking.ica.local" "http://localhost:${PF_HTTP_PORT}$1" 2>/dev/null
}
https_code() {
  curl -sk -o /dev/null -w '%{http_code}' --max-time 10 \
    --resolve "booking.ica.local:${PF_TLS_PORT}:127.0.0.1" "https://booking.ica.local:${PF_TLS_PORT}$1" 2>/dev/null
}

# Retry while the listeners come up. Applying config and grading it seconds
# later is a race: the gateway has to receive the route, and for HTTPS also
# fetch and load the credential, before either listener answers.
wait_200() {
  local fn="$1" path="$2" i code
  for i in $(seq 1 30); do
    code=$("$fn" "$path")
    [[ "$code" == "200" ]] && { echo "$code"; return; }
    sleep 2
  done
  echo "$code"
}

c=$(wait_200 http_code /book)
[[ "$c" == "200" ]] || fail "GET /book over HTTP returned '$c', expected 200"

c=$(wait_200 https_code /book)
[[ "$c" == "200" ]] \
  || fail "GET /book over HTTPS returned '$c', expected 200. A '000' here almost always means the HTTPS listener never came up because the gateway cannot read the secret"

c=$(http_code /booking)
[[ "$c" == "200" ]] \
  && fail "GET /booking returned 200. pathType: Prefix is ELEMENT-WISE, so /book must not match /booking. Istio's own uri.prefix behaves differently, which is the trap"

c=$(http_code /status/200)
[[ "$c" == "200" ]] || fail "GET /status/200 returned '$c', expected 200"

c=$(http_code /status/200/extra)
[[ "$c" == "200" ]] \
  && fail "GET /status/200/extra returned 200, but /status/200 is declared pathType: Exact and must not match anything below it"

echo "PASS: IngressClass 'istio' with the correct controller; Ingress 'booking' claimed by it, serving /book (Prefix) and /status/200 (Exact) over HTTP and HTTPS with the secret in istio-system; /booking and /status/200/extra correctly rejected; no Gateway or VirtualService in $NS"
exit 0
