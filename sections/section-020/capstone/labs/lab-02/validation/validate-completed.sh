#!/usr/bin/env bash
# Confirms the whole capstone with real traffic:
#   - HTTP host probe: a header rule above an 80/20 weighted default rule that
#     also mirrors every request to probe-shadow
#   - TCP host probe-tcp: a tcp route that weighs 70/30
#   - both splits and the mirror are in the shuttle's sidecar proxy
#   - one reused connection splits per request on the HTTP Service, and stays
#     on one pod on the TCP Service
#   - the shadow receives the copies, and no client response comes from it
#   - no workload or Service was changed

set -u

NS="starfleet"
HTTP_SVC="probe"
TCP_SVC="probe-tcp"
SHADOW_SVC="probe-shadow"
SUFFIX="${NS}.svc.cluster.local"
SHADOW_CLUSTER="outbound|8000||${SHADOW_SVC}.${SUFFIX}"
TCP_V1="outbound|8000|v1|${TCP_SVC}.${SUFFIX}"
TCP_V2="outbound|8000|v2|${TCP_SVC}.${SUFFIX}"

fail() { echo "FAIL: $*"; exit 1; }

# Name of the object of a kind whose first host is the given Service
find_object() {
  local kind="$1" field="$2" svc="$3"
  kubectl -n "$NS" get "$kind" -o jsonpath="{range .items[*]}{.metadata.name}{\" \"}{$field}{\"\\n\"}{end}" 2>/dev/null \
    | awk -v a="$svc" -v b="$svc.$NS" -v c="$svc.$NS.svc" -v d="$svc.$SUFFIX" '$2==a || $2==b || $2==c || $2==d {print $1; exit}'
}
count_objects() {
  local kind="$1" field="$2" svc="$3"
  kubectl -n "$NS" get "$kind" -o jsonpath="{range .items[*]}{$field}{\"\\n\"}{end}" 2>/dev/null \
    | grep -cE "^($svc|$svc\.$NS|$svc\.$NS\.svc|$svc\.$SUFFIX)( |$)"
}

# --- 0. the environment is still what the capstone handed over ----------------
for d in probe-v1 probe-v2 probe-shadow shuttle; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the workloads alone"
done
deploy_count=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$deploy_count" -eq 4 ]] || fail "$NS holds $deploy_count deployments, expected exactly 4 - do not add or remove deployments"
for v in v1 v2; do
  lbl=$(kubectl -n "$NS" get deployment "probe-$v" -o jsonpath='{.spec.template.metadata.labels.version}' 2>/dev/null)
  [[ "$lbl" == "$v" ]] || fail "deployment probe-$v now labels its pods version='$lbl', expected '$v'"
done
http_port=$(kubectl -n "$NS" get service "$HTTP_SVC" -o jsonpath='{.spec.ports[0].name}' 2>/dev/null)
[[ "$http_port" == "http" ]] || fail "the port of Service $HTTP_SVC is named '$http_port', expected 'http'"
tcp_port=$(kubectl -n "$NS" get service "$TCP_SVC" -o jsonpath='{.spec.ports[0].name}' 2>/dev/null)
[[ "$tcp_port" == "tcp" ]] || fail "the port of Service $TCP_SVC is named '$tcp_port', expected 'tcp'"

# --- 1. the DestinationRules --------------------------------------------------
for svc in "$HTTP_SVC" "$TCP_SVC"; do
  dr=$(find_object destinationrule '.spec.host' "$svc")
  [[ -n "$dr" ]] || fail "no DestinationRule for the host $svc found in $NS"
  for s in v1 v2; do
    lbl=$(kubectl -n "$NS" get destinationrule "$dr" -o jsonpath="{.spec.subsets[?(@.name=='$s')].labels.version}" 2>/dev/null)
    [[ "$lbl" == "$s" ]] || fail "the DestinationRule for $svc has no subset '$s' selecting version=$s (found version='$lbl')"
  done
done

# --- 2. the VirtualServices ----------------------------------------------------
n=$(count_objects virtualservice '.spec.hosts[*]' "$HTTP_SVC")
[[ "$n" -eq 1 ]] || fail "found $n VirtualService objects for $HTTP_SVC in $NS, expected exactly one"
n=$(count_objects virtualservice '.spec.hosts[*]' "$TCP_SVC")
[[ "$n" -eq 1 ]] || fail "found $n VirtualService objects for $TCP_SVC in $NS, expected exactly one"

