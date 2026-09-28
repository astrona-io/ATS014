#!/usr/bin/env bash
# Section 080 capstone. Confirms ONE egress gateway carrying TWO external hosts
# - one plain HTTP restricted by sourceLabels, one with TLS originated at the
# gateway - with the TLS context on the gateway rather than the sidecar.

set -u

NS="edge-egress"
PLAIN_HOST="plain.partner.example"
SEC_HOST="secure.partner.example"

fail() { echo "FAIL: $*"; exit 1; }

PLAIN=$(cat /tmp/plain-ip 2>/dev/null || kubectl -n outside-mesh get pod plain-api -o jsonpath='{.status.podIP}' 2>/dev/null)
SECURE=$(cat /tmp/secure-ip 2>/dev/null || kubectl -n outside-mesh get pod secure-api -o jsonpath='{.status.podIP}' 2>/dev/null)
[[ -n "$PLAIN" && -n "$SECURE" ]] || fail "could not determine the endpoint addresses"

gw_lines() { kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 2>/dev/null | grep -c "$1"; }

# --- 0. environment ----------------------------------------------------------
for d in tester other-client; do
  r=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$r" && "$r" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas"
done
for p in plain-api secure-api; do
  ph=$(kubectl -n outside-mesh get pod "$p" -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$ph" == "Running" ]] || fail "outside-mesh/$p is '$ph', expected Running"
done
kubectl -n outside-mesh get svc -o name 2>/dev/null | grep -q . \
  && fail "a Service exists in outside-mesh - that registers an endpoint through the back door"

# --- 1. the ServiceEntries ---------------------------------------------------
se_proto() { kubectl -n "$NS" get serviceentry "$1" -o jsonpath="{.spec.ports[?(@.number==$2)].protocol}" 2>/dev/null; }

kubectl -n "$NS" get serviceentry plain >/dev/null 2>&1 || fail "ServiceEntry 'plain' not found in $NS"
grep -q "$PLAIN" <<<"$(kubectl -n "$NS" get serviceentry plain -o jsonpath='{.spec.addresses[*]}' 2>/dev/null)" \
  || fail "the 'plain' ServiceEntry does not list address $PLAIN"
[[ "$(se_proto plain 8080)" == "HTTP" ]] || fail "'plain' port 8080 is '$(se_proto plain 8080)', expected HTTP"

kubectl -n "$NS" get serviceentry secure >/dev/null 2>&1 || fail "ServiceEntry 'secure' not found in $NS"
grep -q "$SECURE" <<<"$(kubectl -n "$NS" get serviceentry secure -o jsonpath='{.spec.addresses[*]}' 2>/dev/null)" \
  || fail "the 'secure' ServiceEntry does not list address $SECURE"
[[ "$(se_proto secure 8081)" == "HTTP" ]] \
  || fail "'secure' port 8081 is '$(se_proto secure 8081)', expected HTTP - it is where the sidecar's plaintext traffic arrives"
[[ "$(se_proto secure 8443)" == "HTTPS" ]] \
  || fail "'secure' port 8443 is '$(se_proto secure 8443)', expected HTTPS"

# --- 2. one Gateway, two listeners ------------------------------------------
kubectl -n "$NS" get gateway egress-gateway >/dev/null 2>&1 || fail "Gateway 'egress-gateway' not found in $NS"
sel=$(kubectl -n "$NS" get gateway egress-gateway -o jsonpath='{.spec.selector.istio}' 2>/dev/null)
[[ "$sel" == "egressgateway" ]] || fail "the Gateway selector istio='$sel', expected 'egressgateway'"

gw_host_for_port() {
  kubectl -n "$NS" get gateway egress-gateway \
    -o jsonpath="{.spec.servers[?(@.port.number==$1)].hosts[*]}" 2>/dev/null
}
grep -q "$PLAIN_HOST" <<<"$(gw_host_for_port 8080)" \
  || fail "the Gateway has no server on port 8080 for $PLAIN_HOST (found '$(gw_host_for_port 8080)')"
grep -q "$SEC_HOST" <<<"$(gw_host_for_port 8081)" \
  || fail "the Gateway has no server on port 8081 for $SEC_HOST (found '$(gw_host_for_port 8081)')"

# --- 3. the two subsets ------------------------------------------------------
kubectl -n "$NS" get destinationrule egressgateway-subsets >/dev/null 2>&1 \
  || fail "DestinationRule 'egressgateway-subsets' not found in $NS"
subs=$(kubectl -n "$NS" get destinationrule egressgateway-subsets -o jsonpath='{.spec.subsets[*].name}' 2>/dev/null)
for s in plain secure; do
  grep -qw "$s" <<<"$subs" || fail "the gateway DestinationRule subsets are [$subs] - '$s' is missing"
done

# --- 4. the two two-stage VirtualServices -----------------------------------
check_vs() {
  local vs="$1" host="$2" s1port="$3" s2port="$4" subset="$5" want_labels="$6"
  kubectl -n "$NS" get virtualservice "$vs" >/dev/null 2>&1 || fail "VirtualService '$vs' not found in $NS"

  local tg s1g s1sub s1p s2g s2h s2p
  tg=$(kubectl -n "$NS" get virtualservice "$vs" -o jsonpath='{.spec.gateways[*]}' 2>/dev/null)
  grep -qw mesh <<<"$tg" || fail "$vs top-level gateways are [$tg] - 'mesh' is missing"
  grep -q 'egress-gateway' <<<"$tg" || fail "$vs top-level gateways are [$tg] - the gateway is missing"

  # With sourceLabels, stage 1 must not pin gateways: [mesh] - on 1.30.5 that
  # combination makes Istio drop the label predicate and divert every sidecar.
  # Without sourceLabels, [mesh] is the correct and expected scoping.
  s1g=$(kubectl -n "$NS" get virtualservice "$vs" -o jsonpath='{.spec.http[0].match[0].gateways[0]}' 2>/dev/null)
  if [[ "$want_labels" == "yes" ]]; then
    [[ -z "$s1g" ]] \
      || fail "$vs stage 1 pins gateways '[$s1g]' alongside sourceLabels, which disables the label filter - match on the port and sourceLabels only"
  else
    [[ "$s1g" == "mesh" ]] || fail "$vs stage 1 matches gateways '[$s1g]', expected [mesh]"
  fi
  s1p=$(kubectl -n "$NS" get virtualservice "$vs" -o jsonpath='{.spec.http[0].match[0].port}' 2>/dev/null)
  [[ "$s1p" == "$s1port" ]] || fail "$vs stage 1 matches port '$s1p', expected $s1port"
  s1sub=$(kubectl -n "$NS" get virtualservice "$vs" -o jsonpath='{.spec.http[0].route[0].destination.subset}' 2>/dev/null)
  [[ "$s1sub" == "$subset" ]] || fail "$vs stage 1 routes to subset '$s1sub', expected $subset"

  if [[ "$want_labels" == "yes" ]]; then
    local sl
    sl=$(kubectl -n "$NS" get virtualservice "$vs" -o jsonpath='{.spec.http[0].match[0].sourceLabels.egress-allowed}' 2>/dev/null)
    [[ "$sl" == "true" ]] || fail "$vs stage 1 does not match sourceLabels egress-allowed=\"true\" (found '$sl')"
  fi

  s2g=$(kubectl -n "$NS" get virtualservice "$vs" -o jsonpath='{.spec.http[1].match[0].gateways[0]}' 2>/dev/null)
  grep -q 'egress-gateway' <<<"$s2g" || fail "$vs stage 2 matches gateways '[$s2g]', expected the gateway"
  s2h=$(kubectl -n "$NS" get virtualservice "$vs" -o jsonpath='{.spec.http[1].route[0].destination.host}' 2>/dev/null)
  [[ "$s2h" == "$host" ]] || fail "$vs stage 2 routes to host '$s2h', expected $host"
  s2p=$(kubectl -n "$NS" get virtualservice "$vs" -o jsonpath='{.spec.http[1].route[0].destination.port.number}' 2>/dev/null)
  [[ "$s2p" == "$s2port" ]] || fail "$vs stage 2 routes to port '$s2p', expected $s2port"
}
check_vs plain-through-egress  "$PLAIN_HOST" 8080 8080 plain  yes
check_vs secure-through-egress "$SEC_HOST"   8081 8443 secure no

# --- 5. the origination DestinationRule on the EXTERNAL host ---------------
DR=originate-tls-for-secure
kubectl -n "$NS" get destinationrule "$DR" >/dev/null 2>&1 || fail "DestinationRule '$DR' not found in $NS"
dh=$(kubectl -n "$NS" get destinationrule "$DR" -o jsonpath='{.spec.host}' 2>/dev/null)
[[ "$dh" == "$SEC_HOST" ]] \
  || fail "the origination DestinationRule targets '$dh', expected $SEC_HOST. Policy is applied by the proxy CALLING that host - the gateway"
top=$(kubectl -n "$NS" get destinationrule "$DR" -o jsonpath='{.spec.trafficPolicy.tls.mode}' 2>/dev/null)
[[ -z "$top" ]] || fail "the origination DestinationRule sets tls at the top level (mode '$top') - it belongs under portLevelSettings"
plp=$(kubectl -n "$NS" get destinationrule "$DR" -o jsonpath='{.spec.trafficPolicy.portLevelSettings[0].port.number}' 2>/dev/null)
pls=$(kubectl -n "$NS" get destinationrule "$DR" -o jsonpath='{.spec.trafficPolicy.portLevelSettings[0].tls.sni}' 2>/dev/null)
[[ "$plp" == "8443" ]]      || fail "portLevelSettings port is '$plp', expected 8443"
[[ "$pls" == "$SEC_HOST" ]] || fail "the tls sni is '$pls', expected $SEC_HOST"

# --- 6. live: plain host, from the permitted workload -----------------------
before=$(gw_lines "$PLAIN_HOST")
code=$(kubectl -n "$NS" exec deploy/tester -- curl -s -o /dev/null -w '%{http_code}' --max-time 20 "http://${PLAIN_HOST}:8080/get" 2>/dev/null)
sleep 3
after=$(gw_lines "$PLAIN_HOST")
[[ "$code" == "200" ]] || fail "the plain call from tester returned '$code', expected 200"
[[ $((after - before)) -ge 1 ]] \
  || fail "the gateway logged nothing for $PLAIN_HOST after a call from tester - the traffic went direct. Check stage 1 and the sourceLabels"

# --- 7. live: secure host, TLS originated at the gateway --------------------
before=$(gw_lines "$SEC_HOST")
body=$(kubectl -n "$NS" exec deploy/tester -- curl -s --max-time 20 "http://${SEC_HOST}:8081/" 2>/dev/null)
code=$(kubectl -n "$NS" exec deploy/tester -- curl -s -o /dev/null -w '%{http_code}' --max-time 20 "http://${SEC_HOST}:8081/" 2>/dev/null)
sleep 3
after=$(gw_lines "$SEC_HOST")

[[ "$code" == "200" ]] \
  || fail "the secure call from tester returned '$code', expected 200. That endpoint speaks only TLS, so plaintext reaching it fails"
grep -q 'scheme=https' <<<"$body" \
  || fail "the secure endpoint reported '$body', expected 'scheme=https' - TLS was not originated"
[[ $((after - before)) -ge 1 ]] \
  || fail "the gateway logged nothing for $SEC_HOST - the traffic did not go through the gateway"
kubectl -n istio-system logs deploy/istio-egressgateway --tail=30 2>/dev/null \
  | grep "$SEC_HOST" | tail -1 | grep -q ':8443' \
  || fail "the gateway's log line for $SEC_HOST shows no upstream on 8443 - stage 2 is routing to the wrong port"

# --- 8. other-client is un-diverted, not blocked ----------------------------
before=$(gw_lines "$PLAIN_HOST")
code=$(kubectl -n "$NS" exec deploy/other-client -- curl -s -o /dev/null -w '%{http_code}' --max-time 20 "http://${PLAIN_HOST}:8080/get" 2>/dev/null)
sleep 3
after=$(gw_lines "$PLAIN_HOST")
[[ "$code" == "200" ]] \
  || fail "the plain call from other-client returned '$code', expected 200 - sourceLabels narrows the route, not the permission"
[[ $((after - before)) -eq 0 ]] \
  || fail "the gateway logged $((after - before)) line(s) for a call from other-client, which does not carry egress-allowed=true"

# --- 9. the TLS context is on the gateway, not the sidecar ------------------
gw_tls=$(istioctl proxy-config cluster deploy/istio-egressgateway -n istio-system --fqdn "$SEC_HOST" -o json 2>/dev/null | grep -c transportSocket)
sc_tls=$(istioctl proxy-config cluster deploy/tester -n "$NS" --fqdn "$SEC_HOST" -o json 2>/dev/null | grep -c transportSocket)
[[ "$gw_tls" -ge 1 ]] || fail "the GATEWAY proxy has no transportSocket for $SEC_HOST - origination did not take effect there"
[[ "$sc_tls" -eq 0 ]] || fail "the TESTER sidecar has a transportSocket for $SEC_HOST ($sc_tls) - the sidecar should only speak plain HTTP to the gateway"

echo "PASS: one egress gateway carries both partners - $PLAIN_HOST over plain HTTP restricted to egress-allowed workloads, and $SEC_HOST with TLS originated at the gateway (scheme=https, upstream 8443); other-client reached the plain endpoint directly with no gateway line; transportSocket is on the gateway ($gw_tls) and not the sidecar ($sc_tls)"
exit 0
