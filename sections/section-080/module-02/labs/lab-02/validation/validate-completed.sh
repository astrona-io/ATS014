#!/usr/bin/env bash
# Confirms the partner route through the departure gate works with mutual TLS
# started at the gate: stage 2 sends the signal on to port 443, the MUTUAL
# DestinationRule is unchanged, the client certificate Secret is in the gate's
# own namespace and loaded by the gate, the shuttle holds no TLS settings or
# keys for the partner, and - the part that matters - a live plain signal from
# the shuttle reaches the partner, which accepts the gate's certificate.

set -u

NS="starfleet"
HOST="partner.outpost.example"
GW_NS="istio-egress"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is still what the lab handed over -------------------
r=$(kubectl -n "$NS" get deployment shuttle -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ -n "$r" && "$r" -ge 1 ]] || fail "shuttle - deployment missing or has no ready replicas in $NS"
r=$(kubectl -n outpost get deployment partner -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ -n "$r" && "$r" -ge 1 ]] || fail "outpost/partner - deployment missing or has no ready replicas. Leave the partner alone"
v=$(kubectl -n outpost get configmap partner-conf -o jsonpath='{.data.default\.conf}' 2>/dev/null)
grep -q 'ssl_verify_client *on' <<<"$v" \
  || fail "the partner no longer asks for a client certificate. Leave the partner's configuration alone: the fix belongs in the mesh"

# --- 1. the objects that were correct are still in place --------------------
kubectl -n "$NS" get serviceentry partner >/dev/null 2>&1 || fail "ServiceEntry 'partner' not found in $NS - it was correct, leave it in place"
kubectl -n "$NS" get gateway departure-gate >/dev/null 2>&1 || fail "Gateway 'departure-gate' not found in $NS - it was correct, leave it in place"
kubectl -n "$NS" get destinationrule departure-gate >/dev/null 2>&1 || fail "DestinationRule 'departure-gate' not found in $NS - stage 1 names its subset 'partner'"

DR=partner-tls
kubectl -n "$NS" get destinationrule "$DR" >/dev/null 2>&1 || fail "DestinationRule '$DR' not found in $NS - it holds the TLS settings for the gate"
dh=$(kubectl -n "$NS" get destinationrule "$DR" -o jsonpath='{.spec.host}' 2>/dev/null)
[[ "$dh" == "$HOST" ]] || fail "DestinationRule '$DR' targets host '$dh', expected $HOST. The TLS settings belong to the outside host, so the gate follows them"
pm=$(kubectl -n "$NS" get destinationrule "$DR" -o jsonpath='{.spec.trafficPolicy.portLevelSettings[0].tls.mode}' 2>/dev/null)
pp=$(kubectl -n "$NS" get destinationrule "$DR" -o jsonpath='{.spec.trafficPolicy.portLevelSettings[0].port.number}' 2>/dev/null)
pc=$(kubectl -n "$NS" get destinationrule "$DR" -o jsonpath='{.spec.trafficPolicy.portLevelSettings[0].tls.credentialName}' 2>/dev/null)
sk=$(kubectl -n "$NS" get destinationrule "$DR" -o jsonpath='{.spec.trafficPolicy.portLevelSettings[0].tls.insecureSkipVerify}' 2>/dev/null)
[[ "$pp" == "443" && "$pm" == "MUTUAL" ]] \
  || fail "DestinationRule '$DR' has port '$pp' mode '$pm', expected port 443 with MUTUAL. The partner asks for a client certificate"
[[ "$pc" == "partner-client-cert" ]] \
  || fail "credentialName is '$pc', expected partner-client-cert. Keep the name and put the Secret where the gate reads it"
[[ "$sk" != "true" ]] || fail "insecureSkipVerify is true. The gate must check the partner's certificate with ca.crt from the Secret"
ex=$(kubectl -n "$NS" get destinationrule "$DR" -o jsonpath='{.spec.exportTo[*]}' 2>/dev/null)
[[ "$ex" == "$GW_NS" ]] || fail "DestinationRule '$DR' exportTo is [$ex], expected [$GW_NS]. Only the gate should get the TLS settings"

# --- 2. stage 2 sends the signal on to port 443 ------------------------------
VS=partner-via-gate
kubectl -n "$NS" get virtualservice "$VS" >/dev/null 2>&1 || fail "VirtualService '$VS' not found in $NS"
s1g=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[0].match[0].gateways[0]}' 2>/dev/null)
s1h=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[0].route[0].destination.host}' 2>/dev/null)
[[ "$s1g" == "mesh" && "$s1h" == "istio-egress.istio-egress.svc.cluster.local" ]] \
  || fail "stage 1 (the first rule) must match gateways [mesh] and route to the gate's Service; found gateways '$s1g', host '$s1h'. Stage 1 was correct"
