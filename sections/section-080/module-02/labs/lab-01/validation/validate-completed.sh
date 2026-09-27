#!/usr/bin/env bash
# Confirms the five-object chain: both ports declared, a gateway listener on
# 8080, a two-stage VirtualService whose gateway stage targets 8443, and an
# origination DestinationRule on the EXTERNAL host - proven by the gateway log,
# the transportSocket comparison across both proxies, and the endpoint itself.

set -u

NS="egwtls-demo"
HOST="partner.example.com"

fail() { echo "FAIL: $*"; exit 1; }

PARTNER=$(cat /tmp/partner-ip 2>/dev/null || kubectl -n outside-mesh get pod partner-api -o jsonpath='{.status.podIP}' 2>/dev/null)
[[ -n "$PARTNER" ]] || fail "could not determine the partner-api address"

gw_lines() { kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 2>/dev/null | grep -c "$HOST"; }

# --- 0. the environment is intact -------------------------------------------
r=$(kubectl -n "$NS" get deployment tester -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ -n "$r" && "$r" -ge 1 ]] || fail "tester - deployment missing or has no ready replicas"
ph=$(kubectl -n outside-mesh get pod partner-api -o jsonpath='{.status.phase}' 2>/dev/null)
[[ "$ph" == "Running" ]] || fail "outside-mesh/partner-api is '$ph', expected Running"
if kubectl -n outside-mesh get svc -o name 2>/dev/null | grep -q .; then
  fail "a Service exists in outside-mesh - that registers the endpoint through the back door"
fi

# --- 1. the ServiceEntry with BOTH ports ------------------------------------
kubectl -n "$NS" get serviceentry partner >/dev/null 2>&1 || fail "ServiceEntry 'partner' not found in $NS"
a=$(kubectl -n "$NS" get serviceentry partner -o jsonpath='{.spec.addresses[*]}' 2>/dev/null)
grep -q "$PARTNER" <<<"$a" || fail "the ServiceEntry addresses are [$a] - $PARTNER is missing"
pp() { kubectl -n "$NS" get serviceentry partner -o jsonpath="{.spec.ports[?(@.number==$1)].protocol}" 2>/dev/null; }
[[ "$(pp 8080)" == "HTTP" ]] \
  || fail "port 8080 is declared '$(pp 8080)', expected HTTP - it is where the sidecar's plaintext traffic arrives"
[[ "$(pp 8443)" == "HTTPS" ]] \
  || fail "port 8443 is declared '$(pp 8443)', expected HTTPS - stage 2 has nowhere to send traffic without it"

# --- 2. the Gateway listener -------------------------------------------------
kubectl -n "$NS" get gateway egress-gateway >/dev/null 2>&1 || fail "Gateway 'egress-gateway' not found in $NS"
sel=$(kubectl -n "$NS" get gateway egress-gateway -o jsonpath='{.spec.selector.istio}' 2>/dev/null)
[[ "$sel" == "egressgateway" ]] || fail "the Gateway selector istio='$sel', expected 'egressgateway'"
gp=$(kubectl -n "$NS" get gateway egress-gateway -o jsonpath='{.spec.servers[0].port.number}' 2>/dev/null)
[[ "$gp" == "8080" ]] \
  || fail "the Gateway listener port is '$gp', expected 8080. The gateway RECEIVES on 8080 and SENDS on 8443 - those are two directions, not an inconsistency"
gh=$(kubectl -n "$NS" get gateway egress-gateway -o jsonpath='{.spec.servers[*].hosts[*]}' 2>/dev/null)
grep -qw "$HOST" <<<"$gh" || fail "the Gateway hosts are [$gh] - it must name the external host $HOST"

# --- 3. the gateway-subset DestinationRule ----------------------------------
kubectl -n "$NS" get destinationrule egressgateway-for-partner >/dev/null 2>&1 \
  || fail "DestinationRule 'egressgateway-for-partner' not found in $NS"
ds=$(kubectl -n "$NS" get destinationrule egressgateway-for-partner -o jsonpath='{.spec.subsets[0].name}' 2>/dev/null)
[[ "$ds" == "partner" ]] || fail "the gateway DestinationRule subset is '$ds', expected 'partner'"

# --- 4. the two-stage VirtualService -----------------------------------------
VS=partner-through-egress
kubectl -n "$NS" get virtualservice "$VS" >/dev/null 2>&1 || fail "VirtualService '$VS' not found in $NS"
tg=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.gateways[*]}' 2>/dev/null)
grep -qw 'mesh' <<<"$tg" || fail "the top-level gateways are [$tg] - 'mesh' is missing, so stage 1 never reaches sidecars"
grep -q 'egress-gateway' <<<"$tg" || fail "the top-level gateways are [$tg] - the gateway is missing"

s1g=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[0].match[0].gateways[0]}' 2>/dev/null)
[[ "$s1g" == "mesh" ]] || fail "the FIRST rule matches gateways '[$s1g]', expected [mesh]"
s1h=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[0].route[0].destination.host}' 2>/dev/null)
grep -q 'istio-egressgateway' <<<"$s1h" || fail "stage 1 routes to '$s1h', expected the egress gateway Service"

