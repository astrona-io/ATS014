#!/usr/bin/env bash
# Confirms the three-object TLS origination chain: a ServiceEntry with both
# ports, a VirtualService redirecting 8080 to 8443, and a DestinationRule
# originating TLS under portLevelSettings with sni - proven by the TLS-only
# endpoint reporting scheme=https to a plain http:// caller.

set -u

NS="tlsorig-demo"
NAME="secure-api"
HOST="secure.example.com"

fail() { echo "FAIL: $*"; exit 1; }

SECURE_IP=$(cat /tmp/secure-ip 2>/dev/null || kubectl -n outside-mesh get pod secure-api -o jsonpath='{.status.podIP}' 2>/dev/null)
[[ -n "$SECURE_IP" ]] || fail "could not determine the secure-api pod address"

# --- 0. the environment is intact -------------------------------------------
r=$(kubectl -n "$NS" get deployment tester -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ -n "$r" && "$r" -ge 1 ]] || fail "tester - deployment missing or has no ready replicas"
ph=$(kubectl -n outside-mesh get pod secure-api -o jsonpath='{.status.phase}' 2>/dev/null)
[[ "$ph" == "Running" ]] || fail "outside-mesh/secure-api is '$ph', expected Running"
if kubectl -n outside-mesh get svc -o name 2>/dev/null | grep -q .; then
  fail "a Service exists in outside-mesh - that would put the endpoint in the mesh registry through the back door"
fi

# --- 1. the ServiceEntry with BOTH ports ------------------------------------
kubectl -n "$NS" get serviceentry "$NAME" >/dev/null 2>&1 \
  || fail "ServiceEntry '$NAME' not found in $NS"

hosts=$(kubectl -n "$NS" get serviceentry "$NAME" -o jsonpath='{.spec.hosts[*]}' 2>/dev/null)
grep -qw "$HOST" <<<"$hosts" || fail "the ServiceEntry hosts are [$hosts] - $HOST is missing"

addrs=$(kubectl -n "$NS" get serviceentry "$NAME" -o jsonpath='{.spec.addresses[*]}' 2>/dev/null)
grep -q "$SECURE_IP" <<<"$addrs" \
  || fail "the ServiceEntry addresses are [$addrs] - $SECURE_IP is missing. Without it the sidecar cannot match traffic aimed at that IP"

proto_for() {
  kubectl -n "$NS" get serviceentry "$NAME" \
    -o jsonpath="{.spec.ports[?(@.number==$1)].protocol}" 2>/dev/null
}
p80=$(proto_for 8080); p443=$(proto_for 8443)
[[ "$p80" == "HTTP" ]] \
  || fail "port 8080 is declared '$p80', expected HTTP. Without a plaintext HTTP port the application's request has nowhere to arrive"
[[ "$p443" == "HTTPS" ]] \
  || fail "port 8443 is declared '$p443', expected HTTPS"

loc=$(kubectl -n "$NS" get serviceentry "$NAME" -o jsonpath='{.spec.location}' 2>/dev/null)
res=$(kubectl -n "$NS" get serviceentry "$NAME" -o jsonpath='{.spec.resolution}' 2>/dev/null)
[[ "$loc" == "MESH_EXTERNAL" ]] || fail "location is '$loc', expected MESH_EXTERNAL"
[[ "$res" == "STATIC" ]]        || fail "resolution is '$res', expected STATIC"
ep=$(kubectl -n "$NS" get serviceentry "$NAME" -o jsonpath='{.spec.endpoints[0].address}' 2>/dev/null)
[[ "$ep" == "$SECURE_IP" ]] || fail "endpoints[0].address is '$ep', expected $SECURE_IP"

# --- 2. the VirtualService redirects the port -------------------------------
kubectl -n "$NS" get virtualservice "$NAME" >/dev/null 2>&1 \
  || fail "VirtualService '$NAME' not found in $NS"