s2g=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[1].match[0].gateways[0]}' 2>/dev/null)
s2h=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[1].route[0].destination.host}' 2>/dev/null)
s2p=$(kubectl -n "$NS" get virtualservice "$VS" -o jsonpath='{.spec.http[1].route[0].destination.port.number}' 2>/dev/null)
[[ "$s2g" == "departure-gate" && "$s2h" == "$HOST" ]] \
  || fail "stage 2 (the second rule) must match gateways [departure-gate] and route to $HOST; found gateways '$s2g', host '$s2h'"
[[ "$s2p" == "443" ]] \
  || fail "stage 2 routes to port '$s2p', expected 443. The TLS settings only cover port 443, and the partner only listens there"

# --- 3. the Secret is on the gate's planet, and the gate loaded it ----------
kubectl -n "$GW_NS" get secret partner-client-cert >/dev/null 2>&1 \
  || fail "no Secret 'partner-client-cert' in $GW_NS. credentialName is read from the namespace of the proxy that uses it: the gate's (look at istioctl proxy-config secret on the gate, and the istiod log)"
for k in 'tls\.crt' 'tls\.key' 'ca\.crt'; do
  val=$(kubectl -n "$GW_NS" get secret partner-client-cert -o jsonpath="{.data.$k}" 2>/dev/null)
  [[ -n "$val" ]] || fail "the Secret partner-client-cert in $GW_NS has no key ${k//\\/} - it needs tls.crt, tls.key and ca.crt"
done

loaded=""
for i in $(seq 1 30); do
  row=$(istioctl proxy-config secret deploy/istio-egress -n "$GW_NS" 2>/dev/null | grep -E '^kubernetes://partner-client-cert[[:space:]]')
  grep -q ' ACTIVE ' <<<"$row" && { loaded=1; break; }
  sleep 2
done
[[ -n "$loaded" ]] || fail "the gate has not loaded kubernetes://partner-client-cert (istioctl proxy-config secret deploy/istio-egress -n $GW_NS shows: ${row:-no row})"

# --- 4. the shuttle holds no TLS settings and no keys for the partner -------
sc_tls=$(istioctl proxy-config cluster deploy/shuttle -n "$NS" --fqdn "$HOST" -o json 2>/dev/null | grep -c transportSocket)
[[ "$sc_tls" -eq 0 ]] || fail "the shuttle's sidecar has TLS settings for $HOST ($sc_tls). Keep exportTo: [$GW_NS] so only the gate starts the TLS connection"
if istioctl proxy-config secret deploy/shuttle -n "$NS" 2>/dev/null | grep -q partner-client-cert; then
  fail "the shuttle's sidecar holds partner-client-cert. Only the gate should hold the partner's keys"
fi

# --- 5. live: a plain signal reaches the partner through the gate ----------
gw_lines() { kubectl -n "$GW_NS" logs deploy/istio-egress --tail=-1 2>/dev/null | grep -c "\"$HOST\""; }
body=""; code=""
for i in $(seq 1 20); do
  before=$(gw_lines)
  out=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 10 -w '\n%{http_code}' "http://$HOST/" 2>/dev/null)
  code=$(tail -1 <<<"$out"); body=$(sed '$d' <<<"$out")
  [[ "$code" == "200" ]] && break
  sleep 3
done
[[ "$code" == "200" ]] \
  || fail "GET http://$HOST/ from the shuttle returned '$code', expected 200. Read the gate's flight log: kubectl logs -n $GW_NS deploy/istio-egress --tail=1"
grep -q 'verify=SUCCESS' <<<"$body" || fail "the partner answered '$body', expected verify=SUCCESS - it did not accept a client certificate"
grep -q 'client=CN=starfleet-departure-gate' <<<"$body" \
  || fail "the partner answered '$body' - it should see the client certificate CN=starfleet-departure-gate from the delivered Secret"

sleep 3
after=$(gw_lines)
[[ $((after - before)) -ge 1 ]] || fail "the gate's flight log gained no line for $HOST. The signal must leave through the gate"
kubectl -n "$GW_NS" logs deploy/istio-egress --tail=20 2>/dev/null | grep "\"$HOST\"" | tail -1 | grep -q ':443"' \
  || fail "the gate's last line for $HOST does not show an upstream on port 443"

echo "PASS: stage 2 routes to port 443, the gate loaded partner-client-cert from $GW_NS, the shuttle holds no TLS settings or keys for the partner, and a plain http:// signal reached the partner through the gate with verify=SUCCESS"
exit 0
