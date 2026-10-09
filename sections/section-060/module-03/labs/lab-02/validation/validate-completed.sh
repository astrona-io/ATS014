#!/usr/bin/env bash
# Confirms the Gateway API Gateway the waiting HTTPRoute needs: the istio
# class, one HTTP listener on port 80 for starfleet.example.com, a proxy that
# Istio built in starfleet, healthy conditions on the Gateway and the route,
# the route left unchanged, and - the part that matters - live signals from
# the shuttle that reach the bridge through the new gate.

set -u

NS="starfleet"
GW="starfleet-gateway"
HOST="starfleet.example.com"
GW_URL="http://${GW}-istio.${NS}"

fail() { echo "FAIL: $*"; exit 1; }

cond() {  # cond <kind> <name> <jsonpath to a conditions list> <type>
  kubectl -n "$NS" get "$1" "$2" \
    -o jsonpath="{range $3[?(@.type=='$4')]}{.status}{end}" 2>/dev/null
}

# --- 0. the environment is still what the lab handed over -------------------
for d in bridge-v1 cargo-v1 navcom-v1 scout-v1 scout-v2 scout-v3 shuttle; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the ships alone: the task is the Gateway"
done
kubectl get gatewayclass istio >/dev/null 2>&1 \
  || fail "GatewayClass 'istio' not found - Istio has not registered its class, so nothing can build a gate"

# --- 1. the waiting HTTPRoute is unchanged -----------------------------------
kubectl -n "$NS" get httproute bridge >/dev/null 2>&1 \
  || fail "HTTPRoute 'bridge' not found in $NS - it was correct, leave it in place"
route=$(kubectl -n "$NS" get httproute bridge -o jsonpath='{.spec.parentRefs[0].name}|{.spec.hostnames[*]}|{.spec.rules[0].matches[0].path.value}|{.spec.rules[0].backendRefs[0].name}:{.spec.rules[0].backendRefs[0].port}' 2>/dev/null)
[[ "$route" == "$GW|$HOST|/productpage|bridge:9080" ]] \
  || fail "the HTTPRoute 'bridge' changed (found '$route'). It must still dock at $GW for $HOST and send /productpage to bridge:9080 - build the Gateway to fit the route, not the other way round"

# --- 2. the Gateway -----------------------------------------------------------
kubectl -n "$NS" get gateway "$GW" >/dev/null 2>&1 \
  || fail "Gateway '$GW' not found in $NS. The HTTPRoute 'bridge' names it in parentRefs, so it must have exactly this name and live on the same planet"

gcn=$(kubectl -n "$NS" get gateway "$GW" -o jsonpath='{.spec.gatewayClassName}' 2>/dev/null)
[[ "$gcn" == "istio" ]] || fail "the Gateway's gatewayClassName is '$gcn', expected istio. Only the istio class makes Istio build the gate"

svctype=$(kubectl -n "$NS" get gateway "$GW" -o jsonpath='{.metadata.annotations.networking\.istio\.io/service-type}' 2>/dev/null)
[[ "$svctype" == "ClusterIP" ]] \
  || fail "the Gateway has no annotation networking.istio.io/service-type: ClusterIP (found '$svctype'). This kind cluster has no load balancer, so without it the gate never gets an address"

count=$(kubectl -n "$NS" get gateway "$GW" -o jsonpath='{range .spec.listeners[*]}x{end}' 2>/dev/null)
[[ "$count" == "x" ]] || fail "the Gateway has ${#count} listeners, expected exactly one"

listener=$(kubectl -n "$NS" get gateway "$GW" -o jsonpath='{.spec.listeners[0].name}|{.spec.listeners[0].port}|{.spec.listeners[0].protocol}|{.spec.listeners[0].hostname}' 2>/dev/null)
[[ "$listener" == "http|80|HTTP|$HOST" ]] \
  || fail "the listener is '$listener' (name|port|protocol|hostname), expected 'http|80|HTTP|$HOST'"

from=$(kubectl -n "$NS" get gateway "$GW" -o jsonpath='{.spec.listeners[0].allowedRoutes.namespaces.from}' 2>/dev/null)
[[ -z "$from" || "$from" == "Same" ]] \
  || fail "allowedRoutes.namespaces.from is '$from'. The route lives on the gate's own planet, so keep the default 'Same' and let no other planet dock"

