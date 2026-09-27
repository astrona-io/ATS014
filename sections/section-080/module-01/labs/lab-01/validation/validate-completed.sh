#!/usr/bin/env bash
# Confirms the four objects route external traffic through the egress gateway,
# that the gateway's own log records the request, that the sidecar's route
# points inward, and that a workload not matching sourceLabels is un-diverted
# rather than blocked.

set -u

NS="egwgw-demo"
HOST="partner.example.com"
GWSVC="istio-egressgateway.istio-system.svc.cluster.local"

fail() { echo "FAIL: $*"; exit 1; }

PARTNER=$(cat /tmp/partner-ip 2>/dev/null || kubectl -n outside-mesh get pod partner-api -o jsonpath='{.status.podIP}' 2>/dev/null)
[[ -n "$PARTNER" ]] || fail "could not determine the partner-api address"

gw_lines() { kubectl -n istio-system logs deploy/istio-egressgateway --tail=-1 2>/dev/null | grep -c "$HOST"; }
call_from() {
  kubectl -n "$NS" exec "deploy/$1" -- \
    curl -s -o /dev/null -w '%{http_code}' --max-time 15 "http://${PARTNER}:8080/get" 2>/dev/null
}

# --- 0. the environment is intact -------------------------------------------
for d in tester other-client; do
  r=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$r" && "$r" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas"
done
ph=$(kubectl -n outside-mesh get pod partner-api -o jsonpath='{.status.phase}' 2>/dev/null)
[[ "$ph" == "Running" ]] || fail "outside-mesh/partner-api is '$ph', expected Running"
if kubectl -n outside-mesh get svc -o name 2>/dev/null | grep -q .; then
  fail "a Service exists in outside-mesh - that registers the endpoint through the back door"
fi
gwr=$(kubectl -n istio-system get deployment istio-egressgateway -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ -n "$gwr" && "$gwr" -ge 1 ]] || fail "istio-egressgateway is not ready"

# --- 1. the ServiceEntry ------------------------------------------------------
kubectl -n "$NS" get serviceentry partner >/dev/null 2>&1 || fail "ServiceEntry 'partner' not found in $NS"
h=$(kubectl -n "$NS" get serviceentry partner -o jsonpath='{.spec.hosts[*]}' 2>/dev/null)
grep -qw "$HOST" <<<"$h" || fail "the ServiceEntry hosts are [$h] - $HOST is missing"
a=$(kubectl -n "$NS" get serviceentry partner -o jsonpath='{.spec.addresses[*]}' 2>/dev/null)
grep -q "$PARTNER" <<<"$a" || fail "the ServiceEntry addresses are [$a] - $PARTNER is missing"
p=$(kubectl -n "$NS" get serviceentry partner -o jsonpath='{.spec.ports[0].protocol}' 2>/dev/null)
[[ "$p" == "HTTP" ]] || fail "the ServiceEntry port protocol is '$p', expected HTTP"

# --- 2. the Gateway -----------------------------------------------------------
kubectl -n "$NS" get gateway egress-gateway >/dev/null 2>&1 || fail "Gateway 'egress-gateway' not found in $NS"
sel=$(kubectl -n "$NS" get gateway egress-gateway -o jsonpath='{.spec.selector.istio}' 2>/dev/null)
[[ "$sel" == "egressgateway" ]] \
  || fail "the Gateway selector istio='$sel', expected 'egressgateway' - note this is the EGRESS gateway, not the ingress one"
gh=$(kubectl -n "$NS" get gateway egress-gateway -o jsonpath='{.spec.servers[*].hosts[*]}' 2>/dev/null)
grep -qw "$HOST" <<<"$gh" \
  || fail "the Gateway servers hosts are [$gh] - it must name the EXTERNAL host $HOST. Read the object from the gateway's point of view: which hostnames will it serve?"

# --- 3. the DestinationRule subset -------------------------------------------
kubectl -n "$NS" get destinationrule egressgateway-for-partner >/dev/null 2>&1 \
  || fail "DestinationRule 'egressgateway-for-partner' not found in $NS"
