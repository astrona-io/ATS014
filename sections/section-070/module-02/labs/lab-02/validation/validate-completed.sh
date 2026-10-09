#!/usr/bin/env bash
# Confirms the repaired TLS origination to the vault: the ServiceEntry was left
# alone, the VirtualService moves port 8080 to 8443, the DestinationRule seals
# only port 8443 (with sni), the shuttle's proxy holds a TLS transport socket
# for 8443 and none for 8080 - and, the part that matters, a plain http://
# signal from the shuttle reaches the TLS-only vault, which reports
# scheme=https.

set -u

NS="starfleet"
NAME="vault"
HOST="vault.outpost.example"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is still what the lab handed over -------------------
r=$(kubectl -n "$NS" get deployment shuttle -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ -n "$r" && "$r" -ge 1 ]] || fail "shuttle - deployment missing or has no ready replicas in $NS"
ph=$(kubectl -n outpost get pod vault -o jsonpath='{.status.phase}' 2>/dev/null)
[[ "$ph" == "Running" ]] || fail "outpost/vault is '$ph', expected Running. Leave the vault alone: the fault is in the Istio objects"
VAULT_IP=$(kubectl -n outpost get pod vault -o jsonpath='{.status.podIP}' 2>/dev/null)
[[ -n "$VAULT_IP" ]] || fail "could not read the vault pod's address"
if kubectl -n outpost get svc -o name 2>/dev/null | grep -q .; then
  fail "a Service exists in outpost. The vault must stay off the star chart except through the ServiceEntry"
fi

# --- 1. the ServiceEntry was correct: it must still be ----------------------
kubectl -n "$NS" get serviceentry "$NAME" >/dev/null 2>&1 \
  || fail "ServiceEntry '$NAME' not found in $NS. It was correct, leave it in place"
proto_for() {
  kubectl -n "$NS" get serviceentry "$NAME" \
    -o jsonpath="{.spec.ports[?(@.number==$1)].protocol}" 2>/dev/null
}
[[ "$(proto_for 8080)" == "HTTP" && "$(proto_for 8443)" == "HTTPS" ]] \
  || fail "the ServiceEntry must still declare 8080 as HTTP and 8443 as HTTPS (found 8080='$(proto_for 8080)', 8443='$(proto_for 8443)'). It was correct, leave it alone"
addrs=$(kubectl -n "$NS" get serviceentry "$NAME" -o jsonpath='{.spec.addresses[*]}' 2>/dev/null)
grep -qw "$VAULT_IP" <<<"$addrs" || fail "the ServiceEntry addresses are [$addrs], the vault is at $VAULT_IP. Leave the ServiceEntry as it was"

# --- 2. the VirtualService moves the signal from 8080 to 8443 ---------------
kubectl -n "$NS" get virtualservice "$NAME" >/dev/null 2>&1 \
  || fail "VirtualService '$NAME' not found in $NS. Fix it, do not delete it: without it the signal never reaches port 8443"
mport=$(kubectl -n "$NS" get virtualservice "$NAME" -o jsonpath='{.spec.http[0].match[0].port}' 2>/dev/null)
dport=$(kubectl -n "$NS" get virtualservice "$NAME" -o jsonpath='{.spec.http[0].route[0].destination.port.number}' 2>/dev/null)
dhost=$(kubectl -n "$NS" get virtualservice "$NAME" -o jsonpath='{.spec.http[0].route[0].destination.host}' 2>/dev/null)
[[ "$mport" == "8080" ]] \
  || fail "the VirtualService matches port '$mport', but the shuttle calls port 8080. A rule for a port nobody calls never fires, so the signal stays on 8080"
[[ "$dport" == "8443" ]] || fail "the VirtualService routes to port '$dport', expected 8443"
[[ "$dhost" == "$HOST" ]] || fail "the VirtualService routes to host '$dhost', expected $HOST. Only the port should change"

# --- 3. the DestinationRule seals the right port ----------------------------
kubectl -n "$NS" get destinationrule "$NAME" >/dev/null 2>&1 \
  || fail "DestinationRule '$NAME' not found in $NS. Without it the proxy sends plain HTTP to the TLS port"
toptls=$(kubectl -n "$NS" get destinationrule "$NAME" -o jsonpath='{.spec.trafficPolicy.tls.mode}' 2>/dev/null)
[[ -z "$toptls" ]] \
  || fail "the DestinationRule sets tls at the top level of trafficPolicy (mode '$toptls'). That seals port 8080 too. Put it under portLevelSettings for 8443 only"
tls8080=$(kubectl -n "$NS" get destinationrule "$NAME" \
  -o jsonpath='{.spec.trafficPolicy.portLevelSettings[?(@.port.number==8080)].tls.mode}' 2>/dev/null)
[[ -z "$tls8080" ]] \
  || fail "the DestinationRule still seals port 8080 (tls mode '$tls8080'). Port 8080 is the plain side, where the application arrives"
mode=$(kubectl -n "$NS" get destinationrule "$NAME" \
  -o jsonpath='{.spec.trafficPolicy.portLevelSettings[?(@.port.number==8443)].tls.mode}' 2>/dev/null)
sni=$(kubectl -n "$NS" get destinationrule "$NAME" \
  -o jsonpath='{.spec.trafficPolicy.portLevelSettings[?(@.port.number==8443)].tls.sni}' 2>/dev/null)
[[ "$mode" == "SIMPLE" ]] \
  || fail "port 8443 has tls mode '$mode', expected SIMPLE under portLevelSettings for port 8443"
[[ "$sni" == "$HOST" ]] \
  || fail "port 8443 has sni '$sni', expected $HOST. The proxy is the TLS client now and must name the server"

# --- 4. the shuttle's proxy has the orders ----------------------------------
sock_count() {
  istioctl proxy-config cluster deploy/shuttle -n "$NS" --fqdn "$HOST" --port "$1" -o json 2>/dev/null \
    | grep -c 'envoy.transport_sockets.tls'
}
ok=""
for i in $(seq 1 15); do
  if [[ "$(sock_count 8443)" -ge 1 && "$(sock_count 8080)" -eq 0 ]]; then ok=1; break; fi
  sleep 2
done
[[ -n "$ok" ]] \
  || fail "the shuttle's proxy should seal port 8443 and leave port 8080 plain (TLS transport sockets: 8443=$(sock_count 8443), 8080=$(sock_count 8080)). Check: istioctl proxy-config cluster deploy/shuttle -n $NS --fqdn $HOST"

# --- 5. the decisive test: plain http:// reaching the TLS-only vault --------
code=""; body=""
for i in $(seq 1 10); do
  body=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 10 "http://${VAULT_IP}:8080/" 2>/dev/null)
  code=$(kubectl -n "$NS" exec deploy/shuttle -- \
    curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://${VAULT_IP}:8080/" 2>/dev/null)
  [[ "$code" == "200" ]] && grep -q 'scheme=https' <<<"$body" && break
  sleep 2
done
[[ "$code" == "200" ]] \
  || fail "GET http://${VAULT_IP}:8080/ from the shuttle returned '$code', expected 200. 503 UF means the signal went to port 8080; 400 means plain HTTP reached the TLS port. Read the shuttle's flight log"
grep -q 'scheme=https' <<<"$body" \
  || fail "the vault answered '$body', expected 'scheme=https'. It reports how it was reached, so TLS was not originated"

echo "PASS: the VirtualService moves port 8080 to 8443, the DestinationRule seals only port 8443 with sni $HOST, and a plain http:// signal from the shuttle reached the TLS-only vault, which reported scheme=https"
exit 0
