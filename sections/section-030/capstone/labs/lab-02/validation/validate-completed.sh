#!/usr/bin/env bash
# Confirms the probe DestinationRule: subsets v1 and v2, tls ISTIO_MUTUAL and a
# consistentHash on the x-session-id header at host level, and a ROUND_ROBIN
# override on subset v2 only; that the shuttle's proxy holds a TLS transport
# socket for both subset clusters, RING_HASH for v1 and no RING_HASH for v2;
# that the PeerAuthentication and the workloads were left alone; and - the part
# that matters - that live requests return 200, one x-session-id value always
# reaches one v1 pod, the same value spreads over both v2 pods, and the
# drifter outside the mesh is still refused.

set -u

NS="starfleet"
SVC="probe"
FQDN="probe.starfleet.svc.cluster.local"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is still what the capstone handed over --------------
for d in probe-v1 probe-v2 shuttle; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the deployments alone"
done
v1=$(kubectl -n "$NS" get deployment probe-v1 -o jsonpath='{.spec.replicas}' 2>/dev/null)
v2=$(kubectl -n "$NS" get deployment probe-v2 -o jsonpath='{.spec.replicas}' 2>/dev/null)
[[ "$v1" == "3" && "$v2" == "2" ]] || fail "probe-v1 runs $v1 replicas and probe-v2 runs $v2, expected 3 and 2. Do not scale the deployments"

pa_mode=$(kubectl -n "$NS" get peerauthentication probe -o jsonpath='{.spec.mtls.mode}' 2>/dev/null)
[[ "$pa_mode" == "STRICT" ]] || fail "the PeerAuthentication 'probe' has mode '${pa_mode:-missing}', expected STRICT. Do not weaken it: the DestinationRule must match it"

# --- 1. the DestinationRule ---------------------------------------------------
kubectl -n "$NS" get destinationrule "$SVC" >/dev/null 2>&1 \
  || fail "DestinationRule '$SVC' not found in $NS"
dr_host=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.host}' 2>/dev/null)
case "$dr_host" in
  "$SVC"|"$SVC.$NS"|"$SVC.$NS.svc"|"$FQDN") ;;
  *) fail "DestinationRule host is '$dr_host', expected $SVC (short or full name)" ;;
esac
dr_json=$(kubectl -n "$NS" get destinationrule "$SVC" -o json 2>/dev/null)
grep -q '"DISABLE"' <<<"$dr_json" && fail "the DestinationRule contains tls mode DISABLE. The probe accepts only mTLS"

for s in v1 v2; do
  lbl=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath="{.spec.subsets[?(@.name==\"$s\")].labels.version}" 2>/dev/null)
  [[ "$lbl" == "$s" ]] || fail "subset $s selects version='${lbl:-nothing}', expected version=$s"
done
tls=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.trafficPolicy.tls.mode}' 2>/dev/null)
[[ "$tls" == "ISTIO_MUTUAL" ]] || fail "the host-level trafficPolicy.tls.mode is '${tls:-unset}', expected ISTIO_MUTUAL"
hash_header=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.trafficPolicy.loadBalancer.consistentHash.httpHeaderName}' 2>/dev/null)
[[ "$hash_header" == "x-session-id" ]] || fail "the host-level consistentHash header is '${hash_header:-unset}', expected x-session-id"
lb_v2=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.subsets[?(@.name=="v2")].trafficPolicy.loadBalancer.simple}' 2>/dev/null)
[[ "$lb_v2" == "ROUND_ROBIN" ]] || fail "subset v2 has loadBalancer.simple '${lb_v2:-unset}', expected ROUND_ROBIN"
lb_v1=$(kubectl -n "$NS" get destinationrule "$SVC" -o json 2>/dev/null | grep -c '"simple"')
[[ "$lb_v1" -eq 1 ]] || fail "the DestinationRule has $lb_v1 'simple' load balancer settings, expected exactly 1 (subset v2). Subset v1 inherits the host's consistentHash"