http_vs=$(find_object virtualservice '.spec.hosts[0]' "$HTTP_SVC")
tcp_vs=$(find_object virtualservice '.spec.hosts[0]' "$TCP_SVC")

mirror_host=$(kubectl -n "$NS" get virtualservice "$http_vs" -o jsonpath='{.spec.http[*].mirror.host}' 2>/dev/null)
case "$mirror_host" in
  "$SHADOW_SVC"|"$SHADOW_SVC.$NS"|"$SHADOW_SVC.$NS.svc"|"$SHADOW_SVC.$SUFFIX") ;;
  *) fail "the http rules of VirtualService $http_vs mirror to host '${mirror_host:-none}', expected $SHADOW_SVC" ;;
esac
pct=$(kubectl -n "$NS" get virtualservice "$http_vs" -o jsonpath='{.spec.http[*].mirrorPercentage.value}' 2>/dev/null)
if [[ -n "$pct" ]]; then
  awk -v p="$pct" 'BEGIN{exit !(p>=99.9)}' || fail "mirrorPercentage is $pct, expected 100: every request of the default rule must be copied"
fi

tcp_match=$(kubectl -n "$NS" get virtualservice "$tcp_vs" -o jsonpath='{.spec.tcp[0].match[0].port}' 2>/dev/null)
[[ "$tcp_match" == "8000" ]] || fail "the first tcp route of $tcp_vs matches port '${tcp_match:-none}', expected 8000 (the Service port). A port named tcp is routed with the tcp section"
t1=$(kubectl -n "$NS" get virtualservice "$tcp_vs" -o jsonpath="{.spec.tcp[0].route[?(@.destination.subset=='v1')].weight}" 2>/dev/null)
t2=$(kubectl -n "$NS" get virtualservice "$tcp_vs" -o jsonpath="{.spec.tcp[0].route[?(@.destination.subset=='v2')].weight}" 2>/dev/null)
[[ "$t1" == "70" && "$t2" == "30" ]] || fail "the tcp route weighs v1=${t1:-none} and v2=${t2:-none}, expected 70 and 30"

# --- 3. the shuttle's proxy holds the mirror and the TCP split -----------------
policy=""; listener=""; holds_tcp=0
for i in $(seq 1 20); do
  policy=$(istioctl proxy-config routes deploy/shuttle -n "$NS" -o json 2>/dev/null \
    | grep -A2 '"requestMirrorPolicies"' | grep -o '"cluster": "[^"]*"' | head -1)
  listener=$(istioctl proxy-config listener deploy/shuttle -n "$NS" --port 8000 -o json 2>/dev/null)
  holds_tcp=0
  if grep -q 'weightedClusters' <<<"$listener" && grep -qF "$TCP_V1" <<<"$listener" && grep -qF "$TCP_V2" <<<"$listener"; then
    holds_tcp=1
  fi
  [[ "$policy" == *"$SHADOW_CLUSTER"* && "$holds_tcp" -eq 1 ]] && break
  sleep 3
done
[[ "$policy" == *"$SHADOW_CLUSTER"* ]] || fail "the proxy of the shuttle holds no mirror policy for $SHADOW_CLUSTER (found: ${policy:-none})"
[[ "$holds_tcp" -eq 1 ]] || fail "the proxy of the shuttle holds no weighted clusters for $TCP_V1 and $TCP_V2 in its listener for port 8000"

# --- 4. HTTP: the header rule sends every tester request to v2 ------------------
tester=$(for i in $(seq 1 20); do
  kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 5 -H 'x-tester: yes' "http://$HTTP_SVC:8000/hostname" 2>/dev/null | grep -o 'probe-v[0-9]' || echo none
done | sort | uniq -c)
t_v2=$(awk '$2=="probe-v2"{print $1}' <<<"$tester")
[[ "${t_v2:-0}" -eq 20 ]] || fail "of 20 requests with the header x-tester: yes, the answers were: $(tr '\n' ' ' <<<"$tester"). Every one must come from probe-v2"