s2g=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[1].match[0].gateways[0]}' 2>/dev/null)
grep -q 'egress-gateway' <<<"$s2g" || fail "the SECOND rule matches gateways '[$s2g]', expected the gateway name"
s2h=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[1].route[0].destination.host}' 2>/dev/null)
s2p=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[1].route[0].destination.port.number}' 2>/dev/null)
[[ "$s2h" == "$HOST" ]] || fail "stage 2 routes to host '$s2h', expected $HOST"
[[ "$s2p" == "8443" ]] \
  || fail "stage 2 routes to port '$s2p', expected 8443. Routing to 8080 forwards plaintext to a TLS-only endpoint"

# --- 5. the origination DestinationRule on the EXTERNAL host ----------------
DR=originate-tls-for-partner
kubectl -n "$NS" get destinationrule "$DR" >/dev/null 2>&1 || fail "DestinationRule '$DR' not found in $NS"
dh=$(kubectl -n "$NS" get destinationrule "$DR" -o jsonpath='{.spec.host}' 2>/dev/null)
[[ "$dh" == "$HOST" ]] \
  || fail "the origination DestinationRule targets host '$dh', expected $HOST. Traffic policy is applied by the proxy CALLING that host - pointing it at the gateway Service originates nothing"

top=$(kubectl -n "$NS" get destinationrule "$DR" -o jsonpath='{.spec.trafficPolicy.tls.mode}' 2>/dev/null)
[[ -z "$top" ]] || fail "the origination DestinationRule sets tls at the TOP level (mode '$top') - it belongs under portLevelSettings for 8443"
plp=$(kubectl -n "$NS" get destinationrule "$DR" -o jsonpath='{.spec.trafficPolicy.portLevelSettings[0].port.number}' 2>/dev/null)
plm=$(kubectl -n "$NS" get destinationrule "$DR" -o jsonpath='{.spec.trafficPolicy.portLevelSettings[0].tls.mode}' 2>/dev/null)
pls=$(kubectl -n "$NS" get destinationrule "$DR" -o jsonpath='{.spec.trafficPolicy.portLevelSettings[0].tls.sni}' 2>/dev/null)
[[ "$plp" == "8443" ]]   || fail "portLevelSettings port is '$plp', expected 8443"
[[ "$plm" == "SIMPLE" ]] || fail "the port 8443 tls mode is '$plm', expected SIMPLE"
[[ "$pls" == "$HOST" ]]  || fail "the port 8443 tls sni is '$pls', expected $HOST"

# --- 6. live: plain http:// reaches a TLS-only endpoint ---------------------
before=$(gw_lines)
body=$(kubectl -n "$NS" exec deploy/tester -- curl -s --max-time 20 "http://${PARTNER}:8080/" 2>/dev/null)
code=$(kubectl -n "$NS" exec deploy/tester -- curl -s -o /dev/null -w '%{http_code}' --max-time 20 "http://${PARTNER}:8080/" 2>/dev/null)
sleep 3
after=$(gw_lines)

[[ "$code" == "200" ]] \
  || fail "GET http://${PARTNER}:8080/ returned '$code', expected 200. The endpoint speaks only TLS, so a failure means plaintext reached it"
grep -q 'scheme=https' <<<"$body" \
  || fail "the endpoint reported '$body', expected 'scheme=https' - TLS was not originated"

# --- 7. the gateway was in the path, on port 8443 ---------------------------
[[ $((after - before)) -ge 1 ]] \
  || fail "the gateway logged no line for $HOST. The call succeeded, which proves nothing - it may have gone direct from the sidecar. Check stage 1 and 'mesh' in the top-level gateways"
kubectl -n istio-system logs deploy/istio-egressgateway --tail=20 2>/dev/null \
  | grep "$HOST" | tail -1 | grep -q ':8443' \
  || fail "the gateway's log line for $HOST does not show an upstream on port 8443 - stage 2 is routing to the wrong port"

# --- 8. the TLS context is on the GATEWAY, not the sidecar ------------------
gw_tls=$(istioctl proxy-config cluster deploy/istio-egressgateway -n istio-system \
  --fqdn "$HOST" -o json 2>/dev/null | grep -c transportSocket)
sc_tls=$(istioctl proxy-config cluster deploy/tester -n "$NS" \
  --fqdn "$HOST" -o json 2>/dev/null | grep -c transportSocket)
[[ "$gw_tls" -ge 1 ]] \
  || fail "the GATEWAY proxy's cluster for $HOST has no transportSocket - the origination DestinationRule did not take effect on it"
[[ "$sc_tls" -eq 0 ]] \
  || fail "the TESTER sidecar's cluster for $HOST has a transportSocket ($sc_tls). The sidecar should only speak plain HTTP to the gateway - this suggests the sidecar is originating TLS itself"

echo "PASS: five objects route $HOST through the egress gateway with TLS originated there - a plain http:// call returned 200 with scheme=https, the gateway logged the request upstream on 8443, and the transportSocket is on the gateway ($gw_tls) and not on the sidecar ($sc_tls)"
exit 0
