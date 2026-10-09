#!/usr/bin/env bash
# Confirms the two broken HTTPRoutes were repaired without touching the
# Gateway: the Gateway is unchanged and alone in the namespace, both HTTPRoutes keep
# their names, hosts and paths, both report Accepted and ResolvedRefs on
# starfleet-gateway, the Gateway listener holds both routes, and - the part that
# matters - live requests from the shuttle pod reach the bridge and the scout
# through the gateway proxy.

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
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the deployments alone: the faults are in the HTTPRoutes"
done
for s in bridge scout; do
  kubectl -n "$NS" get service "$s" >/dev/null 2>&1 \
    || fail "Service '$s' not found in $NS. Do not rename or remove Services - point the routes at the Services that exist"
done
svcs=$(kubectl -n "$NS" get services -o name 2>/dev/null | grep -v "service/${GW}-istio" | wc -l | tr -d ' ')
[[ "$svcs" -eq 4 ]] || fail "$NS holds $svcs Services besides the gateway proxy's own, expected 4 (bridge, cargo, navcom, scout). Do not add a Service to match a typo - fix the route instead"

# --- 1. the Gateway is unchanged ----------------------------------------------
gws=$(kubectl -n "$NS" get gateways -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
[[ "$gws" == "$GW" ]] \
  || fail "the Gateways in $NS are [$gws], expected only $GW. Do not create a second Gateway to match a typo - fix the route's parentRefs instead"
gw=$(kubectl -n "$NS" get gateway "$GW" -o jsonpath='{.spec.gatewayClassName}|{.spec.listeners[*].name}|{.spec.listeners[0].port}|{.spec.listeners[0].protocol}|{.spec.listeners[0].hostname}|{.spec.listeners[0].allowedRoutes.namespaces.from}' 2>/dev/null)
[[ "$gw" == "istio|http|80|HTTP|$HOST|Same" ]] \
  || fail "the Gateway $GW changed (found '$gw'). It was correct: leave it as one HTTP listener named http on port 80 for $HOST with allowedRoutes from Same"

# --- 2. the status conditions --------------------------------------------------
check_status() {  # check_status <route>
  local a r parent msg
  for _ in $(seq 1 30); do
    [[ "$(cond httproute "$1" '.status.parents[0].conditions' ResolvedRefs)" == "True" ]] && break
    sleep 2
  done
  parent=$(kubectl -n "$NS" get httproute "$1" -o jsonpath='{.status.parents[*].parentRef.name}' 2>/dev/null)
  [[ -n "$parent" ]] || fail "HTTPRoute '$1' has no status from any Gateway (status.parents is empty). No Gateway accepted it: check the name in its parentRefs"
  a=$(cond httproute "$1" '.status.parents[0].conditions' Accepted)
  r=$(cond httproute "$1" '.status.parents[0].conditions' ResolvedRefs)
  [[ "$a" == "True" ]] || fail "HTTPRoute '$1' reports Accepted=$a on $parent. The Gateway refused it - the condition message says why"
  msg=$(kubectl -n "$NS" get httproute "$1" -o jsonpath="{.status.parents[0].conditions[?(@.type=='ResolvedRefs')].message}" 2>/dev/null)
  [[ "$r" == "True" ]] || fail "HTTPRoute '$1' reports ResolvedRefs=$r ($msg). A backend Service could not be found: compare backendRefs with 'kubectl get svc -n $NS'"
}
for r in bridge scout; do
  kubectl -n "$NS" get httproute "$r" >/dev/null 2>&1 \
    || fail "HTTPRoute '$r' not found in $NS - repair it, do not delete it"
  check_status "$r"
done

# --- 3. both routes keep their names, hosts and paths -------------------------
check_spec() {  # check_spec <route> <path> <backend>
  kubectl -n "$NS" get httproute "$1" >/dev/null 2>&1 \
    || fail "HTTPRoute '$1' not found in $NS - repair it, do not delete it"
  local spec
  spec=$(kubectl -n "$NS" get httproute "$1" -o jsonpath='{.spec.parentRefs[*].name}|{.spec.parentRefs[0].namespace}|{.spec.hostnames[*]}|{.spec.rules[0].matches[0].path.type}|{.spec.rules[0].matches[0].path.value}|{.spec.rules[0].backendRefs[*].name}:{.spec.rules[0].backendRefs[0].port}' 2>/dev/null)
  case "$spec" in
    "$GW||$HOST|PathPrefix|$2|$3:9080"|"$GW|$NS|$HOST|PathPrefix|$2|$3:9080") ;;
    *) fail "HTTPRoute '$1' is '$spec' (parentRefs|namespace|hostnames|path type|path|backend:port), expected '$GW||$HOST|PathPrefix|$2|$3:9080'. Read its status: kubectl get httproute $1 -n $NS -o yaml" ;;
  esac
}
check_spec bridge /productpage bridge
check_spec scout /reviews scout

attached=$(kubectl -n "$NS" get gateway "$GW" -o jsonpath='{.status.listeners[0].attachedRoutes}' 2>/dev/null)
[[ "$attached" == "2" ]] || fail "the Gateway listener holds $attached routes, expected 2 (bridge and scout)"

# --- 4. live requests through the gateway proxy --------------------------------
code_for() {  # code_for <path>
  kubectl -n "$NS" exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
    -H "Host: $HOST" "${GW_URL}$1" 2>/dev/null
}

check_path() {  # check_path <path> <what>
  local code="" good=0
  for _ in $(seq 1 30); do
    code=$(code_for "$1")
    [[ "$code" == "200" ]] && break
    sleep 2
  done
  [[ "$code" == "200" ]] \
    || fail "GET $1 with Host $HOST through ${GW}-istio returned '$code', expected 200 from $2. Read the gateway proxy's access log: kubectl logs -n $NS deploy/${GW}-istio --tail=5"
  for _ in $(seq 1 10); do
    [[ "$(code_for "$1")" == "200" ]] && good=$((good + 1))
  done
  [[ "$good" -eq 10 ]] || fail "only $good of 10 requests to $1 returned 200"
}
check_path /productpage "the bridge"
check_path /reviews/0 "the scout"

echo "PASS: the Gateway is unchanged, both HTTPRoutes are attached to $GW with Accepted and ResolvedRefs True, the Gateway listener holds 2 routes, and 10 of 10 requests each reach the bridge and the scout"
exit 0
