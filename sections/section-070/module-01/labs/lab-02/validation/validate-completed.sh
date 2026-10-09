#!/usr/bin/env bash
# Confirms the starfleet Sidecar still blocks unknown hosts (REGISTRY_ONLY), the
# VirtualService for the relay is unchanged, the relay's ServiceEntry reaches
# the shuttle's sidecar proxy with an HTTP port, and - the part that matters -
# that live requests from the shuttle reach the relay, hit the 2s timeout on a
# slow call, and still cannot reach the rogue.

set -u

NS="starfleet"
HOST="relay.outpost.example"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is still what the lab handed over -------------------
r=$(kubectl -n "$NS" get deployment shuttle -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ -n "$r" && "$r" -ge 1 ]] || fail "the shuttle deployment is missing or has no ready replicas in $NS"
for p in relay rogue; do
  ph=$(kubectl -n outpost get pod "$p" -o jsonpath='{.status.phase}' 2>/dev/null)
  [[ "$ph" == "Running" ]] || fail "outpost/$p is '$ph', expected Running. Leave the outpost namespace alone"
done
if kubectl -n outpost get svc -o name 2>/dev/null | grep -q .; then
  fail "a Service exists in outpost. A Service would add the pods to the service registry by another path - fix the ServiceEntry instead"
fi
RELAY_IP=$(kubectl -n outpost get pod relay -o jsonpath='{.status.podIP}' 2>/dev/null)
ROGUE_IP=$(kubectl -n outpost get pod rogue -o jsonpath='{.status.podIP}' 2>/dev/null)
[[ -n "$RELAY_IP" && -n "$ROGUE_IP" ]] || fail "could not read the relay and rogue pod addresses"

# --- 1. the Sidecar still blocks unknown hosts --------------------------------
kubectl -n "$NS" get sidecar default >/dev/null 2>&1 \
  || fail "the Sidecar 'default' in $NS is gone. It keeps the namespace REGISTRY_ONLY - put it back and fix the route another way"
mode=$(kubectl -n "$NS" get sidecar default -o jsonpath='{.spec.outboundTrafficPolicy.mode}' 2>/dev/null)
[[ "$mode" == "REGISTRY_ONLY" ]] \
  || fail "the Sidecar's outboundTrafficPolicy.mode is '$mode', expected REGISTRY_ONLY. Opening every route out is not the fix"
ehosts=$(kubectl -n "$NS" get sidecar default -o jsonpath='{.spec.egress[*].hosts[*]}' 2>/dev/null)
for h in $ehosts; do
  [[ "$h" == "*/*" ]] && fail "the Sidecar's egress.hosts contains */*, which takes in every namespace. Add only what the shuttle needs"
done
sel=$(kubectl -n "$NS" get sidecar default -o jsonpath='{.spec.workloadSelector}' 2>/dev/null)
[[ -z "$sel" ]] || fail "the Sidecar 'default' now has a workloadSelector. Keep it namespace-wide"
others=$(kubectl -n "$NS" get sidecar -o name 2>/dev/null | grep -v '/default$')
[[ -z "$others" ]] || fail "extra Sidecar objects in $NS: $others. Keep one Sidecar, 'default'"

# --- 2. the VirtualService is unchanged -----------------------------------------
kubectl -n "$NS" get virtualservice relay >/dev/null 2>&1 \
  || fail "the VirtualService 'relay' in $NS is gone. It was correct - leave it in place"
vh=$(kubectl -n "$NS" get virtualservice relay -o jsonpath='{.spec.hosts[*]}' 2>/dev/null)
[[ "$vh" == "$HOST" ]] || fail "the VirtualService hosts changed to [$vh]. Leave the VirtualService unchanged"
vt=$(kubectl -n "$NS" get virtualservice relay -o jsonpath='{.spec.http[0].timeout}' 2>/dev/null)
[[ "$vt" == "2s" ]] || fail "the VirtualService timeout is '$vt', expected 2s. Leave the VirtualService unchanged"