mport=$(kubectl -n "$NS" get virtualservice "$NAME" -o jsonpath='{.spec.http[0].match[0].port}' 2>/dev/null)
dport=$(kubectl -n "$NS" get virtualservice "$NAME" -o jsonpath='{.spec.http[0].route[0].destination.port.number}' 2>/dev/null)
dhost=$(kubectl -n "$NS" get virtualservice "$NAME" -o jsonpath='{.spec.http[0].route[0].destination.host}' 2>/dev/null)
[[ "$mport" == "8080" ]] || fail "the VirtualService matches port '$mport', expected 8080"
[[ "$dport" == "8443" ]] || fail "the VirtualService routes to port '$dport', expected 8443"
[[ "$dhost" == "$HOST" ]] || fail "the VirtualService routes to host '$dhost', expected $HOST - only the port should change"

# --- 3. the DestinationRule originates TLS on the RIGHT port ----------------
kubectl -n "$NS" get destinationrule "$NAME" >/dev/null 2>&1 \
  || fail "DestinationRule '$NAME' not found in $NS"

toptls=$(kubectl -n "$NS" get destinationrule "$NAME" -o jsonpath='{.spec.trafficPolicy.tls.mode}' 2>/dev/null)
[[ -z "$toptls" ]] \
  || fail "the DestinationRule sets tls at the TOP level of trafficPolicy (mode '$toptls'). That applies to port 8080 too, so the proxy tries to originate TLS on the plaintext side and the whole arrangement breaks. It belongs under portLevelSettings for 8443"

plsport=$(kubectl -n "$NS" get destinationrule "$NAME" \
  -o jsonpath='{.spec.trafficPolicy.portLevelSettings[0].port.number}' 2>/dev/null)
[[ "$plsport" == "8443" ]] \
  || fail "portLevelSettings[0].port.number is '$plsport', expected 8443"

mode=$(kubectl -n "$NS" get destinationrule "$NAME" \
  -o jsonpath='{.spec.trafficPolicy.portLevelSettings[0].tls.mode}' 2>/dev/null)
sni=$(kubectl -n "$NS" get destinationrule "$NAME" \
  -o jsonpath='{.spec.trafficPolicy.portLevelSettings[0].tls.sni}' 2>/dev/null)
[[ "$mode" == "SIMPLE" ]] || fail "the port 8443 tls mode is '$mode', expected SIMPLE"
[[ "$sni" == "$HOST" ]] \
  || fail "the port 8443 tls sni is '$sni', expected $HOST. The proxy is the TLS client now and must announce the server name"

# --- 4. the proxy holds a TLS transport socket ------------------------------
dump=$(istioctl proxy-config cluster deploy/tester -n "$NS" --fqdn "$HOST" -o json 2>/dev/null)
[[ -n "$dump" ]] || fail "could not read the tester proxy's cluster config for $HOST"
grep -q 'transportSocket' <<<"$dump" \
  || fail "the tester proxy's cluster for $HOST has no transportSocket - TLS origination is not configured on it"

# --- 5. the decisive test: plain http:// reaching a TLS-only endpoint -------
body=$(kubectl -n "$NS" exec deploy/tester -- \
  curl -s --max-time 15 "http://${SECURE_IP}:8080/" 2>/dev/null)
code=$(kubectl -n "$NS" exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code}' --max-time 15 "http://${SECURE_IP}:8080/" 2>/dev/null)

[[ "$code" == "200" ]] \
  || fail "GET http://${SECURE_IP}:8080/ returned '$code', expected 200. The endpoint speaks only TLS, so a failure here means the sidecar sent plaintext - check the VirtualService port redirect and the DestinationRule"

grep -q 'scheme=https' <<<"$body" \
  || fail "the endpoint reported '$body', expected 'scheme=https'. It answers with the scheme it was actually reached over, so anything else means TLS was not originated"

echo "PASS: ServiceEntry declares 8080/HTTP and 8443/HTTPS for $HOST at $SECURE_IP; the VirtualService redirects 8080 to 8443; the DestinationRule originates SIMPLE TLS with sni under portLevelSettings for 8443; and a plain http:// call reached the TLS-only endpoint, which reported scheme=https"
exit 0
