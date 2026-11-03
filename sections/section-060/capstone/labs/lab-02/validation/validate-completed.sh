#!/usr/bin/env bash
# Confirms the TLS secret in the gateway namespace, HTTPS with the provided
# certificate, the HTTP redirect, the route to bridge, header-based routing to
# probe v2 and v1 through a DestinationRule, and a 404 for other paths.

set -u

NS="starfleet"
HOST="starfleet.example.com"
CRT="/tmp/starfleet-edge.crt"
PF_HTTP="" PF_TLS=""

cleanup() {
  [[ -n "$PF_HTTP" ]] && kill "$PF_HTTP" 2>/dev/null
  [[ -n "$PF_TLS"  ]] && kill "$PF_TLS"  2>/dev/null
}
fail() { cleanup; echo "FAIL: $*"; exit 1; }
trap cleanup EXIT

# --- 0. the environment is intact -------------------------------------------
for d in bridge probe-v1 probe-v2; do
  r=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$r" && "$r" -ge 1 ]] || fail "deployment $d is missing or has no ready replicas. Leave the workloads unchanged"
done
gwr=$(kubectl -n istio-system get deployment istio-ingressgateway -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ -n "$gwr" && "$gwr" -ge 1 ]] || fail "istio-ingressgateway is not ready"
[[ -f "$CRT" ]] || fail "the certificate $CRT is missing. It was written when the lab started"

# --- 1. the objects ------------------------------------------------------------
kubectl -n "$NS" get gateway starfleet-gateway >/dev/null 2>&1 || fail "Gateway 'starfleet-gateway' not found in $NS"
kubectl -n "$NS" get virtualservice starfleet >/dev/null 2>&1 || fail "VirtualService 'starfleet' not found in $NS"
subsets=$(kubectl -n "$NS" get destinationrule probe -o jsonpath='{range .spec.subsets[*]}{.name}={.labels.version} {end}' 2>/dev/null)
grep -q 'v1=v1' <<<"$subsets" && grep -q 'v2=v2' <<<"$subsets" \
  || fail "DestinationRule 'probe' must define the subsets v1 (version: v1) and v2 (version: v2) (found '$subsets')"

# --- 2. the secret -------------------------------------------------------------
if ! kubectl -n istio-system get secret starfleet-tls >/dev/null 2>&1; then
  if kubectl -n "$NS" get secret starfleet-tls >/dev/null 2>&1; then
    fail "the secret 'starfleet-tls' is in $NS but not in istio-system. The gateway pod reads secrets only from its own namespace"
  fi
  fail "secret 'starfleet-tls' not found in istio-system"
fi
stype=$(kubectl -n istio-system get secret starfleet-tls -o jsonpath='{.type}' 2>/dev/null)
[[ "$stype" == "kubernetes.io/tls" ]] \
  || fail "secret starfleet-tls has type '$stype', expected kubernetes.io/tls. Create it with 'kubectl create secret tls'"

active=0
for i in $(seq 1 30); do
  if istioctl proxy-config secret deploy/istio-ingressgateway -n istio-system 2>/dev/null \
      | grep 'kubernetes://starfleet-tls' | grep -q 'ACTIVE'; then active=1; break; fi
  sleep 2
done
[[ "$active" == "1" ]] \
  || fail "the gateway proxy does not hold kubernetes://starfleet-tls as ACTIVE. Check the secret name, its namespace and credentialName in the Gateway"

# --- 3. live traffic ---------------------------------------------------------
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

https_code() {  # $1 = path; optional $2.. = extra curl arguments
  local path="$1"; shift
  curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "$@" \
    --resolve "${HOST}:${PF_TLS_PORT}:127.0.0.1" "https://${HOST}:${PF_TLS_PORT}${path}" 2>/dev/null
}
https_body() {  # $1 = path; optional $2.. = extra curl arguments
  local path="$1"; shift
  curl -sk --max-time 10 "$@" \
    --resolve "${HOST}:${PF_TLS_PORT}:127.0.0.1" "https://${HOST}:${PF_TLS_PORT}${path}" 2>/dev/null
}

c=""
for i in $(seq 1 30); do
  c=$(https_code /productpage)
  [[ "$c" == "200" ]] && break
  sleep 2
done
[[ "$c" == "200" ]] \
  || fail "GET /productpage over HTTPS returned '$c', expected 200. A '000' means the handshake failed: the gateway has no certificate for $HOST"

want=$(openssl x509 -in "$CRT" -noout -fingerprint -sha256 2>/dev/null)
got=$(openssl s_client -connect "127.0.0.1:${PF_TLS_PORT}" -servername "$HOST" </dev/null 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256 2>/dev/null)
[[ -n "$got" && "$got" == "$want" ]] \
  || fail "the certificate served for $HOST is not the one in $CRT. Create the secret from that certificate and key"

# header routing: beta goes to v2, everything else to v1
beta=""
for i in $(seq 1 15); do
  beta=$(https_body /hostname -H "x-channel: beta")
  grep -q 'probe-v2' <<<"$beta" && break
  sleep 2
done
grep -q 'probe-v2' <<<"$beta" \
  || fail "GET /hostname with x-channel: beta was not answered by a probe-v2 pod (body: '$beta'). Check the header match and the subset v2"

v1=0
for i in $(seq 1 5); do
  grep -q 'probe-v1' <<<"$(https_body /hostname)" && v1=$((v1 + 1))
done
[[ "$v1" -eq 5 ]] || fail "$v1 of 5 requests to /hostname without the header were answered by probe-v1, expected 5. The rule without the header must send every request to subset v1"

c=$(https_code /status/200)
[[ "$c" == "404" ]] || fail "GET /status/200 over HTTPS returned '$c', expected 404. The VirtualService must have routes for /productpage and /hostname only"

# plain HTTP redirects
out=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 10 \
  -H "Host: ${HOST}" "http://localhost:${PF_HTTP_PORT}/productpage" 2>/dev/null)
code="${out%% *}"
loc="${out#* }"
[[ "$code" == "301" ]] \
  || fail "plain HTTP GET /productpage returned '$code', expected 301. The port 80 server needs tls.httpsRedirect: true and host $HOST"
[[ "$loc" == https://${HOST}* ]] \
  || fail "the redirect address is '$loc', expected it to start with https://${HOST}"

echo "PASS: secret starfleet-tls ACTIVE on the gateway; HTTPS for $HOST serves the provided certificate; /productpage returns 200; x-channel: beta reaches probe-v2 and other /hostname requests reach probe-v1; other paths return 404; plain HTTP returns 301 to https://$HOST"
exit 0