# --- 3. the ServiceEntry -----------------------------------------------------
se=$(kubectl get serviceentry -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {.spec.hosts[*]}{"\n"}{end}' 2>/dev/null \
  | awk -v h="$HOST" '{for (i=2;i<=NF;i++) if ($i==h) print $1}')
n=$(grep -c . <<<"$se")
[[ "$n" -ge 1 ]] || fail "no ServiceEntry for $HOST exists any more. The relay must be registered with a ServiceEntry"
[[ "$n" -eq 1 ]] || fail "$n ServiceEntry objects register $HOST ($(echo $se)). Keep exactly one"
sens=${se%%/*}; sename=${se##*/}
addrs=$(kubectl -n "$sens" get serviceentry "$sename" -o jsonpath='{.spec.addresses[*]} {.spec.endpoints[*].address}' 2>/dev/null)
grep -qw "$ROGUE_IP" <<<"$addrs" && fail "the ServiceEntry $se lists the rogue's address $ROGUE_IP. Only the relay may be registered"

# --- 4. the entry reaches the shuttle's sidecar proxy ------------------------
# A hidden entry leaves the shuttle's proxy with no listener on port 8080 (a
# VirtualService in the namespace can still pull in the cluster, so the cluster
# list alone proves nothing).
ok=""
for i in $(seq 1 30); do
  istioctl proxy-config listener deploy/shuttle -n "$NS" --port 8080 2>/dev/null | grep -q ' 8080 ' && { ok=1; break; }
  sleep 2
done
[[ -n "$ok" ]] || fail "the shuttle's proxy has no listener on port 8080 (istioctl proxy-config listener deploy/shuttle -n $NS --port 8080), so every request to the relay goes to the BlackHoleCluster. The ServiceEntry $se exists, but the shuttle never sees it. Compare where it lives, and its exportTo, with the Sidecar's egress.hosts"

# --- 5. live requests ----------------------------------------------------------
from_shuttle() {
  kubectl -n "$NS" exec deploy/shuttle -- curl -s -o /dev/null -w "$1" --max-time 20 "$2" 2>/dev/null
}

c=""
for i in $(seq 1 15); do
  c=$(from_shuttle '%{http_code}' "http://${RELAY_IP}:8080/get")
  [[ "$c" == "200" ]] && break
  sleep 2
done
[[ "$c" == "200" ]] \
  || fail "GET http://${RELAY_IP}:8080/get from the shuttle returned '$c', expected 200. Read the shuttle's access log: BlackHoleCluster or block_all means the relay is still not in its service registry"

proto=$(kubectl -n "$sens" get serviceentry "$sename" -o jsonpath='{.spec.ports[?(@.number==8080)].protocol}' 2>/dev/null)
[[ "$proto" == "HTTP" ]] \
  || fail "the ServiceEntry $se declares port 8080 as '$proto'. A VirtualService timeout only applies to a port declared HTTP - with TCP the proxy only moves bytes"

c=$(from_shuttle '%{http_code}' "http://${ROGUE_IP}:8080/get")
[[ "$c" == "200" ]] \
  && fail "GET http://${ROGUE_IP}:8080/get returned 200. The rogue must stay blocked - do not open the namespace to unknown hosts"

res=$(from_shuttle '%{http_code} %{time_total}' "http://${RELAY_IP}:8080/delay/5")
code=${res%% *}; took=${res##* }
[[ "$code" == "504" ]] \
  || fail "GET /delay/5 on the relay returned '$code' after ${took}s, expected 504 after about 2s. The 2s timeout in the VirtualService is not applied - check the protocol of the ServiceEntry port"
inwindow=$(awk -v t="${took:-0}" 'BEGIN { print (t >= 1.2 && t <= 4.0) ? 1 : 0 }')
[[ "$inwindow" == "1" ]] || fail "GET /delay/5 returned 504 after ${took}s, expected about 2s"

echo "PASS: the starfleet Sidecar is still REGISTRY_ONLY; the ServiceEntry $se for $HOST (HTTP on 8080) reaches the shuttle's sidecar proxy; the relay answers 200, a slow call hits the 2s timeout (504 after ${took}s), and the rogue is still blocked"
exit 0
