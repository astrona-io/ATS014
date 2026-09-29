#!/usr/bin/env bash
# Confirms every workload in both namespaces is genuinely meshed: the namespace
# is labelled for injection, nothing opts out, each pod actually carries the
# istio-proxy native sidecar, and the control plane can see all of them.
#
# Note the proxy is checked in .spec.initContainers as well as .spec.containers:
# on Kubernetes 1.28+ Istio injects it as a native sidecar, which lives in the
# init list with restartPolicy: Always.

set -u

fail() { echo "FAIL: $*"; exit 1; }

# --- 0. the workloads are still the ones the lab handed over ----------------
# Parallel lists rather than an associative array: `declare -A` needs bash 4,
# and the grader may run under bash 3.2.
WORKLOADS="mesh-demo/api/nginx mesh-demo/reports/curl legacy-app/billing/nginx"

for entry in $WORKLOADS; do
  ns="${entry%%/*}"; rest="${entry#*/}"; d="${rest%%/*}"; want_img="${rest##*/}"
  kubectl -n "$ns" get deployment "$d" >/dev/null 2>&1 \
    || fail "deployment $d is missing from $ns - the workloads must be brought into the mesh, not replaced"
  img=$(kubectl -n "$ns" get deployment "$d" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
  grep -q "$want_img" <<<"$img" \
    || fail "$ns/$d now runs image '$img' - leave the application containers unchanged"
  reps=$(kubectl -n "$ns" get deployment "$d" -o jsonpath='{.spec.replicas}' 2>/dev/null)
  [[ "$reps" == "1" ]] || fail "$ns/$d has replicas=$reps, expected 1 - leave the replica counts alone"
done

for entry in "mesh-demo/api" "legacy-app/billing"; do
  ns="${entry%%/*}"; svc="${entry##*/}"
  kubectl -n "$ns" get service "$svc" >/dev/null 2>&1 || fail "service $svc is missing from $ns"
done

# --- 1. both namespaces are configured for injection ------------------------
for ns in mesh-demo legacy-app; do
  lbl=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null)
  rev=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.istio\.io/rev}' 2>/dev/null)
  if [[ "$lbl" != "enabled" && -z "$rev" ]]; then
    fail "namespace $ns is not labelled for injection (istio-injection=enabled or istio.io/rev) - pods created there in future would come up without a proxy"
  fi
done

# --- 2. nothing opts out ----------------------------------------------------
for ns in mesh-demo legacy-app; do
  for d in $(kubectl -n "$ns" get deployment -o jsonpath='{.items[*].metadata.name}'); do
    ann=$(kubectl -n "$ns" get deployment "$d" \
      -o jsonpath='{.spec.template.metadata.annotations.sidecar\.istio\.io/inject}' 2>/dev/null)
    [[ "$ann" == "false" ]] \
      && fail "$ns/$d still sets sidecar.istio.io/inject=\"false\" on its pod template - it will keep coming up without a proxy"
  done
done

# --- 3. every live pod actually carries the proxy ---------------------------
# A pod being deleted still reports phase=Running, so a rollout that is still
# draining would otherwise fail a correct answer. Skip anything with a
# deletionTimestamp - it is on its way out and its replacement is what counts.
total=0
for ns in mesh-demo legacy-app; do
  pods=$(kubectl -n "$ns" get pods --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
  [[ -n "$pods" ]] || fail "no running pods found in $ns"
  for p in $pods; do
    deleting=$(kubectl -n "$ns" get pod "$p" -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null)
    [[ -n "$deleting" ]] && continue
    init=$(kubectl -n "$ns" get pod "$p" -o jsonpath='{.spec.initContainers[*].name}' 2>/dev/null)
    main=$(kubectl -n "$ns" get pod "$p" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null)
    if ! grep -qw 'istio-proxy' <<<"$init $main"; then
      fail "pod $ns/$p has no istio-proxy container (init: [$init] containers: [$main]) - it is running outside the mesh. Labelling a namespace does not change pods that already exist"
    fi
    ready=$(kubectl -n "$ns" get pod "$p" -o jsonpath='{.status.containerStatuses[*].ready}' 2>/dev/null)
    grep -q 'false' <<<"$ready" && fail "pod $ns/$p has a container that is not ready"
    total=$((total + 1))
  done
done
[[ "$total" -ge 3 ]] || fail "only $total live pods carry a proxy across both namespaces, expected at least 3"

# --- 4. the control plane can see all of them -------------------------------
status=$(istioctl proxy-status 2>/dev/null) || fail "istioctl proxy-status failed"
for entry in "mesh-demo/api" "mesh-demo/reports" "legacy-app/billing"; do
  ns="${entry%%/*}"; d="${entry##*/}"
  pods=$(kubectl -n "$ns" get pods -l "app=$d" --field-selector=status.phase=Running \
    -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
  [[ -n "$pods" ]] || fail "no running pod for $ns/$d"
  seen=""
  for pod in $pods; do
    deleting=$(kubectl -n "$ns" get pod "$pod" -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null)
    [[ -n "$deleting" ]] && continue
    grep -q "$pod.$ns" <<<"$status" && { seen="$pod"; break; }
  done
  [[ -n "$seen" ]] \
    || fail "no live pod of $ns/$d appears in istioctl proxy-status - its proxy is not connected to the control plane"
done

echo "PASS: both namespaces are injected, nothing opts out, every pod carries the native sidecar, and the control plane sees all of them"
