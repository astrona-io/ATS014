#!/usr/bin/env bash
# Confirms HTTPS for starfleet.example.com with the provided certificate, the
# passthrough host reaching the archive with the archive's own certificate, the
# Gateway servers keeping their modes, and the secret ACTIVE on the gateway.

set -u

NS="starfleet"
HOST="starfleet.example.com"
ARCHIVE_HOST="archive.starfleet.example.com"
CRT="/tmp/starfleet-example.crt"
PF_TLS=""

cleanup() { [[ -n "$PF_TLS" ]] && kill "$PF_TLS" 2>/dev/null; }
fail() { cleanup; echo "FAIL: $*"; exit 1; }
trap cleanup EXIT

# --- 0. the environment is intact -------------------------------------------
for d in probe-v1 probe-v2 archive; do
  r=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$r" && "$r" -ge 1 ]] || fail "deployment $d is missing or has no ready replicas. Leave the workloads unchanged"
done
gwr=$(kubectl -n istio-system get deployment istio-ingressgateway -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ -n "$gwr" && "$gwr" -ge 1 ]] || fail "istio-ingressgateway is not ready"
[[ -f "$CRT" ]] || fail "the certificate $CRT is missing. It was written when the lab started"
sidecars=$(kubectl -n "$NS" get pod -l app=archive -o jsonpath='{.items[*].spec.containers[*].name}' 2>/dev/null)
grep -qw istio-proxy <<<"$sidecars" \
  && fail "the archive pod has a sidecar proxy. Leave the archive unchanged: it terminates TLS itself"

# --- 1. the Gateway keeps its two servers ------------------------------------
gw_json=$(kubectl -n "$NS" get gateway starfleet-gateway -o json 2>/dev/null) \
  || fail "Gateway 'starfleet-gateway' not found in $NS"
modes=$(python3 - "$gw_json" <<'PY'
import json, sys
gw = json.loads(sys.argv[1])
by_host = {}
for s in gw.get("spec", {}).get("servers", []):
    for h in s.get("hosts", []):
        tls = s.get("tls", {})
        by_host[h] = (s.get("port", {}).get("protocol", ""), tls.get("mode", ""), tls.get("credentialName", ""))
a = by_host.get("starfleet.example.com", ("", "", ""))
b = by_host.get("archive.starfleet.example.com", ("", "", ""))
print("|".join([a[0], a[1], b[0], b[1], a[2]]))
PY
)
IFS='|' read -r s_proto s_mode a_proto a_mode cred <<<"$modes"
[[ "$s_proto" == "HTTPS" && "$s_mode" == "SIMPLE" ]] \
  || fail "the server for $HOST must be protocol HTTPS with tls.mode SIMPLE (found '$s_proto $s_mode')"
[[ "$a_proto" == "TLS" && "$a_mode" == "PASSTHROUGH" ]] \
  || fail "the server for $ARCHIVE_HOST must be protocol TLS with tls.mode PASSTHROUGH (found '$a_proto $a_mode'). Fix the VirtualService, not the Gateway"

# --- 2. what the gateway proxy holds ----------------------------------------
[[ -n "$cred" ]] || fail "the HTTPS server for $HOST has no credentialName"
if ! kubectl -n istio-system get secret "$cred" >/dev/null 2>&1; then
  fail "the secret '$cred' (credentialName of the HTTPS server) is not in istio-system. The gateway pod reads secrets only from its own namespace"
fi
active=0
for i in $(seq 1 30); do
  if istioctl proxy-config secret deploy/istio-ingressgateway -n istio-system 2>/dev/null \
      | grep "kubernetes://$cred" | grep -q 'ACTIVE'; then active=1; break; fi
  sleep 2
done
[[ "$active" == "1" ]] || fail "the gateway proxy does not hold kubernetes://$cred as ACTIVE. Check the secret name, its namespace and credentialName"

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

PF_TLS_PORT=$(free_port)
kubectl -n istio-system port-forward svc/istio-ingressgateway ${PF_TLS_PORT}:443 >/dev/null 2>&1 & PF_TLS=$!
sleep 3
wait_bound "${PF_TLS_PORT}" || fail "the local port-forward to the gateway never came up"

c=""
for i in $(seq 1 30); do
  c=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 \
    --resolve "${HOST}:${PF_TLS_PORT}:127.0.0.1" "https://${HOST}:${PF_TLS_PORT}/anything/dock" 2>/dev/null)
  [[ "$c" == "200" ]] && break
  sleep 2
done
[[ "$c" == "200" ]] \
  || fail "GET /anything/dock over HTTPS for $HOST returned '$c', expected 200. A '000' means the handshake failed: the gateway has no certificate for this host"

want=$(openssl x509 -in "$CRT" -noout -fingerprint -sha256 2>/dev/null)
got=$(openssl s_client -connect "127.0.0.1:${PF_TLS_PORT}" -servername "$HOST" </dev/null 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256 2>/dev/null)
[[ -n "$got" && "$got" == "$want" ]] \
  || fail "the certificate served for $HOST is not the one in $CRT"

body=""
for i in $(seq 1 30); do
  body=$(curl -sk --max-time 10 \
    --resolve "${ARCHIVE_HOST}:${PF_TLS_PORT}:127.0.0.1" "https://${ARCHIVE_HOST}:${PF_TLS_PORT}/" 2>/dev/null)
  grep -q '"service":"archive"' <<<"$body" && break
  sleep 2
done
grep -q '"service":"archive"' <<<"$body" \
  || fail "the request for $ARCHIVE_HOST did not reach the archive (body: '$body'). A passthrough server needs a VirtualService with a tls: match on sniHosts, not an http: rule"

archive_want=$(kubectl -n "$NS" get secret archive-tls -o go-template='{{index .data "tls.crt" | base64decode}}' 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256 2>/dev/null)
archive_got=$(openssl s_client -connect "127.0.0.1:${PF_TLS_PORT}" -servername "$ARCHIVE_HOST" </dev/null 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256 2>/dev/null)
[[ -n "$archive_got" && "$archive_got" == "$archive_want" ]] \
  || fail "the certificate presented for $ARCHIVE_HOST is not the archive's own certificate. The gateway must pass the connection through, not terminate it"

echo "PASS: HTTPS for $HOST returns 200 with the provided certificate (secret ACTIVE on the gateway); $ARCHIVE_HOST reaches the archive through PASSTHROUGH with the archive's own certificate; both Gateway servers keep their modes"
exit 0
