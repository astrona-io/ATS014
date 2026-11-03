#!/usr/bin/env bash
# Confirms the probe DestinationRule defines subsets v1 and v2, sets
# tls ISTIO_MUTUAL at host level, gives subset v2 its own RANDOM load balancer
# and leaves v1 alone; that the shuttle's proxy holds a TLS transport socket
# for both subset clusters and RANDOM for v2 only; that the PeerAuthentication
# and the workloads were left alone; and - the part that matters - that live
# requests from the shuttle reach v1 pods (no header) and v2 pods (header
# x-canary: true) with status 200, while the drifter outside the mesh is still
# refused.

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
[[ "$v1" == "3" && "$v2" == "1" ]] || fail "probe-v1 runs $v1 replicas and probe-v2 runs $v2, expected 3 and 1. Do not scale the deployments"

# The PeerAuthentication is the thing the DestinationRule must match: it stays STRICT.
pa_mode=$(kubectl -n "$NS" get peerauthentication probe -o jsonpath='{.spec.mtls.mode}' 2>/dev/null)
[[ "$pa_mode" == "STRICT" ]] || fail "the PeerAuthentication 'probe' has mode '${pa_mode:-missing}', expected STRICT. Do not weaken it: the DestinationRule must match it"
pa_label=$(kubectl -n "$NS" get peerauthentication probe -o jsonpath='{.spec.selector.matchLabels.app}' 2>/dev/null)
[[ "$pa_label" == "probe" ]] || fail "the PeerAuthentication 'probe' selects app='${pa_label}', expected app=probe"

# --- 1. the DestinationRule ---------------------------------------------------
kubectl -n "$NS" get destinationrule "$SVC" >/dev/null 2>&1 \
  || fail "DestinationRule '$SVC' not found in $NS"
dr_host=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.host}' 2>/dev/null)
case "$dr_host" in
  "$SVC"|"$SVC.$NS"|"$SVC.$NS.svc"|"$FQDN") ;;
  *) fail "DestinationRule host is '$dr_host', expected $SVC (short or full name)" ;;
esac

dr_json=$(kubectl -n "$NS" get destinationrule "$SVC" -o json 2>/dev/null)
grep -q '"DISABLE"' <<<"$dr_json" && fail "the DestinationRule contains tls mode DISABLE. The probe accepts only mTLS, so a client must not turn TLS off"

for s in v1 v2; do
  lbl=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath="{.spec.subsets[?(@.name==\"$s\")].labels.version}" 2>/dev/null)
  [[ "$lbl" == "$s" ]] || fail "subset $s selects version='${lbl:-nothing}', expected version=$s"
done

tls=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.trafficPolicy.tls.mode}' 2>/dev/null)
[[ "$tls" == "ISTIO_MUTUAL" ]] || fail "the host-level trafficPolicy.tls.mode is '${tls:-unset}', expected ISTIO_MUTUAL"

lb_v2=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.subsets[?(@.name=="v2")].trafficPolicy.loadBalancer.simple}' 2>/dev/null)
[[ "$lb_v2" == "RANDOM" ]] || fail "subset v2 has loadBalancer.simple '${lb_v2:-unset}', expected RANDOM"
lb_v1=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.subsets[?(@.name=="v1")].trafficPolicy.loadBalancer.simple}' 2>/dev/null)
[[ -z "$lb_v1" ]] || fail "subset v1 sets its own loadBalancer ('$lb_v1'). Only subset v2 gets an override"

# --- 2. the shuttle's proxy holds what the rules say -------------------------
cluster_json() {
  istioctl proxy-config cluster deploy/shuttle -n "$NS" --fqdn "$FQDN" --subset "$1" -o json 2>/dev/null
}
ok=""
for i in $(seq 1 15); do
  j1=$(cluster_json v1); j2=$(cluster_json v2)
  t1=$(grep -c 'envoy.transport_sockets.tls' <<<"$j1")
  t2=$(grep -c 'envoy.transport_sockets.tls' <<<"$j2")
  p2=$(grep -o '"lbPolicy": "[A-Z_]*"' <<<"$j2" | head -1)
  if [[ "$t1" -ge 1 && "$t2" -ge 1 && "$p2" == *'"RANDOM"'* ]]; then ok=1; break; fi
  sleep 2
done
[[ -n "$ok" ]] || fail "the shuttle's proxy should hold a TLS transport socket for both subset clusters and lbPolicy RANDOM for v2 (TLS sockets: v1=$t1, v2=$t2; v2 policy: '${p2:-none}'). If you just applied the fix, wait a few seconds and submit again"
grep -q '"lbPolicy": "RANDOM"' <<<"$j1" && fail "the v1 cluster uses RANDOM too. Only subset v2 should"

# --- 3. live requests -------------------------------------------------------
send() {
  # $1 = extra curl header args (may be empty); prints "<status> <pod>"
  local out
  out=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 5 -w '\n%{http_code}' $1 "http://$SVC:8000/hostname" 2>/dev/null)
  echo "$(tail -n1 <<<"$out") $(grep -o 'probe-v[12]-[a-z0-9-]*' <<<"$out" | head -1)"
}

# Wait until the first request works, so a slow proxy update is not a fail.
first=""
for i in $(seq 1 15); do
  first=$(send "")
  [[ "$first" == 200* ]] && break
  sleep 2
done

bad=""
for i in $(seq 1 8); do
  r=$(send "")
  [[ "$r" == 200\ probe-v1-* ]] || bad+="[$r] "
done
[[ -z "$bad" ]] || fail "requests without a header should return 200 from a v1 pod. Got: $bad. 503 means the proxy could not reach the probe: check the tls mode and the subsets"

bad=""
for i in $(seq 1 8); do
  r=$(send "-H x-canary:true")
  [[ "$r" == 200\ probe-v2-* ]] || bad+="[$r] "
done
[[ -z "$bad" ]] || fail "requests with 'x-canary: true' should return 200 from the v2 pod. Got: $bad"

# --- 4. the PeerAuthentication still refuses a client with no sidecar --------
code=$(kubectl -n outpost exec deploy/drifter -- curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://$FQDN:8000/hostname" 2>/dev/null)
[[ "$code" != "200" ]] || fail "the drifter (no sidecar) reached the probe with 200. The probe must stay STRICT, so only mesh clients may reach it"

echo "PASS: the DestinationRule uses tls ISTIO_MUTUAL with subsets v1 and v2 (v2 RANDOM), the shuttle's proxy holds mTLS for both subsets, requests reach v1 and v2 with status 200, and the drifter is still refused by STRICT"
exit 0