# --- 2. the shuttle's proxy holds what the rules say -------------------------
cluster_json() {
  istioctl proxy-config cluster deploy/shuttle -n "$NS" --fqdn "$FQDN" --subset "$1" -o json 2>/dev/null
}
ok=""
for i in $(seq 1 15); do
  j1=$(cluster_json v1); j2=$(cluster_json v2)
  t1=$(grep -c 'envoy.transport_sockets.tls' <<<"$j1")
  t2=$(grep -c 'envoy.transport_sockets.tls' <<<"$j2")
  p1=$(grep -o '"lbPolicy": "[A-Z_]*"' <<<"$j1" | head -1)
  p2=$(grep -o '"lbPolicy": "[A-Z_]*"' <<<"$j2" | head -1)
  if [[ "$t1" -ge 1 && "$t2" -ge 1 && "$p1" == *'"RING_HASH"'* && "$p2" != *'"RING_HASH"'* ]]; then ok=1; break; fi
  sleep 2
done
[[ -n "$ok" ]] || fail "the shuttle's proxy should hold a TLS transport socket for both subset clusters, RING_HASH for v1 and no RING_HASH for v2 (TLS sockets: v1=$t1, v2=$t2; policies: v1='${p1:-none}', v2='${p2:-none}'). If you just applied the fix, wait a few seconds and submit again"

# --- 3. live requests -------------------------------------------------------
send() {
  # $@ = curl header arguments; prints "<status> <pod>"
  local out
  out=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 5 -w '\n%{http_code}' "$@" "http://$SVC:8000/hostname" 2>/dev/null)
  echo "$(tail -n1 <<<"$out") $(grep -o 'probe-v[12]-[a-z0-9-]*' <<<"$out" | head -1)"
}

first=""
for i in $(seq 1 15); do
  first=$(send -H "x-session-id: s1")
  [[ "$first" == 200* ]] && break
  sleep 2
done

collect() {
  # $1 = subset name, $2 = pod prefix, rest = extra curl header arguments;
  # prints the pod names (one per line) and fails on any non-200 answer
  local subset="$1" prefix="$2"; shift 2
  local r
  for i in $(seq 1 8); do
    r=$(send -H "x-session-id: s1" "$@")
    [[ "$r" == 200\ "$prefix"* ]] || { echo "FAIL: subset $subset: a request returned [$r], expected status 200 from a $prefix pod. 503 means the proxy could not reach the probe: check the tls mode"; return 1; }
    echo "${r#* }"
  done
}

v1_pods=$(collect v1 probe-v1-) || { echo "$v1_pods"; exit 1; }
n1=$(sort -u <<<"$v1_pods" | grep -c .)
[[ "$n1" -eq 1 ]] || fail "subset v1: 8 requests with x-session-id: s1 reached $n1 different pods. One x-session-id must always reach the same pod"

v2_pods=$(collect v2 probe-v2- -H "x-canary: true") || { echo "$v2_pods"; exit 1; }
n2=$(sort -u <<<"$v2_pods" | grep -c .)
[[ "$n2" -eq 2 ]] || fail "subset v2: 8 requests with the same x-session-id reached $n2 pod(s), expected both v2 pods. Subset v2 must spread requests in turn"

# --- 4. the PeerAuthentication still refuses a client with no sidecar --------
code=$(kubectl -n outpost exec deploy/drifter -- curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://$FQDN:8000/hostname" 2>/dev/null)
[[ "$code" != "200" ]] || fail "the drifter (no sidecar) reached the probe with 200. The probe must stay STRICT"

echo "PASS: the DestinationRule combines tls ISTIO_MUTUAL and a consistentHash on x-session-id with a ROUND_ROBIN override on v2; one session reached one v1 pod, the same session spread over both v2 pods, all answers were 200, and the drifter is still refused"
exit 0
