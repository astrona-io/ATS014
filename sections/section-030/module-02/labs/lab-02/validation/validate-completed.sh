#!/usr/bin/env bash
# Confirms the repaired probe DestinationRule: no tls mode DISABLE anywhere (the
# tls block is removed or ISTIO_MUTUAL), the host-level consistentHash on the
# x-user header is still there, and subset v2 no longer replaces it; that the
# shuttle's proxy holds a TLS transport socket and RING_HASH for both subset
# clusters; that the PeerAuthentication and the workloads were left alone;
# and - the part that matters - that live requests from the shuttle return 200
# and that the same x-user value always reaches the same pod in both
# subsets, while the drifter outside the mesh is still refused.

set -u

NS="starfleet"
SVC="probe"
FQDN="probe.starfleet.svc.cluster.local"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is still what the lab handed over -------------------
for d in probe-v1 probe-v2 shuttle; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the deployments alone: the fix belongs in the DestinationRule"
done
v1=$(kubectl -n "$NS" get deployment probe-v1 -o jsonpath='{.spec.replicas}' 2>/dev/null)
v2=$(kubectl -n "$NS" get deployment probe-v2 -o jsonpath='{.spec.replicas}' 2>/dev/null)
[[ "$v1" == "2" && "$v2" == "2" ]] || fail "probe-v1 runs $v1 replicas and probe-v2 runs $v2, expected 2 and 2. Do not scale the deployments"

pa_mode=$(kubectl -n "$NS" get peerauthentication probe -o jsonpath='{.spec.mtls.mode}' 2>/dev/null)
[[ "$pa_mode" == "STRICT" ]] || fail "the PeerAuthentication 'probe' has mode '${pa_mode:-missing}', expected STRICT. Do not weaken it: fix the DestinationRule so it matches"

# --- 1. the DestinationRule ---------------------------------------------------
kubectl -n "$NS" get destinationrule "$SVC" >/dev/null 2>&1 \
  || fail "DestinationRule '$SVC' not found in $NS. Fix it, do not delete it: the VirtualService needs its subsets"
dr_host=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.host}' 2>/dev/null)
case "$dr_host" in
  "$SVC"|"$SVC.$NS"|"$SVC.$NS.svc"|"$FQDN") ;;
  *) fail "DestinationRule host is '$dr_host', expected $SVC (short or full name)" ;;
esac
for s in v1 v2; do
  lbl=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath="{.spec.subsets[?(@.name==\"$s\")].labels.version}" 2>/dev/null)
  [[ "$lbl" == "$s" ]] || fail "subset $s selects version='${lbl:-nothing}', expected version=$s. Keep both subsets"
done

dr_json=$(kubectl -n "$NS" get destinationrule "$SVC" -o json 2>/dev/null)
grep -q '"DISABLE"' <<<"$dr_json" \
  && fail "the DestinationRule still contains tls mode DISABLE. The probe accepts only mTLS: remove the tls block or set ISTIO_MUTUAL"
tls=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.trafficPolicy.tls.mode}' 2>/dev/null)
[[ -z "$tls" || "$tls" == "ISTIO_MUTUAL" ]] || fail "the host-level tls mode is '$tls', expected ISTIO_MUTUAL or no tls block"

hash_header=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.trafficPolicy.loadBalancer.consistentHash.httpHeaderName}' 2>/dev/null)
[[ "$hash_header" == "x-user" ]] || fail "the host-level consistentHash header is '${hash_header:-unset}', expected x-user. Keep the host-level policy: the fault is in what overrides it"
sub_simple=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.subsets[*].trafficPolicy.loadBalancer.simple}' 2>/dev/null)
[[ -z "$sub_simple" ]] || fail "a subset still sets loadBalancer.simple ('$sub_simple'). That replaces the host's consistentHash for the subset. Remove it, or repeat the consistentHash there"

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
  if [[ "$t1" -ge 1 && "$t2" -ge 1 && "$p1" == *'"RING_HASH"'* && "$p2" == *'"RING_HASH"'* ]]; then ok=1; break; fi
  sleep 2
done
[[ -n "$ok" ]] || fail "the shuttle's proxy should hold a TLS transport socket and lbPolicy RING_HASH for both subset clusters (TLS sockets: v1=$t1, v2=$t2; policies: v1='${p1:-none}', v2='${p2:-none}'). If you just applied the fix, wait a few seconds and submit again"

# --- 3. live requests -------------------------------------------------------
send() {
  # $@ = curl header arguments; prints "<status> <pod>"
  local out
  out=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 5 -w '\n%{http_code}' "$@" "http://$SVC:8000/hostname" 2>/dev/null)
  echo "$(tail -n1 <<<"$out") $(grep -o 'probe-v[12]-[a-z0-9-]*' <<<"$out" | head -1)"
}

first=""
for i in $(seq 1 15); do
  first=$(send -H "x-user: alice")
  [[ "$first" == 200* ]] && break
  sleep 2
done

check_sticky() {
  # $1 = subset name, $2 = pod prefix, rest = extra curl header arguments
  local subset="$1" prefix="$2"; shift 2
  local seen="" r
  for i in $(seq 1 8); do
    r=$(send -H "x-user: alice" "$@")
    [[ "$r" == 200\ "$prefix"* ]] || fail "subset $subset: a request returned [$r], expected status 200 from a $prefix pod. 503 means the proxy could not reach the probe: check the tls mode"
    seen+="${r#* }"$'\n'
  done
  local distinct
  distinct=$(sort -u <<<"$seen" | grep -c .)
  [[ "$distinct" -eq 1 ]] || fail "subset $subset: 8 requests with x-user: alice reached $distinct different pods. The same x-user must always reach the same pod"
}
check_sticky v1 probe-v1-
check_sticky v2 probe-v2- -H "x-canary: true"

# --- 4. the PeerAuthentication still refuses a client with no sidecar --------
code=$(kubectl -n outpost exec deploy/drifter -- curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://$FQDN:8000/hostname" 2>/dev/null)
[[ "$code" != "200" ]] || fail "the drifter (no sidecar) reached the probe with 200. The probe must stay STRICT, so only mesh clients may reach it"

echo "PASS: no tls DISABLE is left, both subsets use consistentHash on x-user with mTLS in the shuttle's proxy, 8 requests per subset with the same x-user reached one pod and returned 200, and the drifter is still refused by STRICT"
exit 0
