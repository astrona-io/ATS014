#!/usr/bin/env bash
# Confirms that probe-zone-b is in its own zone again (local/zone-b), that
# the shuttle's proxy sees the two probes in two different zones, that the
# DestinationRule and the Service were left alone, and - the part that
# matters - that live requests stay in the shuttle's own zone.

set -u

NS="starfleet"
FQDN="probe.starfleet.svc.cluster.local"
CLUSTER="outbound|8000||$FQDN"

fail() { echo "FAIL: $*"; exit 1; }

signal() {  # one request from the shuttle; prints the probe that answered.
  # A failed kubectl exec (not a failed request) is retried, so a flaky API
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
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Keep every deployment running"
done

deploy_count=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$deploy_count" -eq 3 ]] || fail "$NS holds $deploy_count deployments, expected exactly 3 - do not add or remove deployments"

for n in $(kubectl get nodes -o name); do
  zone=$(kubectl get "$n" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}')
  region=$(kubectl get "$n" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/region}')
  [[ "$region/$zone" == "local/zone-a" ]] || fail "node $n is now in '$region/$zone', expected local/zone-a. Leave the node labels alone: only one deployment is in the wrong zone"
done

shuttle_loc=$(kubectl -n "$NS" get deployment shuttle -o jsonpath='{.spec.template.metadata.labels.istio-locality}' 2>/dev/null)
[[ -z "$shuttle_loc" ]] || fail "the shuttle now carries istio-locality=$shuttle_loc. The shuttle must keep the node's locality, local/zone-a"

a_loc=$(kubectl -n "$NS" get deployment probe-zone-a -o jsonpath='{.spec.template.metadata.labels.istio-locality}' 2>/dev/null)
[[ "$a_loc" == "local.zone-a" ]] || fail "probe-zone-a now declares istio-locality='$a_loc', expected local.zone-a. That deployment was already in the right zone"

selector=$(kubectl -n "$NS" get service probe -o jsonpath='{.spec.selector}' 2>/dev/null)
[[ "$selector" == '{"app":"probe"}' ]] || fail "the probe Service selector is '$selector', expected {\"app\":\"probe\"} - leave the Service alone"

# --- 1. the DestinationRule is unchanged -------------------------------------
kubectl -n "$NS" get destinationrule probe >/dev/null 2>&1 \
  || fail "DestinationRule 'probe' not found in $NS - it was correct, leave it in place"
od=$(kubectl -n "$NS" get destinationrule probe -o jsonpath='{.spec.trafficPolicy.outlierDetection.consecutive5xxErrors}' 2>/dev/null)
[[ -n "$od" ]] || fail "the probe DestinationRule lost its outlierDetection. Without it Istio applies no locality preference - put it back"
lb=$(kubectl -n "$NS" get destinationrule probe -o jsonpath='{.spec.trafficPolicy.loadBalancer.localityLbSetting.enabled}' 2>/dev/null)
[[ "$lb" == "true" ]] || fail "the probe DestinationRule no longer has localityLbSetting.enabled: true - the DestinationRule was correct, the fault is in a deployment's locality label"
dist=$(kubectl -n "$NS" get destinationrule probe -o jsonpath='{.spec.trafficPolicy.loadBalancer.localityLbSetting.distribute}' 2>/dev/null)
[[ -z "$dist" ]] || fail "the probe DestinationRule now has a distribute block. Fixed weights hide the problem - remove it and fix the deployment's locality label instead"

# --- 2. probe-zone-b declares its own zone -----------------------------------
b_loc=$(kubectl -n "$NS" get deployment probe-zone-b -o jsonpath='{.spec.template.metadata.labels.istio-locality}' 2>/dev/null)
[[ -n "$b_loc" ]] || fail "probe-zone-b has no istio-locality label on its pod template, so it takes the node's locality, local/zone-a. Give it its own locality"
[[ "$b_loc" == "local.zone-b" ]] || fail "probe-zone-b declares istio-locality='$b_loc', expected local.zone-b (region.zone, with a dot)"

# --- 3. the shuttle's proxy sees two zones -----------------------------------
zones=""
for i in $(seq 1 30); do
  zones=$(istioctl proxy-config endpoints deploy/shuttle -n "$NS" --cluster "$CLUSTER" -o json 2>/dev/null \
    | grep -o '"zone": "[^"]*"' | sed 's/.*: "//; s/"$//' | sort | tr '\n' ' ' | sed 's/ $//')
  [[ "$zones" == "zone-a zone-b" ]] && break
  sleep 2
done
[[ "$zones" == "zone-a zone-b" ]] || fail "the shuttle's proxy shows probe endpoints in zones [$zones], expected one in zone-a and one in zone-b. If the label is right, restart probe-zone-b so a new pod starts with it"

# --- 4. live requests stay in the shuttle's zone -----------------------------
sleep 3
result=$(for i in $(seq 1 20); do signal; done | sort | uniq -c | awk '{print $2"="$1}' | tr '\n' ' ' | sed 's/ $//')
[[ "$result" == "probe-zone-a=20" ]] || fail "20 requests from the shuttle gave [$result], expected all 20 from probe-zone-a, the shuttle's own zone"

echo "PASS: probe-zone-b is in local/zone-b, the shuttle's proxy sees one probe in each zone, the DestinationRule is unchanged, and all 20 requests stayed in the shuttle's zone"
exit 0