dh=$(kubectl -n "$NS" get destinationrule egressgateway-for-partner -o jsonpath='{.spec.host}' 2>/dev/null)
grep -q 'istio-egressgateway' <<<"$dh" || fail "the DestinationRule host is '$dh', expected the egress gateway Service"
ds=$(kubectl -n "$NS" get destinationrule egressgateway-for-partner -o jsonpath='{.spec.subsets[0].name}' 2>/dev/null)
[[ "$ds" == "partner" ]] || fail "the DestinationRule subset is '$ds', expected 'partner'"

# --- 4. the two-stage VirtualService -----------------------------------------
VS=partner-through-egress
kubectl -n "$NS" get virtualservice "$VS" >/dev/null 2>&1 || fail "VirtualService '$VS' not found in $NS"

tg=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.gateways[*]}' 2>/dev/null)
grep -qw 'mesh' <<<"$tg" \
  || fail "the VirtualService top-level gateways are [$tg] - 'mesh' is missing, so stage 1 is never programmed into sidecars and nothing is diverted"
grep -qE '(^| )(egress-gateway|'"$NS"'/egress-gateway)( |$)' <<<"$tg" \
  || fail "the VirtualService top-level gateways are [$tg] - the gateway is missing, so stage 2 never reaches it"

s1g=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[0].match[0].gateways[0]}' 2>/dev/null)
[[ "$s1g" == "mesh" ]] \
  || fail "the FIRST http rule matches gateways '[$s1g]', expected [mesh]. Stage 1 runs in the sidecars"
s1d=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[0].route[0].destination.host}' 2>/dev/null)
grep -q 'istio-egressgateway' <<<"$s1d" \
  || fail "stage 1 routes to '$s1d', expected the egress gateway Service"
s1s=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[0].route[0].destination.subset}' 2>/dev/null)
[[ "$s1s" == "partner" ]] || fail "stage 1 routes to subset '$s1s', expected 'partner'"
s1l=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[0].match[0].sourceLabels.egress-allowed}' 2>/dev/null)
[[ "$s1l" == "true" ]] \
  || fail "stage 1 does not match sourceLabels egress-allowed=\"true\" (found '$s1l')"

s2g=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[1].match[0].gateways[0]}' 2>/dev/null)
grep -q 'egress-gateway' <<<"$s2g" \
  || fail "the SECOND http rule matches gateways '[$s2g]', expected the gateway name. Stage 2 runs on the gateway"
s2d=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[1].route[0].destination.host}' 2>/dev/null)
[[ "$s2d" == "$HOST" ]] || fail "stage 2 routes to '$s2d', expected $HOST"

# --- 5. the sidecar route points inward --------------------------------------
routes=$(istioctl proxy-config routes deploy/tester -n "$NS" -o json 2>/dev/null)
grep -q 'istio-egressgateway' <<<"$routes" \
  || fail "the tester sidecar has no route to the egress gateway - stage 1 never reached it"

# --- 6. tester goes through the gateway --------------------------------------
before=$(gw_lines)
code=$(call_from tester)
[[ "$code" == "200" ]] || fail "the call from tester returned '$code', expected 200"
sleep 3
after=$(gw_lines)
diverted=$((after - before))
[[ "$diverted" -ge 1 ]] \
  || fail "the gateway logged no line for $HOST after a call from tester. The call succeeded, which proves nothing - it went direct. Check stage 1's sourceLabels and that 'mesh' is in the top-level gateways"

# --- 7. other-client is UN-DIVERTED, not blocked -----------------------------
before=$(gw_lines)
code=$(call_from other-client)
sleep 3
after=$(gw_lines)
other=$((after - before))

[[ "$code" == "200" ]] \
  || fail "the call from other-client returned '$code', expected 200. sourceLabels narrows the ROUTE, not the permission - a non-matching workload should still reach the endpoint directly"
[[ "$other" -eq 0 ]] \
  || fail "the gateway logged $other line(s) for a call from other-client. That workload does not carry egress-allowed=true, so stage 1 must not divert it"

echo "PASS: four objects route $HOST through the egress gateway; a call from tester produced $diverted gateway log line(s) and its sidecar route points at the gateway Service, while other-client still reached the endpoint directly with 0 gateway lines - the route was narrowed, not the permission"
exit 0
