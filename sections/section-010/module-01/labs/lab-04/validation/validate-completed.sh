#!/usr/bin/env bash
# Confirms the scout VirtualService was repaired: exactly one
# VirtualService describes the real scout Service, none is left in another
# namespace with the short name, jason's rule comes before the catch-all and names
# a subset that exists, istioctl analyze has nothing to say about it, and - the
# part that matters - live requests reach the right scout version.

set -u

NS="starfleet"
SVC="scout"
FQDN="scout.starfleet.svc.cluster.local"

fail() { echo "FAIL: $*"; exit 1; }

# full name a host resolves to, given the namespace of the object it is in
resolve() {  # $1 = host as written, $2 = namespace of the object
  local h="$1" ns="$2"
  case "$h" in
    *.svc.cluster.local) echo "$h" ;;
    *.svc)               echo "$h.cluster.local" ;;
    *.*)                 echo "$h.svc.cluster.local" ;;
    *)                   echo "$h.$ns.svc.cluster.local" ;;
  esac
}

# --- 0. the environment is still what the lab handed over -------------------
for d in bridge-v1 cargo-v1 navcom-v1 scout-v1 scout-v2 scout-v3 shuttle; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the deployments alone: the fault is in the VirtualService"
done

deploy_count=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$deploy_count" -eq 7 ]] || fail "$NS holds $deploy_count deployments, expected exactly 7 - do not add or remove deployments"

for v in v1 v2 v3; do
  lbl=$(kubectl -n "$NS" get deployment "scout-$v" -o jsonpath='{.spec.template.metadata.labels.version}' 2>/dev/null)
  [[ "$lbl" == "$v" ]] || fail "deployment scout-$v now labels its pods version='$lbl', expected '$v'. Do not relabel the pods"
done

selector=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.selector}' 2>/dev/null)
[[ -n "$selector" ]] || fail "Service $SVC not found in $NS"
grep -q 'version' <<<"$selector" && fail "the $SVC Service selector is $selector - it must keep selecting on app only"

# --- 1. the DestinationRule is unchanged ---------------------------------------
kubectl -n "$NS" get destinationrule "$SVC" >/dev/null 2>&1 \
  || fail "DestinationRule '$SVC' not found in $NS - it was correct, leave it in place"
names=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath='{.spec.subsets[*].name}' 2>/dev/null | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')
[[ "$names" == "v1 v2 v3" ]] || fail "DestinationRule subsets are [$names], expected v1, v2 and v3 - the DestinationRule was correct, leave it unchanged"
for s in v1 v2 v3; do
  lbl=$(kubectl -n "$NS" get destinationrule "$SVC" -o jsonpath="{.spec.subsets[?(@.name=='$s')].labels.version}" 2>/dev/null)
  [[ "$lbl" == "$s" ]] || fail "subset '$s' now selects version='$lbl' - leave the DestinationRule unchanged"
done

# --- 2. exactly one VirtualService describes the real scout Service -------------
# one line per VirtualService: namespace name host1,host2,...
vs_list=$(kubectl get virtualservice -A -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name} {.spec.hosts[*]}{"\n"}{end}' 2>/dev/null)

matches=()
while read -r vns vname hosts; do
  [[ -z "$vns" ]] && continue
  for h in $hosts; do
    full=$(resolve "$h" "$vns")
    if [[ "$h" == "$SVC" && "$vns" != "$NS" ]]; then
      fail "VirtualService $vns/$vname still uses the short host '$SVC' in the namespace '$vns'. There it means $full, a Service that does not exist. Move it to $NS, or write the full name $FQDN"
    fi
    [[ "$full" == "$FQDN" ]] && matches+=("$vns/$vname")
  done
done <<<"$vs_list"

[[ ${#matches[@]} -eq 1 ]] || fail "found ${#matches[@]} VirtualService objects for $FQDN (${matches[*]:-none}), expected exactly one. Keep one VirtualService per host"
VS_NS="${matches[0]%%/*}"; VS_NAME="${matches[0]#*/}"

# --- 3. the rules inside it ------------------------------------------------------
# for every http rule: <jason header value>|<destination host>|<subset>
rules=$(kubectl -n "$VS_NS" get virtualservice "$VS_NAME" -o jsonpath='{range .spec.http[*]}{.match[0].headers.end-user.exact}|{.route[0].destination.host}|{.route[0].destination.subset};{end}' 2>/dev/null)
IFS=';' read -r -a parts <<<"$rules"
[[ ${#parts[@]} -eq 2 ]] || fail "the VirtualService $VS_NS/$VS_NAME has ${#parts[@]} http rules, expected 2: the jason rule, then the catch-all"

IFS='|' read -r r0_hdr r0_host r0_sub <<<"${parts[0]}"
IFS='|' read -r r1_hdr r1_host r1_sub <<<"${parts[1]}"
[[ "$r0_hdr" == "jason" ]] || fail "rule 0 of $VS_NS/$VS_NAME does not match end-user=jason. The proxy stops at the first rule that fits, so the catch-all must come last"
[[ -z "$r1_hdr" ]] || fail "rule 1 of $VS_NS/$VS_NAME has a match. The last rule must be the catch-all with no match"
[[ "$(resolve "$r0_host" "$VS_NS")" == "$FQDN" && "$(resolve "$r1_host" "$VS_NS")" == "$FQDN" ]] \
  || fail "the routes in $VS_NS/$VS_NAME send to '$r0_host' and '$r1_host'. In the namespace $VS_NS these must resolve to $FQDN"
[[ "$r0_sub" == "v2" ]] || fail "the jason rule sends to subset '$r0_sub', expected v2. A subset the DestinationRule does not define gives 503 NC"
[[ "$r1_sub" == "v1" ]] || fail "the catch-all sends to subset '$r1_sub', expected v1"

# --- 4. istioctl analyze has nothing to say about it -------------------------------
analysis=$(istioctl analyze -A 2>&1)
if grep -E 'IST0101|IST0130' <<<"$analysis" | grep -q "VirtualService.*$SVC"; then
  fail "istioctl analyze -A still reports a problem with the scout VirtualService: $(grep -E 'IST0101|IST0130' <<<"$analysis" | grep "$SVC" | head -1)"
fi

# --- 5. live requests ---------------------------------------------------------------
versions() {  # $@ = extra curl args; prints the scout versions of 10 requests
  local i
  for i in $(seq 1 10); do
    kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 10 "$@" "http://$SVC:9080/reviews/0" 2>/dev/null \
      | grep -o 'scout-v[0-9]' || echo "no-answer"
  done | sort | uniq -c | awk '{print $2"="$1}' | tr '\n' ' ' | sed 's/ $//'
}

settle() {  # wait until the new VirtualService has reached the shuttle
  local i
  for i in $(seq 1 30); do
    kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 5 -H "end-user: jason" \
      "http://$SVC:9080/reviews/0" 2>/dev/null | grep -q 'scout-v2' && return 0
    sleep 2
  done
}
settle

jason=$(versions -H "end-user: jason")
[[ "$jason" == "scout-v2=10" ]] || fail "10 requests as jason gave [$jason], expected all 10 from scout-v2. Read the shuttle's access log: no response flag and a random version means the rules never reached it, NC means a subset that does not exist"

others=$(versions)
[[ "$others" == "scout-v1=10" ]] || fail "10 requests without the end-user header gave [$others], expected all 10 from scout-v1"

echo "PASS: one VirtualService ($VS_NS/$VS_NAME) describes $FQDN, jason's rule comes first with subset v2, the catch-all sends to v1, istioctl analyze is clean for it, jason reaches scout-v2 and everyone else scout-v1"
exit 0
