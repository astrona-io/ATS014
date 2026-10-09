#!/usr/bin/env bash
# Confirms the cargo beacon (Service) selects the cargo ships again, that the
# ships themselves were left alone, that the shuttle's proxy holds a healthy
# cargo endpoint, and - the part that matters - that live signals to cargo and
# the bridge page succeed.

set -u

NS="starfleet"
SVC="cargo"
FQDN="cargo.starfleet.svc.cluster.local"

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the ships are still what the lab handed over --------------------------
for d in bridge-v1 cargo-v1 navcom-v1 scout-v1 scout-v2 scout-v3 shuttle; do
  ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ -n "$ready" && "$ready" -ge 1 ]] || fail "$d - deployment missing or has no ready replicas in $NS. Leave the ships flying: the fault is not in them"
done

deploy_count=$(kubectl -n "$NS" get deployments -o name 2>/dev/null | wc -l | tr -d ' ')
[[ "$deploy_count" -eq 7 ]] || fail "$NS holds $deploy_count deployments, expected exactly 7 - do not add or remove ships"

pod_app=$(kubectl -n "$NS" get deployment cargo-v1 -o jsonpath='{.spec.template.metadata.labels.app}' 2>/dev/null)
[[ "$pod_app" == "cargo" ]] || fail "deployment cargo-v1 now labels its pods app='$pod_app', expected 'cargo'. Do not relabel the ships - fix the beacon that looks for them"

# --- 1. the cargo Service -------------------------------------------------------
kubectl -n "$NS" get service "$SVC" >/dev/null 2>&1 || fail "Service '$SVC' not found in $NS - repair it, do not delete it"

sel=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.selector.app}' 2>/dev/null)
[[ "$sel" == "cargo" ]] || fail "the cargo Service selects app='$sel', but the cargo pods carry app=cargo. A selector that matches no pod is accepted and leaves the Service with no endpoints: 503 UH"

port=$(kubectl -n "$NS" get service "$SVC" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
[[ "$port" == "9080" ]] || fail "the cargo Service port is '$port', expected 9080 - leave the port unchanged"

# --- 2. the shuttle's proxy holds a healthy cargo endpoint ------------------------
ok=""
for i in $(seq 1 30); do
  if istioctl proxy-config endpoints deploy/shuttle -n "$NS" \
       --cluster "outbound|9080||$FQDN" 2>/dev/null | grep -q HEALTHY; then
    ok=1; break
  fi
  sleep 2
done
[[ -n "$ok" ]] || fail "the shuttle's proxy has no healthy endpoint in the cargo cluster (outbound|9080||$FQDN). Compare the Service selector with the cargo pods' labels"

# --- 3. live signals --------------------------------------------------------------
codes=""
for i in $(seq 1 10); do
  c=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$SVC:9080/details/0" 2>/dev/null)
  codes="$codes $c"
done
n200=$(tr ' ' '\n' <<<"$codes" | grep -c '^200$')
[[ "$n200" -eq 10 ]] || fail "10 signals to http://cargo:9080/details/0 gave [$codes ], expected 200 every time. Read the flag in the shuttle's flight log"

page=$(kubectl -n "$NS" exec deploy/shuttle -- curl -s --max-time 10 "http://bridge:9080/productpage" 2>/dev/null)
grep -q 'Error fetching product details' <<<"$page" && fail "the bridge page still says 'Error fetching product details' - the bridge cannot reach cargo yet"
grep -q 'ISBN-10' <<<"$page" || fail "the bridge page does not show the product details (no ISBN-10 found) - the bridge cannot reach cargo yet"

echo "PASS: the cargo Service selects the cargo ships again, the shuttle's proxy holds a healthy cargo endpoint, 10 of 10 signals to cargo answered 200, and the bridge page shows the product details"
exit 0
