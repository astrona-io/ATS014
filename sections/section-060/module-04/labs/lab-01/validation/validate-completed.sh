#!/usr/bin/env bash
# Confirms the TLS secret in the gateway namespace, HTTPS served with the
# provided certificate, the gateway holding the secret as ACTIVE, and plain
# HTTP redirected to HTTPS.

set -u

NS="starfleet"
HOST="probe.example.com"
CRT="/tmp/probe-example.crt"
PF_HTTP="" PF_TLS=""

cleanup() {
  [[ -n "$PF_HTTP" ]] && kill "$PF_HTTP" 2>/dev/null
  [[ -n "$PF_TLS"  ]] && kill "$PF_TLS"  2>/dev/null
}
fail() { cleanup; echo "FAIL: $*"; exit 1; }
trap cleanup EXIT

# --- 0. the environment is intact -------------------------------------------
r=$(kubectl -n "$NS" get deployment probe-v1 -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ -n "$r" && "$r" -ge 1 ]] || fail "probe-v1 - deployment missing or has no ready replicas"
gwr=$(kubectl -n istio-system get deployment istio-ingressgateway -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ -n "$gwr" && "$gwr" -ge 1 ]] || fail "istio-ingressgateway is not ready"
[[ -f "$CRT" ]] || fail "the certificate $CRT is missing. It was written when the lab started"

# --- 1. the secret ------------------------------------------------------------
if ! kubectl -n istio-system get secret probe-tls >/dev/null 2>&1; then
  if kubectl -n "$NS" get secret probe-tls >/dev/null 2>&1; then
    fail "the secret 'probe-tls' is in $NS but not in istio-system. The gateway pod loads the certificate, and it reads secrets only from its own namespace"
  fi
  fail "secret 'probe-tls' not found in istio-system"
fi
stype=$(kubectl -n istio-system get secret probe-tls -o jsonpath='{.type}' 2>/dev/null)
[[ "$stype" == "kubernetes.io/tls" ]] \
  || fail "secret probe-tls has type '$stype', expected kubernetes.io/tls. Create it with 'kubectl create secret tls'"

# --- 2. the Gateway and the VirtualService exist -----------------------------
kubectl -n "$NS" get gateway probe-gateway >/dev/null 2>&1 || fail "Gateway 'probe-gateway' not found in $NS"
kubectl -n "$NS" get virtualservice probe >/dev/null 2>&1 || fail "VirtualService 'probe' not found in $NS"

# --- 3. what the gateway proxy holds ----------------------------------------
wait_secret_active() {
  local i
  for i in $(seq 1 30); do
    if istioctl proxy-config secret deploy/istio-ingressgateway -n istio-system 2>/dev/null \
        | grep 'kubernetes://probe-tls' | grep -q 'ACTIVE'; then
      return 0
    fi
    sleep 2
  done
  return 1
}
wait_secret_active \
  || fail "the gateway proxy does not hold kubernetes://probe-tls as ACTIVE. A status of WARMING means istiod could not find the secret: check its name, its namespace and credentialName in the Gateway"

listeners=$(istioctl proxy-config listeners deploy/istio-ingressgateway -n istio-system 2>/dev/null)
grep -Eq '[[:space:]]443[[:space:]]' <<<"$listeners" \
  || fail "the gateway has no listener on port 443. Check that the Gateway selector matches the gateway pod and that the HTTPS server exists"

# --- 4. live traffic ---------------------------------------------------------
# Pick free local ports and wait for the forwards to bind, so two labs graded at
# the same time on one machine do not collide.
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
sleep 3
wait_bound "${PF_HTTP_PORT}" || fail "the local port-forward to the gateway never came up"
wait_bound "${PF_TLS_PORT}" || fail "the local port-forward to the gateway never came up"

https_code() {
  curl -sk -o /dev/null -w '%{http_code}' --max-time 10 \
    --resolve "${HOST}:${PF_TLS_PORT}:127.0.0.1" "https://${HOST}:${PF_TLS_PORT}$1" 2>/dev/null
}

c=""
for i in $(seq 1 30); do
  c=$(https_code /get)
  [[ "$c" == "200" ]] && break
  sleep 2
done
[[ "$c" == "200" ]] \
  || fail "GET /get over HTTPS returned '$c', expected 200. A '000' usually means the handshake failed: the gateway has no certificate for $HOST. Check the secret and credentialName"

# the gateway serves the certificate from the file
want=$(openssl x509 -in "$CRT" -noout -fingerprint -sha256 2>/dev/null)
got=$(openssl s_client -connect "127.0.0.1:${PF_TLS_PORT}" -servername "$HOST" </dev/null 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256 2>/dev/null)
[[ -n "$got" && "$got" == "$want" ]] \
  || fail "the certificate served for $HOST is not the one in $CRT. Create the secret from that certificate and key"

# plain HTTP redirects
out=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 10 \
  -H "Host: ${HOST}" "http://localhost:${PF_HTTP_PORT}/get" 2>/dev/null)
code="${out%% *}"
loc="${out#* }"
[[ "$code" == "301" ]] \
  || fail "plain HTTP GET /get returned '$code', expected 301. The port 80 server needs tls.httpsRedirect: true and host $HOST"
[[ "$loc" == https://${HOST}* ]] \
  || fail "the redirect address is '$loc', expected it to start with https://${HOST}"

echo "PASS: secret probe-tls (kubernetes.io/tls) in istio-system and ACTIVE on the gateway; HTTPS for $HOST serves the provided certificate and returns 200; plain HTTP returns 301 to https://$HOST"
exit 0
