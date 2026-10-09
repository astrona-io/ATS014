#!/usr/bin/env bash
# Confirms the ingress class `istio` names Istio's controller, that the Ingress
# was left alone and is still claimed by that class, that nothing was routed
# around it with Istio's own objects, and - the part that matters - that live
# requests through the ingress gateway reach the probe (HTTP echo server).

set -u

NS="starfleet"
HOST="starfleet.example.com"
GATE="http://istio-ingressgateway.istio-system"
CONTROLLER="istio.io/ingress-controller"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is still what the lab handed over -------------------
for d in probe-v1 probe-v2 shuttle; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the deployments alone: the fault is in the ingress class"
done

port=$(kubectl -n "$NS" get service probe -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
[[ "$port" == "8000" ]] || fail "Service probe in $NS should listen on port 8000 (found '$port'). Leave the Services unchanged"

gate_ready=$(kubectl -n istio-system get deployment istio-ingressgateway -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ -n "$gate_ready" && "$gate_ready" -ge 1 ]] || fail "the ingress gateway istio-ingressgateway in istio-system has no ready pod. Leave the gateway installed as it was"

# --- 1. the IngressClass --------------------------------------------------------
kubectl get ingressclass istio >/dev/null 2>&1 \
  || fail "IngressClass 'istio' not found. The Ingress names it in ingressClassName, so it must exist"

ctrl=$(kubectl get ingressclass istio -o jsonpath='{.spec.controller}' 2>/dev/null)
[[ "$ctrl" == "$CONTROLLER" ]] || fail "IngressClass 'istio' names the controller '$ctrl', but istiod only serves '$CONTROLLER'. spec.controller cannot be edited: delete the IngressClass and create it again"

# --- 2. the Ingress was left unchanged ------------------------------------------
kubectl -n "$NS" get ingress starfleet >/dev/null 2>&1 \
  || fail "Ingress 'starfleet' not found in $NS - it was correct, leave it in place"

cls=$(kubectl -n "$NS" get ingress starfleet -o jsonpath='{.spec.ingressClassName}' 2>/dev/null)
[[ "$cls" == "istio" ]] || fail "Ingress 'starfleet' has ingressClassName '$cls', expected 'istio'. Fix the class, not the Ingress"

rule=$(kubectl -n "$NS" get ingress starfleet -o jsonpath='{.spec.rules[0].host}|{.spec.rules[0].http.paths[0].path}|{.spec.rules[0].http.paths[0].pathType}|{.spec.rules[0].http.paths[0].backend.service.name}|{.spec.rules[0].http.paths[0].backend.service.port.number}' 2>/dev/null)
[[ "$rule" == "$HOST|/anything|Prefix|probe|8000" ]] || fail "the Ingress rule changed (found '$rule'). It must still send $HOST /anything (Prefix) to probe:8000 - the fault is in the IngressClass"

nrules=$(kubectl -n "$NS" get ingress starfleet -o jsonpath='{range .spec.rules[*]}{range .http.paths[*]}x{end}{end}' 2>/dev/null)
[[ "$nrules" == "x" ]] || fail "the Ingress should hold exactly one path. Leave it unchanged"

# --- 3. nothing routed around the Ingress ----------------------------------------
others=$(kubectl get gateways.networking.istio.io,virtualservices.networking.istio.io -A -o name 2>/dev/null)
[[ -z "$others" ]] || fail "found Istio routing objects: $(echo $others). The task is to make the ingress gateway serve the Ingress itself - remove the Gateway / VirtualService"

# --- 4. live requests through the ingress gateway -------------------------------
code() {  # $1 = path; prints the status code the ingress gateway returns for it
  kubectl -n "$NS" exec deploy/shuttle -- curl -s -o /dev/null --max-time 5 \
    -w '%{http_code}' -H "Host: $HOST" "$GATE$1" 2>/dev/null || echo "000"
}

for i in $(seq 1 30); do
  [[ "$(code /anything/dock/1)" == "200" ]] && break
  sleep 2
done

ok=0
for i in $(seq 1 5); do
  [[ "$(code /anything/dock/$i)" == "200" ]] && ok=$((ok + 1))
done
last=$(code /anything/dock/1)
[[ "$ok" -eq 5 ]] || fail "$ok of 5 requests to $HOST/anything/dock/N through the ingress gateway got 200 (last code: $last). A 503 from the shuttle (connection refused in its access log) means the ingress gateway has no listener on port 80: no controller serves the Ingress yet. Check kubectl get ingress -n $NS - the CLASS column - and the IngressClass controller"

outside=$(code /status/200)
[[ "$outside" == "404" ]] || fail "a request to $HOST/status/200 got '$outside', expected 404 from the ingress gateway: only /anything is routed. Leave the Ingress unchanged"

echo "PASS: IngressClass istio names $CONTROLLER, the Ingress is unchanged and claimed by it, no Gateway or VirtualService exists, and 5 of 5 requests through the ingress gateway reach the probe"
exit 0
