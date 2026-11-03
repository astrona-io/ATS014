#!/usr/bin/env bash
# Confirms the probe-tcp DestinationRule defines v1 and v2 over the pods'
# version label, that exactly one VirtualService for probe-tcp has one tcp
# route that matches port 8000 and weighs 80/20, that the shuttle's sidecar
# proxy holds both weighted clusters, that one reused connection stays on one
# pod, and - the part that matters - that 150 fresh connections really split
# close to 80/20.

set -u

NS="starfleet"
SVC="probe-tcp"
FQDN="probe-tcp.starfleet.svc.cluster.local"
V1_CLUSTER="outbound|8000|v1|${FQDN}"
V2_CLUSTER="outbound|8000|v2|${FQDN}"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the environment is still what the lab handed over -------------------
for d in probe-v1 probe-v2 shuttle; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the deployments alone"
done

deploy_count=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$deploy_count" -eq 3 ]] || fail "$NS holds $deploy_count deployments, expected exactly 3 - do not add or remove deployments"

for v in v1 v2; do
  lbl=$(kubectl -n "$NS" get deployment "probe-$v" -o jsonpath='{.spec.template.metadata.labels.version}' 2>/dev/null)
  [[ "$lbl" == "$v" ]] || fail "deployment probe-$v now labels its pods version='$lbl', expected '$v'. Do not relabel the pods"
done

port_name=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.ports[0].name}' 2>/dev/null)
[[ "$port_name" == "tcp" ]] || fail "the port of Service $SVC is named '$port_name', expected 'tcp'. Leave the Service unchanged"
selector=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.selector}' 2>/dev/null)
if grep -q 'version' <<<"$selector"; then
  fail "the $SVC Service selector is $selector - it must keep selecting on app only"
fi

# --- 1. the DestinationRule ---------------------------------------------------
dr_name=$(kubectl -n "$NS" get destinationrule -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.host}{"\n"}{end}' 2>/dev/null \
  | awk -v a="$SVC" -v b="$SVC.$NS" -v c="$SVC.$NS.svc" -v d="$FQDN" '$2==a || $2==b || $2==c || $2==d {print $1; exit}')
[[ -n "$dr_name" ]] || fail "no DestinationRule for the host $SVC found in $NS - the tcp route needs it to resolve the subset names"

subset_names=$(kubectl -n "$NS" get destinationrule "$dr_name" -o jsonpath='{.spec.subsets[*].name}' 2>/dev/null)
for s in v1 v2; do
  grep -qw "$s" <<<"$subset_names" || fail "DestinationRule subsets are [$subset_names] - subset '$s' is missing"
  lbl=$(kubectl -n "$NS" get destinationrule "$dr_name" \
    -o jsonpath="{.spec.subsets[?(@.name=='$s')].labels.version}" 2>/dev/null)
  [[ "$lbl" == "$s" ]] || fail "subset '$s' selects version='$lbl', but the probe-$s pods carry version=$s"
done

# --- 2. the VirtualService ----------------------------------------------------
vs_count=$(kubectl -n "$NS" get virtualservice -o jsonpath='{range .items[*]}{.spec.hosts[*]}{"\n"}{end}' 2>/dev/null \
  | grep -cE "^($SVC|$SVC\.$NS|$SVC\.$NS\.svc|$FQDN)( |$)")
[[ "$vs_count" -eq 1 ]] || fail "found $vs_count VirtualService objects for $SVC in $NS, expected exactly one"

vs_name=$(kubectl -n "$NS" get virtualservice -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.hosts[*]}{"\n"}{end}' 2>/dev/null \
  | awk -v a="$SVC" -v b="$SVC.$NS" -v c="$SVC.$NS.svc" -v d="$FQDN" '$2==a || $2==b || $2==c || $2==d {print $1; exit}')

