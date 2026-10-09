#!/usr/bin/env bash
# Confirms the probe DestinationRule splits signals from the shuttle's orbit
# 80/20 between zone-a and zone-b with distribute, that the ships, the node
# and the Service were left alone, and - the part that matters - that 100
# live signals land in both orbits in about those shares.

set -u

NS="starfleet"

fail() { echo "FAIL: $*"; exit 1; }

signal() {  # one signal from the shuttle; prints the probe that answered.
  # A failed kubectl exec (not a failed signal) is retried, so a flaky API
  # stream cannot fail the grade.
  local out t
  for t in 1 2 3; do
    out=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 10 http://probe:8000/hostname 2>/dev/null) && break
    sleep 1
  done
  grep -o 'probe-zone-[ab]' <<<"$out" || echo "no-answer"
}

# --- 0. the environment is still what the lab handed over -------------------
for d in shuttle probe-zone-a probe-zone-b; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -eq 1 ]] || fail "$d - deployment missing or not at exactly 1 ready replica in $NS. Leave the ships alone: the split belongs in the DestinationRule"
done

deploy_count=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$deploy_count" -eq 3 ]] || fail "$NS holds $deploy_count deployments, expected exactly 3 - do not add or remove ships"

for z in a b; do
  loc=$(kubectl -n "$NS" get deployment "probe-zone-$z" -o jsonpath='{.spec.template.metadata.labels.istio-locality}' 2>/dev/null)
  [[ "$loc" == "local.zone-$z" ]] || fail "probe-zone-$z declares istio-locality='$loc', expected local.zone-$z. Do not move the ships between orbits"
done

selector=$(kubectl -n "$NS" get service probe -o jsonpath='{.spec.selector}' 2>/dev/null)
[[ "$selector" == '{"app":"probe"}' ]] || fail "the probe Service selector is '$selector', expected {\"app\":\"probe\"} - leave the beacon alone"

# --- 1. the DestinationRule ---------------------------------------------------
kubectl -n "$NS" get destinationrule probe >/dev/null 2>&1 \
  || fail "DestinationRule 'probe' not found in $NS - the split belongs in it"

dr_count=$(kubectl -n "$NS" get destinationrule -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$dr_count" -eq 1 ]] || fail "$NS holds $dr_count DestinationRules, expected only 'probe'"

failover=$(kubectl -n "$NS" get destinationrule probe -o jsonpath='{.spec.trafficPolicy.loadBalancer.localityLbSetting.failover}' 2>/dev/null)
[[ -z "$failover" ]] || fail "the probe DestinationRule has a failover block. distribute and failover cannot be combined - use distribute only"

enabled=$(kubectl -n "$NS" get destinationrule probe -o jsonpath='{.spec.trafficPolicy.loadBalancer.localityLbSetting.enabled}' 2>/dev/null)
[[ "$enabled" == "true" ]] || fail "localityLbSetting.enabled is '$enabled', expected true"

dist=$(kubectl -n "$NS" get destinationrule probe -o jsonpath='{.spec.trafficPolicy.loadBalancer.localityLbSetting.distribute}' 2>/dev/null)
[[ -n "$dist" ]] || fail "the probe DestinationRule has no distribute block, so the shuttle keeps every signal in zone-a and zone-b gets none. Add distribute under localityLbSetting"

froms=$(kubectl -n "$NS" get destinationrule probe -o jsonpath='{.spec.trafficPolicy.loadBalancer.localityLbSetting.distribute[*].from}' 2>/dev/null)
[[ "$froms" == "local/zone-a/*" ]] || fail "distribute has from=[$froms], expected exactly one entry from local/zone-a/* (the shuttle's orbit, region/zone/subzone with slashes)"

weight() {  # $1 = destination locality key; prints its weight in the first distribute entry
  kubectl -n "$NS" get destinationrule probe -o go-template \
    --template "{{with index .spec.trafficPolicy.loadBalancer.localityLbSetting.distribute 0}}{{with index .to \"$1\"}}{{.}}{{end}}{{end}}" 2>/dev/null
}
wa=$(weight 'local/zone-a/*')
wb=$(weight 'local/zone-b/*')
[[ "$wa" == "80" && "$wb" == "20" ]] || fail "distribute sends zone-a=$wa and zone-b=$wb (keys local/zone-a/* and local/zone-b/*), expected 80 and 20"

# --- 2. live signals ------------------------------------------------------------
sleep 5
counts=$(for i in $(seq 1 100); do signal; done | sort | uniq -c)
a=$(awk '$2=="probe-zone-a"{print $1}' <<<"$counts"); a=${a:-0}
b=$(awk '$2=="probe-zone-b"{print $1}' <<<"$counts"); b=${b:-0}
lost=$(awk '$2=="no-answer"{print $1}' <<<"$counts"); lost=${lost:-0}
[[ "$lost" -eq 0 ]] || fail "$lost of 100 signals got no answer from the probe"
(( a >= 65 && a <= 92 && b >= 8 && b <= 35 )) || fail "100 signals gave probe-zone-a=$a and probe-zone-b=$b, expected about 80 and 20. Check that the shuttle's proxy has the new weights"

echo "PASS: the probe DestinationRule distributes signals from local/zone-a/* 80/20 between zone-a and zone-b, the ships are unchanged, and 100 live signals gave probe-zone-a=$a and probe-zone-b=$b"
exit 0