# --- 3. Istio built the gate's proxy in starfleet ---------------------------
ok=""
for _ in $(seq 1 60); do
  ready=$(kubectl -n "$NS" get deployment "${GW}-istio" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] && { ok=1; break; }
  sleep 2
done
[[ -n "$ok" ]] || fail "Deployment ${GW}-istio has no ready pod in $NS. A Gateway API Gateway makes Istio build its proxy on the Gateway's own planet - check 'kubectl describe gateway $GW -n $NS'"
kubectl -n "$NS" get service "${GW}-istio" >/dev/null 2>&1 \
  || fail "Service ${GW}-istio not found in $NS"

extra=$(kubectl -n istio-system get deployments -o name 2>/dev/null | grep -v 'deployment.apps/istiod$' || true)
[[ -z "$extra" ]] || fail "istio-system holds more than istiod ($extra). The gate's proxy belongs in $NS, built from the Gateway - do not install a separate ingress gateway"

# --- 4. the status lights ------------------------------------------------------
for _ in $(seq 1 30); do
  [[ "$(cond gateway "$GW" '.status.conditions' Programmed)" == "True" ]] && break
  sleep 2
done
acc=$(cond gateway "$GW" '.status.conditions' Accepted)
prog=$(cond gateway "$GW" '.status.conditions' Programmed)
[[ "$acc" == "True" ]] || fail "the Gateway reports Accepted=$acc. Run 'kubectl describe gateway $GW -n $NS' - the condition message names the problem"
[[ "$prog" == "True" ]] || fail "the Gateway reports Programmed=$prog. Accepted without Programmed means the YAML is fine but the gate has no address yet - check the service-type annotation. If you deleted and re-created the Gateway within seconds, delete it, wait half a minute and apply it again"

for _ in $(seq 1 30); do
  [[ "$(cond httproute bridge '.status.parents[0].conditions' Accepted)" == "True" ]] && break
  sleep 2
done
ra=$(cond httproute bridge '.status.parents[0].conditions' Accepted)
rr=$(cond httproute bridge '.status.parents[0].conditions' ResolvedRefs)
[[ -n "$ra" ]] || fail "the HTTPRoute 'bridge' has no status from any gate. Its parentRefs names $GW - check the Gateway's name and namespace"
[[ "$ra" == "True" ]] || fail "the HTTPRoute 'bridge' reports Accepted=$ra. Check that the listener's hostname is $HOST and that allowedRoutes lets routes from $NS dock"
[[ "$rr" == "True" ]] || fail "the HTTPRoute 'bridge' reports ResolvedRefs=$rr"

# --- 5. live signals through the gate ------------------------------------------
code_for() {  # code_for <host> <path>
  kubectl -n "$NS" exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
    -H "Host: $1" "${GW_URL}$2" 2>/dev/null
}

code=""
for _ in $(seq 1 30); do
  code=$(code_for "$HOST" /productpage)
  [[ "$code" == "200" ]] && break
  sleep 2
done
[[ "$code" == "200" ]] \
  || fail "GET /productpage with Host $HOST through ${GW}-istio returned '$code', expected 200. Read the gate's flight log: kubectl logs -n $NS deploy/${GW}-istio --tail=5"

good=0
for _ in $(seq 1 10); do
  [[ "$(code_for "$HOST" /productpage)" == "200" ]] && good=$((good + 1))
done
[[ "$good" -eq 10 ]] || fail "only $good of 10 signals to /productpage with Host $HOST returned 200"

other=$(code_for other.example.com /productpage)
[[ "$other" == "404" ]] \
  || fail "GET /productpage with Host other.example.com returned '$other', expected 404. The listener must serve only $HOST"

echo "PASS: Gateway '$GW' uses the istio class with one HTTP listener on port 80 for $HOST, Istio built ${GW}-istio in $NS, the Gateway is Accepted and Programmed, the HTTPRoute 'bridge' docked unchanged, and 10 of 10 signals reach the bridge through the gate"
exit 0
