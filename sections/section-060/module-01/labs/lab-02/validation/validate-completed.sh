#!/usr/bin/env bash
# Confirms the starfleet-gateway Gateway selects the real gateway pods, that the
# gateway proxy now holds a port 80 listener and the bridge routes, that the
# VirtualService was left alone, and - the part that matters - that live
# requests through the ingress gateway reach the bridge.

set -u

NS="starfleet"
GW_NS="istio-ingress"
GW="starfleet-gateway"
HOST="starfleet.example.com"
GATE="http://istio-ingress.istio-ingress.svc.cluster.local:80"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is still what the lab handed over -------------------
for d in bridge-v1 cargo-v1 navcom-v1 scout-v1 scout-v2 scout-v3 shuttle; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the deployments alone: the fix belongs in the Gateway"
done
gw_label=$(kubectl -n "$GW_NS" get deployment istio-ingress -o jsonpath='{.spec.template.metadata.labels.istio}' 2>/dev/null)
[[ "$gw_label" == "ingress" ]] || fail "the gateway Deployment istio-ingress in $GW_NS now labels its pods istio='$gw_label'. Leave the gateway pods alone: fix the Gateway selector instead"

# --- 1. the Gateway -------------------------------------------------------------
kubectl -n "$NS" get gateway "$GW" >/dev/null 2>&1 \
  || fail "Gateway '$GW' not found in $NS - keep its name and namespace, the VirtualService links to it"

selector=$(kubectl -n "$NS" get gateway "$GW" -o jsonpath='{.spec.selector}' 2>/dev/null)
[[ -n "$selector" ]] || fail "Gateway '$GW' has no selector"
sel_args=$(kubectl -n "$NS" get gateway "$GW" -o go-template='{{range $k, $v := .spec.selector}}{{$k}}={{$v}},{{end}}' 2>/dev/null | sed 's/,$//')
pods=$(kubectl -n "$GW_NS" get pods -l "$sel_args" -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$pods" -ge 1 ]] || fail "the Gateway selector [$sel_args] matches no pod in $GW_NS. Compare it with the gateway pod's labels: kubectl get pods -n $GW_NS -L istio"

ports=$(kubectl -n "$NS" get gateway "$GW" -o jsonpath='{range .spec.servers[*]}{.port.number}/{.port.protocol};{end}' 2>/dev/null)
[[ "$ports" == "80/HTTP;" ]] || fail "the Gateway servers are [$ports], expected exactly one server on port 80 with protocol HTTP"
hosts=$(kubectl -n "$NS" get gateway "$GW" -o jsonpath='{.spec.servers[0].hosts[*]}' 2>/dev/null)
[[ "$hosts" == "$HOST" ]] || fail "the Gateway hosts are [$hosts], expected exactly $HOST (no *)"

# --- 2. the VirtualService was left unchanged --------------------------------
kubectl -n "$NS" get virtualservice bridge >/dev/null 2>&1 \
  || fail "VirtualService 'bridge' not found in $NS - it was correct, leave it in place"
vs=$(kubectl -n "$NS" get virtualservice bridge -o jsonpath='{.spec.hosts[*]}|{.spec.gateways[*]}|{.spec.http[0].route[0].destination.host}:{.spec.http[0].route[0].destination.port.number}' 2>/dev/null)
[[ "$vs" == "$HOST|$GW|bridge:9080" ]] || fail "the VirtualService changed (found '$vs'). It must still serve $HOST, link to $GW and route to bridge on port 9080 - the fault is in the Gateway"

# --- 3. the gateway proxy holds the listener and the routes -----------------
ok=""
for i in $(seq 1 30); do
  if istioctl proxy-config listener deploy/istio-ingress -n "$GW_NS" --port 80 2>/dev/null | grep -q 'http.80' \
     && istioctl proxy-config routes deploy/istio-ingress -n "$GW_NS" 2>/dev/null | grep -q "$HOST.*bridge.$NS"; then
    ok=1; break
  fi
  sleep 2
done
[[ -n "$ok" ]] || fail "the gateway proxy has no port 80 listener with the bridge routes for $HOST. Check: istioctl proxy-config listener deploy/istio-ingress -n $GW_NS"

# --- 4. live requests through the ingress gateway ---------------------------
status() {  # $1 = Host header, $2 = path; prints the status code (000 = no reply)
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
[[ "$good" -eq 10 ]] || fail "only $good of 10 requests to /productpage with Host: $HOST got 200 through the ingress gateway (last answer: $(status "$HOST" /productpage)). Compare the Gateway selector with the gateway pod labels: kubectl get pods -n $GW_NS -L istio"

other=$(status other.example.com /productpage)
[[ "$other" != "200" ]] || fail "a request with Host: other.example.com got 200 - the ingress gateway must only serve $HOST"

echo "PASS: the Gateway selects the gateway pods, the gateway proxy listens on port 80 with the bridge routes, the VirtualService is unchanged, 10 of 10 requests reach the bridge through the ingress gateway and other hosts are not served"
exit 0
