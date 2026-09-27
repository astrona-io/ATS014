#!/usr/bin/env bash
# Confirms the mesh is still REGISTRY_ONLY, that a ServiceEntry registers ONLY
# the partner endpoint with the required location/resolution/exportTo, that the
# declared HTTP protocol lets a VirtualService timeout apply, and that the
# second endpoint remains refused.

set -u

NS="egress-demo"
SE="partner-api"

fail() { echo "FAIL: $*"; exit 1; }

PARTNER_IP=$(cat /tmp/partner-ip 2>/dev/null || kubectl -n outside-mesh get pod partner-api -o jsonpath='{.status.podIP}' 2>/dev/null)
FORBIDDEN_IP=$(cat /tmp/forbidden-ip 2>/dev/null || kubectl -n outside-mesh get pod forbidden-api -o jsonpath='{.status.podIP}' 2>/dev/null)
[[ -n "$PARTNER_IP"   ]] || fail "could not determine the partner-api pod address"
[[ -n "$FORBIDDEN_IP" ]] || fail "could not determine the forbidden-api pod address"

from_tester() {
  kubectl -n "$NS" exec deploy/tester -- \
    curl -s -o /dev/null -w "$1" --max-time 20 "$2" 2>/dev/null
}

# --- 0. the environment is intact -------------------------------------------
r=$(kubectl -n "$NS" get deployment tester -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ -n "$r" && "$r" -ge 1 ]] || fail "tester - deployment missing or has no ready replicas"
for p in partner-api forbidden-api; do
  ph=$(kubectl -n outside-mesh get pod "$p" -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$ph" == "Running" ]] || fail "outside-mesh/$p is '$ph', expected Running"
done
if kubectl -n outside-mesh get svc -o name 2>/dev/null | grep -q .; then
  fail "a Service exists in outside-mesh. Creating one would put the endpoint in the mesh registry through the back door - the task is to register it with a ServiceEntry"
fi

# --- 1. the mesh is still deny-by-default -----------------------------------
mode=$(kubectl -n istio-system get cm istio -o jsonpath='{.data.mesh}' 2>/dev/null \
  | grep -A2 outboundTrafficPolicy | grep -o 'REGISTRY_ONLY' | head -1)
[[ "$mode" == "REGISTRY_ONLY" ]] \
  || fail "the mesh outboundTrafficPolicy is no longer REGISTRY_ONLY. Do not relax the mesh policy to make the task pass - the point is to allow one host explicitly"

# --- 2. the ServiceEntry ------------------------------------------------------
kubectl -n "$NS" get serviceentry "$SE" >/dev/null 2>&1 \
  || fail "ServiceEntry '$SE' not found in $NS"

hosts=$(kubectl -n "$NS" get serviceentry "$SE" -o jsonpath='{.spec.hosts[*]}' 2>/dev/null)
grep -qw 'partner.example.com' <<<"$hosts" \
  || fail "the ServiceEntry hosts are [$hosts] - partner.example.com is missing"

addrs=$(kubectl -n "$NS" get serviceentry "$SE" -o jsonpath='{.spec.addresses[*]}' 2>/dev/null)
grep -q "$PARTNER_IP" <<<"$addrs" \
  || fail "the ServiceEntry addresses are [$addrs] - the partner address $PARTNER_IP is missing. Without it the sidecar cannot match traffic aimed at that IP to this entry"
grep -q "$FORBIDDEN_IP" <<<"$addrs" \
  && fail "the ServiceEntry addresses include $FORBIDDEN_IP - the forbidden endpoint must not be registered"

pnum=$(kubectl -n "$NS" get serviceentry "$SE" -o jsonpath='{.spec.ports[0].number}' 2>/dev/null)
pproto=$(kubectl -n "$NS" get serviceentry "$SE" -o jsonpath='{.spec.ports[0].protocol}' 2>/dev/null)
[[ "$pnum" == "8080" ]]  || fail "the ServiceEntry port number is '$pnum', expected 8080"
[[ "$pproto" == "HTTP" ]] \
  || fail "the ServiceEntry port protocol is '$pproto', expected HTTP. With TCP you get a working connection and no layer-7 features, so the timeout in step 7 could never apply"

loc=$(kubectl -n "$NS" get serviceentry "$SE" -o jsonpath='{.spec.location}' 2>/dev/null)
res=$(kubectl -n "$NS" get serviceentry "$SE" -o jsonpath='{.spec.resolution}' 2>/dev/null)
[[ "$loc" == "MESH_EXTERNAL" ]] || fail "location is '$loc', expected MESH_EXTERNAL"
[[ "$res" == "STATIC" ]]        || fail "resolution is '$res', expected STATIC"

ep=$(kubectl -n "$NS" get serviceentry "$SE" -o jsonpath='{.spec.endpoints[0].address}' 2>/dev/null)
[[ "$ep" == "$PARTNER_IP" ]] \
  || fail "the endpoints[0].address is '$ep', expected $PARTNER_IP. resolution STATIC needs the address listed under endpoints"

exp=$(kubectl -n "$NS" get serviceentry "$SE" -o jsonpath='{.spec.exportTo[*]}' 2>/dev/null)
[[ "$exp" == "." ]] \
  || fail "exportTo is [$exp], expected [\".\"]. A ServiceEntry is exported mesh-wide by default, so one namespace's allow-list silently becomes everyone's"

# --- 3. the host reached the proxy ------------------------------------------
clusters=$(istioctl proxy-config cluster deploy/tester -n "$NS" 2>/dev/null)
grep -q 'partner.example.com' <<<"$clusters" \
  || fail "partner.example.com does not appear in the tester proxy's cluster list - the ServiceEntry exists but never reached the sidecar"

# --- 4. the VirtualService ----------------------------------------------------
kubectl -n "$NS" get virtualservice "$SE" >/dev/null 2>&1 \
  || fail "VirtualService '$SE' not found in $NS"
vh=$(kubectl -n "$NS" get virtualservice "$SE" -o jsonpath='{.spec.hosts[*]}' 2>/dev/null)
grep -qw 'partner.example.com' <<<"$vh" \
  || fail "the VirtualService hosts are [$vh] - partner.example.com is missing"
vt=$(kubectl -n "$NS" get virtualservice "$SE" -o jsonpath='{.spec.http[0].timeout}' 2>/dev/null)
[[ "$vt" == "2s" ]] || fail "the VirtualService timeout is '$vt', expected 2s"

# --- 5. live: the partner endpoint is reachable -----------------------------
c=$(from_tester '%{http_code}' "http://${PARTNER_IP}:8080/get")
[[ "$c" == "200" ]] \
  || fail "GET http://${PARTNER_IP}:8080/get returned '$c', expected 200. A 502 means the sidecar still has no cluster for that destination - check spec.addresses"

# --- 6. live: the forbidden endpoint is still refused -----------------------
c=$(from_tester '%{http_code}' "http://${FORBIDDEN_IP}:8080/get")
[[ "$c" == "200" ]] \
  && fail "GET http://${FORBIDDEN_IP}:8080/get returned 200. Registering one endpoint must not open the other - check that the ServiceEntry lists only the partner address"

# --- 7. live: the timeout applies to the registered host --------------------
res2=$(from_tester '%{http_code} %{time_total}' "http://${PARTNER_IP}:8080/delay/5")
code=${res2%% *}; took=${res2##* }
[[ "$code" == "504" ]] \
  || fail "GET /delay/5 returned '$code', expected 504. The VirtualService timeout is not applying - this only works when the ServiceEntry port is declared HTTP"
inwindow=$(python3 -c "print(1 if 1.2 <= ${took:-0} <= 4.0 else 0)" 2>/dev/null)
[[ "$inwindow" == "1" ]] \
  || fail "GET /delay/5 returned 504 after ${took}s, expected roughly 2s"

echo "PASS: mesh still REGISTRY_ONLY; ServiceEntry registers partner.example.com (MESH_EXTERNAL, STATIC, exportTo '.') for ${PARTNER_IP}:8080 only; the partner endpoint returns 200, the forbidden one is still refused, and a 2s VirtualService timeout fired at ${took}s on the registered host"
exit 0
