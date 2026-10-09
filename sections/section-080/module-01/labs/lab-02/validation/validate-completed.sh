#!/usr/bin/env bash
# Confirms the shuttle's requests to relay.outpost.example really go through the
# egress gateway: the call returns 200, the gateway's own
# access log gains a line for it, and the shuttle's route for the relay points
# at the gateway Service. The ServiceEntry, the DestinationRule and the relay
# must be left as the lab handed them over.

set -u

NS="starfleet"
HOST="relay.outpost.example"
GWSVC="istio-egress.istio-egress.svc.cluster.local"

fail() { echo "FAIL: $*"; exit 1; }

gate_lines() { kubectl -n istio-egress logs deploy/istio-egress --tail=-1 2>/dev/null | grep -c "$HOST"; }
call_relay() {
  kubectl -n "$NS" exec deploy/shuttle -- \
    curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://${HOST}:8080/get" 2>/dev/null
}

# --- 0. the environment is still what the lab handed over -------------------
r=$(kubectl -n "$NS" get deployment shuttle -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ -n "$r" && "$r" -ge 1 ]] || fail "the shuttle deployment is missing or has no ready replicas in $NS"
ph=$(kubectl -n outpost get pod relay -o jsonpath='{.status.phase}' 2>/dev/null)
[[ "$ph" == "Running" ]] || fail "outpost/relay is '$ph', expected Running. Leave the outpost namespace alone"
if kubectl -n outpost get svc -o name 2>/dev/null | grep -q .; then
  fail "a Service exists in outpost. That adds the relay to the service registry by another path - fix the route through the egress gateway instead"
fi
g=$(kubectl -n istio-egress get deployment istio-egress -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ -n "$g" && "$g" -ge 1 ]] || fail "the egress gateway istio-egress/istio-egress has no ready replicas"

kubectl -n "$NS" get serviceentry relay >/dev/null 2>&1 \
  || fail "the ServiceEntry 'relay' in $NS is gone. It was correct - put it back"
p=$(kubectl -n "$NS" get serviceentry relay -o jsonpath='{.spec.ports[0].protocol}' 2>/dev/null)
[[ "$p" == "HTTP" ]] || fail "the ServiceEntry 'relay' port protocol is '$p'. It was correct as HTTP - leave it"
ds=$(kubectl -n "$NS" get destinationrule departure-gate-for-relay -o jsonpath='{.spec.subsets[*].name}' 2>/dev/null)
grep -qw relay <<<"$ds" \
  || fail "the DestinationRule 'departure-gate-for-relay' with the subset 'relay' is missing. Stage 1 sends to that subset - without it the shuttle gets 503 NC"

for kind in gateway virtualservice; do
  n=$(kubectl -n "$NS" get "$kind.networking.istio.io" -o name 2>/dev/null | grep -c .)
  [[ "$n" -eq 1 ]] || fail "$n ${kind} objects in $NS, expected exactly one. Fix the existing one instead of adding another"
done
kubectl -n "$NS" get gateway.networking.istio.io departure-gate >/dev/null 2>&1 \
  || fail "the Gateway 'departure-gate' is gone. Fix it instead of replacing it"
kubectl -n "$NS" get virtualservice relay-via-departure-gate >/dev/null 2>&1 \
  || fail "the VirtualService 'relay-via-departure-gate' is gone. Fix it instead of replacing it"

# --- 1. stage 1 reached the shuttle's sidecar --------------------------------
ok=""
for i in $(seq 1 20); do
  istioctl proxy-config routes deploy/shuttle -n "$NS" --name 8080 -o json 2>/dev/null \
    | grep -q "outbound|80|relay|${GWSVC}" && { ok=1; break; }
  sleep 2
done
[[ -n "$ok" ]] \
  || fail "the shuttle's route for $HOST does not point at the egress gateway (istioctl proxy-config routes deploy/shuttle -n $NS --name 8080 -o json). Stage 1 never reached the sidecars - which proxies does the VirtualService's top-level gateways list name?"

# --- 2. live requests go through the egress gateway -------------------------
before=$(gate_lines)
code=""
for i in $(seq 1 15); do
  code=$(call_relay)
  [[ "$code" == "200" ]] && break
  sleep 2
done
if [[ "$code" == "404" ]]; then
  fail "GET http://${HOST}:8080/get from the shuttle returned 404. Read the gateway's access log (kubectl logs -n istio-egress deploy/istio-egress --tail=1): NR means the gateway has no route for $HOST. Read the Gateway's servers[].hosts from the gateway's point of view - which host will it serve?"
fi
[[ "$code" == "200" ]] || fail "GET http://${HOST}:8080/get from the shuttle returned '$code', expected 200. Read the shuttle's and the gateway's access logs"
sleep 3
after=$(gate_lines)
[[ $((after - before)) -ge 1 ]] \
  || fail "the call returned 200, but the gateway's access log has no new line for $HOST. The request went direct, not through the egress gateway"

hosts=$(kubectl -n "$NS" get gateway.networking.istio.io departure-gate -o jsonpath='{.spec.servers[*].hosts[*]}' 2>/dev/null)
grep -qw "$HOST" <<<"$hosts" || fail "the Gateway's servers[].hosts are [$hosts], expected $HOST"

echo "PASS: the shuttle's route for $HOST points at the egress gateway, a live call returned 200, and the gateway's own access log recorded it - the request left the mesh through the egress gateway"
exit 0
