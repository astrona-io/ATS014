# Solution Walkthrough

Four objects: two instances, one service, one template. The field that decides whether you passed is `location`.

---

## Step 1: See What "Anonymous" Means

```sh
VM1=$(cat /tmp/vm1-ip); VM2=$(cat /tmp/vm2-ip)
echo "vm1=$VM1  vm2=$VM2"
kubectl -n vm-demo get pods -o wide

kubectl -n vm-demo exec deploy/tester -- \
  curl -s -o /dev/null -w "by address: %{http_code}\n" --max-time 10 "http://$VM1:8080/get"
kubectl -n vm-demo exec deploy/tester -- \
  curl -s -o /dev/null -w "by name:    %{http_code}\n" --max-time 10 "http://legacy.vm-demo.svc:8080/get"
istioctl proxy-config cluster deploy/tester -n vm-demo | grep -c legacy
```

```text
vm1=10.244.0.31  vm2=10.244.0.33
NAME            READY   STATUS    IP
legacy-vm-1     1/1     Running   10.244.0.31
legacy-vm-2     1/1     Running   10.244.0.33
tester          2/2     Running   10.244.0.32
by address: 200
by name:    000
0
```

Three facts. Both machines answer by IP. The hostname resolves nowhere. And the proxy has zero clusters for them — no policy, no telemetry, no name.

Note `1/1` for the machines and `2/2` for `tester`: the stand-ins have no sidecar, which is the point.

---

## Step 2: Declare Both Instances

```sh
VM1=$(cat /tmp/vm1-ip); VM2=$(cat /tmp/vm2-ip)
cat > legacy-vm-1-manifests.yaml <<'EOF'
apiVersion: networking.istio.io/v1
kind: WorkloadEntry
metadata:
  name: legacy-vm-1
  namespace: vm-demo
spec:
  address: $VM1
  labels:
    app: legacy-backend
  serviceAccount: legacy-sa
---
apiVersion: networking.istio.io/v1
kind: WorkloadEntry
metadata:
  name: legacy-vm-2
  namespace: vm-demo
spec:
  address: $VM2
  labels:
    app: legacy-backend
  serviceAccount: legacy-sa
EOF
kubectl apply -f legacy-vm-1-manifests.yaml
```

Unquoted heredoc so the addresses are substituted — a VM's address has to be baked in, which is the practical difference between declaring a machine and labelling a pod.

**The same `app: legacy-backend` label on both** is what makes them one service in the next step. **`serviceAccount: legacy-sa`** is what gives each a SPIFFE identity of `spiffe://cluster.local/ns/vm-demo/sa/legacy-sa` — the same shape a pod running under that account would have, and the reason an `AuthorizationPolicy` can name them.

Applying these alone changes nothing observable: there is still no hostname.

---

## Step 3: Make Them A Service

Write the manifest to a file and apply the file. It is the habit the exam rewards — you get something you can re-read, edit and re-apply, instead of a heredoc that is gone the moment it runs.

```sh
cat > serviceentry-legacy.yaml <<'EOF'
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: legacy
  namespace: vm-demo
spec:
  hosts:
    - legacy.vm-demo.svc
  location: MESH_INTERNAL
  resolution: STATIC
  ports:
    - number: 8080
      name: http
      protocol: HTTP
  workloadSelector:
    labels:
      app: legacy-backend
EOF
kubectl apply -f serviceentry-legacy.yaml
```

Three fields differ from module 1's external [`ServiceEntry`](https://istio.io/latest/docs/reference/config/networking/service-entry/), and each matters:

- **`location: MESH_INTERNAL`.** These are your workloads. This is what brings identity, mTLS expectations and `AuthorizationPolicy` coverage. `MESH_EXTERNAL` would give you a working hostname and none of that — which is why the grader checks it explicitly: the configuration *looks* fine either way.
- **`resolution: STATIC`.** The addresses are declared in the entries, so there is nothing to resolve. `DNS` would try to resolve `legacy.vm-demo.svc`, which resolves nowhere, and the selector would be ignored.
- **`workloadSelector`.** The join to the entries, by label, exactly as a Service selects pods.

---

## Step 4: Verify the Registry