tcp_routes=$(kubectl -n "$NS" get virtualservice "$vs_name" -o jsonpath='{.spec.tcp[*].route[*].destination.subset}' 2>/dev/null)
[[ -n "$tcp_routes" ]] || fail "the VirtualService $vs_name has no tcp route. A port named tcp is routed with the tcp section, not the http section"

match_port=$(kubectl -n "$NS" get virtualservice "$vs_name" -o jsonpath='{.spec.tcp[0].match[0].port}' 2>/dev/null)
[[ "$match_port" == "8000" ]] || fail "the first tcp route matches port '${match_port:-none}', expected 8000 (the Service port)"

w_v1=$(kubectl -n "$NS" get virtualservice "$vs_name" -o jsonpath="{.spec.tcp[0].route[?(@.destination.subset=='v1')].weight}" 2>/dev/null)
w_v2=$(kubectl -n "$NS" get virtualservice "$vs_name" -o jsonpath="{.spec.tcp[0].route[?(@.destination.subset=='v2')].weight}" 2>/dev/null)
[[ "$w_v1" == "80" && "$w_v2" == "20" ]] || fail "the tcp route weighs v1=${w_v1:-none} and v2=${w_v2:-none}, expected 80 and 20"

# --- 3. the shuttle's proxy holds both weighted clusters ----------------------
holds=0
for i in $(seq 1 20); do
  listener=$(istioctl proxy-config listener deploy/shuttle -n "$NS" --port 8000 -o json 2>/dev/null)
  if grep -q 'weightedClusters' <<<"$listener" && grep -qF "$V1_CLUSTER" <<<"$listener" && grep -qF "$V2_CLUSTER" <<<"$listener"; then
    holds=1; break
  fi
  sleep 3
done
[[ "$holds" -eq 1 ]] || fail "the proxy of the shuttle holds no weighted clusters for $V1_CLUSTER and $V2_CLUSTER in its listener for port 8000. Check that the VirtualService reached the proxy, and that the Service port is named tcp"

# --- 4. one reused connection stays on one pod --------------------------------
urls=()
for _ in $(seq 1 15); do urls+=("http://$SVC:8000/hostname"); done
single_pod_runs=0
for run in 1 2 3 4 5; do
  pods=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 20 "${urls[@]}" 2>/dev/null \
    | grep -o 'probe-v[0-9]' | sort -u | wc -l | tr -d ' ')
  [[ "$pods" -eq 1 ]] && single_pod_runs=$((single_pod_runs + 1))
done
[[ "$single_pod_runs" -eq 5 ]] || fail "only $single_pod_runs of 5 runs of 15 requests over one connection were answered by a single pod. A tcp route picks once per connection, so a reused connection must stay on one pod"

# --- 5. 150 fresh connections split close to 80/20 ------------------------------
answers=$(kubectl -n "$NS" exec deploy/shuttle -- sh -c \
  'for i in $(seq 1 150); do curl -s --max-time 5 http://probe-tcp:8000/hostname; echo; done' 2>/dev/null \
  | grep -o 'probe-v[0-9]' | sort | uniq -c)
v1_count=$(awk '$2=="probe-v1"{print $1}' <<<"$answers"); v1_count=${v1_count:-0}
v2_count=$(awk '$2=="probe-v2"{print $1}' <<<"$answers"); v2_count=${v2_count:-0}
total=$((v1_count + v2_count))
[[ "$total" -eq 150 ]] || fail "of 150 fresh connections only $total were answered ($(tr '\n' ' ' <<<"$answers")). Every connection must get an answer from probe-v1 or probe-v2"
{ [[ "$v2_count" -ge 15 && "$v2_count" -le 45 ]]; } || fail "of 150 fresh connections, v1 answered $v1_count and v2 answered $v2_count. With weights 80/20 about 30 should come from v2 (the grader accepts 15 to 45)"

echo "PASS: subsets v1 and v2 select their probe pods, the tcp route matches port 8000 with weights 80/20, the proxy holds both weighted clusters, reused connections stay on one pod, and 150 fresh connections split $v1_count to v1 and $v2_count to v2"
