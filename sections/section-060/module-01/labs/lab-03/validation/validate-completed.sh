#!/usr/bin/env bash
# Confirms the arrival gate is repaired: the Gateway serves exactly
# starfleet.example.com, the bridge VirtualService is linked to it and routes to
# the real bridge, the gateway proxy holds the routes with a healthy bridge
# endpoint, and - the part that matters - live signals through the gate reach
# the bridge while other hosts and unknown paths are not served.

set -u

NS="starfleet"
GW_NS="istio-ingress"
GW="starfleet-gateway"
HOST="starfleet.example.com"
GATE="http://istio-ingress.istio-ingress.svc.cluster.local:80"
CLUSTER="outbound|9080||bridge.starfleet.svc.cluster.local"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is still what the lab handed over -------------------
for d in bridge-v1 cargo-v1 navcom-v1 scout-v1 scout-v2 scout-v3 shuttle; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the ships alone: the faults are in the Gateway and the VirtualService"
done
deploy_count=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$deploy_count" -eq 7 ]] || fail "$NS holds $deploy_count deployments, expected exactly 7 - do not add or remove ships"
kubectl -n "$NS" get service bridge >/dev/null 2>&1 || fail "Service bridge not found in $NS - leave the Services alone"
for s in $(kubectl -n "$NS" get services -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  [[ "$s" == "bridges" ]] && fail "a Service named 'bridges' exists in $NS. Do not create a ship to match the typo: point the flight plan at the real bridge"
done
gw_label=$(kubectl -n "$GW_NS" get deployment istio-ingress -o jsonpath='{.spec.template.metadata.labels.istio}' 2>/dev/null)
[[ "$gw_label" == "ingress" ]] || fail "the gateway Deployment istio-ingress now labels its pods istio='$gw_label'. Leave the gateway pods alone"

# --- 1. the Gateway -------------------------------------------------------------
kubectl -n "$NS" get gateway "$GW" >/dev/null 2>&1 \
  || fail "Gateway '$GW' not found in $NS - keep its name and namespace"
sel=$(kubectl -n "$NS" get gateway "$GW" -o jsonpath='{.spec.selector.istio}' 2>/dev/null)
[[ "$sel" == "ingress" ]] || fail "the Gateway selector is istio='$sel'; the gateway pods carry istio=ingress"
ports=$(kubectl -n "$NS" get gateway "$GW" -o jsonpath='{range .spec.servers[*]}{.port.number}/{.port.protocol};{end}' 2>/dev/null)
[[ "$ports" == "80/HTTP;" ]] || fail "the Gateway servers are [$ports], expected exactly one server on port 80 with protocol HTTP"
hosts=$(kubectl -n "$NS" get gateway "$GW" -o jsonpath='{.spec.servers[0].hosts[*]}' 2>/dev/null)
[[ "$hosts" == "$HOST" ]] || fail "the Gateway hosts are [$hosts], expected exactly $HOST (no *). Read the host letter by letter: istioctl analyze warns with IST0132 when the two host lists do not overlap"

# --- 2. the VirtualService ---------------------------------------------------
kubectl -n "$NS" get virtualservice bridge >/dev/null 2>&1 \
  || fail "VirtualService 'bridge' not found in $NS - repair it, do not replace it with another name"
vs_hosts=$(kubectl -n "$NS" get virtualservice bridge -o jsonpath='{.spec.hosts[*]}' 2>/dev/null)
[[ "$vs_hosts" == "$HOST" ]] || fail "the VirtualService hosts are [$vs_hosts], expected exactly $HOST"
gws=$(kubectl -n "$NS" get virtualservice bridge -o jsonpath='{.spec.gateways[*]}' 2>/dev/null)
case " $gws " in
  *" $GW "*|*" $NS/$GW "*) ;;
  *) fail "the VirtualService gateways field is [$gws]. Without starfleet-gateway in it, the routes go to mesh (the sidecars) and the gate answers 404 NR" ;;
esac
dests=$(kubectl -n "$NS" get virtualservice bridge -o jsonpath='{range .spec.http[*]}{range .route[*]}{.destination.host}:{.destination.port.number};{end}{end}' 2>/dev/null)
for d in ${dests//;/ }; do
  case "$d" in
    bridge:9080|bridge.$NS:9080|bridge.$NS.svc:9080|bridge.$NS.svc.cluster.local:9080) ;;
    *) fail "the VirtualService sends signals to '$d'. Every route must go to the bridge on port 9080; a missing destination gives 503 NC and istioctl analyze IST0101 Referenced host not found" ;;
  esac
done

# --- 3. the gateway proxy holds the routes and a healthy bridge endpoint ------
ok=""
for i in $(seq 1 30); do
  if istioctl proxy-config routes deploy/istio-ingress -n "$GW_NS" 2>/dev/null | grep -q "$HOST.*/productpage.*bridge.$NS"; then
    ok=1; break
  fi
  sleep 2
done
[[ -n "$ok" ]] || fail "the gateway proxy's route table has no /productpage route for $HOST from bridge.$NS. Check: istioctl proxy-config routes deploy/istio-ingress -n $GW_NS"
istioctl proxy-config endpoints deploy/istio-ingress -n "$GW_NS" --cluster "$CLUSTER" 2>/dev/null | grep -q HEALTHY \
  || fail "the gateway proxy has no healthy endpoint in $CLUSTER"

# --- 4. live signals through the gate ---------------------------------------
status() {  # $1 = Host header, $2 = path; prints the status code
  kubectl -n "$NS" exec deploy/shuttle -- curl -s -o /dev/null --max-time 10 \
    -w '%{http_code}' -H "Host: $1" "$GATE$2" 2>/dev/null || true
}

for i in $(seq 1 30); do
  [[ "$(status "$HOST" /productpage)" == "200" ]] && break
  sleep 2
done

good=0
for i in $(seq 1 10); do
  [[ "$(status "$HOST" /productpage)" == "200" ]] && good=$((good + 1))
done
last=$(status "$HOST" /productpage)
[[ "$good" -eq 10 ]] || fail "only $good of 10 signals to /productpage with Host: $HOST got 200 through the gate (last answer: $last). 404 points at hosts and gateways:, 503 at the destination"

api=$(status "$HOST" /api/v1/products)
[[ "$api" == "200" ]] || fail "/api/v1/products with Host: $HOST got $api, expected 200 - keep all the bridge paths in the flight plan"

other=$(status other.example.com /productpage)
[[ "$other" != "200" ]] || fail "a signal with Host: other.example.com got 200 - the gate must only serve $HOST"
unknown=$(status "$HOST" /admin)
[[ "$unknown" == "404" ]] || fail "/admin with Host: $HOST got $unknown, expected 404 - do not add a catch-all route"

echo "PASS: the Gateway serves only $HOST, the bridge flight plan is linked to it and routes to the real bridge, the gateway proxy holds the routes with a healthy endpoint, 10 of 10 signals reach the bridge and other hosts and paths are not served"
exit 0