```sh
kubectl -n vm-demo exec deploy/tester -- \
  curl -s -o /dev/null -w "by name: %{http_code}\n" --max-time 10 http://legacy.vm-demo.svc:8080/get
istioctl proxy-config cluster deploy/tester -n vm-demo | grep legacy
istioctl proxy-config endpoints deploy/tester -n vm-demo \
  --cluster "outbound|8080||legacy.vm-demo.svc"
```

```text
by name: 200
legacy.vm-demo.svc   8080   -   outbound   STATIC
ENDPOINT             STATUS    OUTLIER CHECK   CLUSTER
10.244.0.31:8080     HEALTHY   OK              outbound|8080||legacy.vm-demo.svc
10.244.0.33:8080     HEALTHY   OK              outbound|8080||legacy.vm-demo.svc
```

The hostname works, and the cluster has **two** endpoints — one per machine, joined by the shared label. Load balancing, outlier detection and locality settings now apply across them exactly as they would across two pods.

If you see only one endpoint, one of the entries has a different label than the selector.

---

## Step 5: The Template For A Real Fleet

```sh
cat > workloadgroup-legacy.yaml <<'EOF'
apiVersion: networking.istio.io/v1
kind: WorkloadGroup
metadata:
  name: legacy
  namespace: vm-demo
spec:
  metadata:
    labels:
      app: legacy-backend
  template:
    serviceAccount: legacy-sa
    ports:
      http: 8080
EOF
kubectl apply -f workloadgroup-legacy.yaml
kubectl -n vm-demo get workloadgroup,workloadentry
```

```text
workloadgroup.networking.istio.io/legacy created
NAME                                             AGE
workloadgroup.networking.istio.io/legacy         3s
workloadentry.networking.istio.io/legacy-vm-1    4m
workloadentry.networking.istio.io/legacy-vm-2    4m
```

Two entries, still the ones you wrote — **no third appeared and none will**. The stand-ins do not run `istio-agent`, have no token and cannot talk to `istiod`, so nothing can register against the group.

Compare the group's `template` with an entry's fields: same service account, same labels, same port. That correspondence is exactly what auto-registration would fill in on a real VM, with the address supplied by the machine itself. [`WorkloadGroup`](https://istio.io/latest/docs/reference/config/networking/workload-group/) is to [`WorkloadEntry`](https://istio.io/latest/docs/reference/config/networking/workload-entry/) what a Deployment is to a Pod.

---

## Common Mistakes

- **`location: MESH_EXTERNAL`.** Routes correctly, gives no identity. The single most likely way to fail this task while appearing to succeed.
- **`resolution: DNS`.** The hostname resolves nowhere and the selector is ignored.
- **Mismatched labels.** The `workloadSelector` and the entries' `labels` must agree — otherwise zero or one endpoint, with no validation error.
- **Omitting `serviceAccount`.** No identity; policies that name principals cannot match.
- **Creating a Service for the pods.** That registers them through the back door and the grader rejects it.
- **Injecting the stand-in pods.** The exercise is to bring an *uninjected* workload into the mesh by declaration.
- **Expecting the `WorkloadGroup` to produce endpoints.** Nothing appears until a real machine registers.
- **Expecting a `WorkloadEntry` to create connectivity.** It declares a workload; the address must already be routable.

---

---

## Reference

The official documentation for everything this task touches — open these rather than trying to recall field names:

- [ServiceEntry API](https://istio.io/latest/docs/reference/config/networking/service-entry/) — `hosts`, `ports`, `location`, `resolution` and `endpoints`
- [WorkloadEntry API](https://istio.io/latest/docs/reference/config/networking/workload-entry/) — `address`, `labels` and `serviceAccount`
- [WorkloadGroup API](https://istio.io/latest/docs/reference/config/networking/workload-group/) — the template and probe fields a registering VM uses
- [Protocol selection](https://istio.io/latest/docs/ops/configuration/traffic-management/protocol-selection/) — how a port's name or `appProtocol` decides what Istio does with it
- [Debugging Envoy and istiod](https://istio.io/latest/docs/ops/diagnostic-tools/proxy-cmd/) — `proxy-status`, `proxy-config` and `x describe` in full