# --- 5. HTTP: 150 default requests split about 80/20, and the shadow gets copies -
sleep 4   # let copies from earlier requests arrive before the count window opens
start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
sleep 1
answers=$(kubectl -n "$NS" exec deploy/shuttle -- sh -c \
  'for i in $(seq 1 150); do curl -s --max-time 5 http://probe:8000/hostname; echo; done' 2>/dev/null \
  | grep -o 'probe-[a-z0-9]*' | sed -E 's/^(probe-v[0-9]).*/\1/' | sort | uniq -c)
h_v1=$(awk '$2=="probe-v1"{print $1}' <<<"$answers"); h_v1=${h_v1:-0}
h_v2=$(awk '$2=="probe-v2"{print $1}' <<<"$answers"); h_v2=${h_v2:-0}
[[ $((h_v1 + h_v2)) -eq 150 ]] || fail "of 150 default HTTP requests, the answers were: $(tr '\n' ' ' <<<"$answers"). Every response must come from probe-v1 or probe-v2, never from $SHADOW_SVC"
{ [[ "$h_v2" -ge 15 && "$h_v2" -le 45 ]]; } || fail "of 150 default HTTP requests, v1 answered $h_v1 and v2 answered $h_v2. With weights 80/20 about 30 should come from v2 (the grader accepts 15 to 45)"

copies=0
for attempt in 1 2 3; do
  sleep 4
  copies=$(kubectl -n "$NS" logs deploy/probe-shadow -c probe --since-time="$start" 2>/dev/null | grep -c 'GET /hostname')
  [[ "$copies" -ge 135 ]] && break
done
[[ "$copies" -ge 1 ]] || fail "$SHADOW_SVC received no copies of 150 default requests. Check the mirror and the Service name"
[[ "$copies" -ge 135 ]] || fail "$SHADOW_SVC received only $copies copies of 150 default requests. Every request of the default rule must be mirrored (mirrorPercentage 100)"

# --- 6. HTTP: one reused connection still splits per request --------------------
http_urls=()
for _ in $(seq 1 60); do http_urls+=("http://$HTTP_SVC:8000/hostname"); done
http_pods=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 30 "${http_urls[@]}" 2>/dev/null \
  | grep -o 'probe-v[0-9]' | sort -u | wc -l | tr -d ' ')
[[ "$http_pods" -ge 2 ]] || fail "60 requests over one connection to $HTTP_SVC were all answered by one version. An http rule picks per request, so both versions must answer"

# --- 7. TCP: one reused connection stays on one pod ------------------------------
tcp_urls=()
for _ in $(seq 1 15); do tcp_urls+=("http://$TCP_SVC:8000/hostname"); done
single=0
for run in 1 2 3 4 5; do
  pods=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 20 "${tcp_urls[@]}" 2>/dev/null \
    | grep -o 'probe-v[0-9]' | sort -u | wc -l | tr -d ' ')
  [[ "$pods" -eq 1 ]] && single=$((single + 1))
done
[[ "$single" -eq 5 ]] || fail "only $single of 5 runs of 15 requests over one connection to $TCP_SVC were answered by a single pod. A tcp route picks once per connection"

# --- 8. TCP: 150 fresh connections split about 70/30 ------------------------------
tcp_answers=$(kubectl -n "$NS" exec deploy/shuttle -- sh -c \
  'for i in $(seq 1 150); do curl -s --max-time 5 http://probe-tcp:8000/hostname; echo; done' 2>/dev/null \
  | grep -o 'probe-v[0-9]' | sort | uniq -c)
c_v1=$(awk '$2=="probe-v1"{print $1}' <<<"$tcp_answers"); c_v1=${c_v1:-0}
c_v2=$(awk '$2=="probe-v2"{print $1}' <<<"$tcp_answers"); c_v2=${c_v2:-0}
[[ $((c_v1 + c_v2)) -eq 150 ]] || fail "of 150 fresh connections to $TCP_SVC the answers were: $(tr '\n' ' ' <<<"$tcp_answers"). Every connection must get an answer"
{ [[ "$c_v2" -ge 25 && "$c_v2" -le 65 ]]; } || fail "of 150 fresh connections to $TCP_SVC, v1 answered $c_v1 and v2 answered $c_v2. With weights 70/30 about 45 should come from v2 (the grader accepts 25 to 65)"

echo "PASS: header rule sends testers to v2; HTTP default split $h_v1/$h_v2 with $copies copies in $SHADOW_SVC; one HTTP connection splits per request; one TCP connection stays on one pod; 150 TCP connections split $c_v1/$c_v2"
