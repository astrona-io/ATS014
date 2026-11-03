# Solution Walkthrough

The walkthrough follows the task from top to bottom, and each section ends with a check. The preference for nearby endpoints is one field on the Kubernetes `Service`, `spec.trafficDistribution: PreferClose`. Outlier detection stays in a `DestinationRule`, because the preference alone does not notice an endpoint that fails while it stays ready.

---

## Start: Look At The Starting State

The task says that the `Service` has no `trafficDistribution` and that requests are spread over both zones. Check both, and send 20 requests from `shuttle`. The path `/hostname` returns the name of the pod that served the request:

```sh
kubectl -n starfleet get destinationrule
kubectl get service probe -n starfleet -o jsonpath='{.spec.trafficDistribution}{"\n"}'
for i in $(seq 1 20); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-zone-[ab]'
done | sort | uniq -c
```

`kubectl` finds no `DestinationRule`, the second command prints an empty line, and the count shows both `probe-zone-a` and `probe-zone-b`.

---

## Task Item 1: Set PreferClose On The Service

> **Task item 1:** Make the `probe` Service prefer endpoints that are close to the client, with the Kubernetes `Service` field for it. Keep its selector and port as they are.

Save this as `service-probe.yaml`. It is the same `Service` as before, with one new field:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: probe
  namespace: starfleet
  labels:
    app: probe
spec:
  selector:
    app: probe
  trafficDistribution: PreferClose
  ports:
  - name: http
    port: 8000
    targetPort: 8080
```

Apply it:

```sh
kubectl apply -f service-probe.yaml
```

Check that the field is stored:

```sh
kubectl get service probe -n starfleet -o jsonpath='{.spec.trafficDistribution}{"\n"}'
```

The command prints `PreferClose`.

---

## Task Item 2: Add Outlier Detection

> **Task item 2:** Create a `DestinationRule` named `probe` in the namespace `starfleet` for the host `probe` with outlier detection: `consecutive5xxErrors` is `2`, `interval` is `5s`, `baseEjectionTime` is `30s` and `maxEjectionPercent` is `100`.

Save this as `destinationrule-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  trafficPolicy:
    outlierDetection:
      consecutive5xxErrors: 2
      interval: 5s
      baseEjectionTime: 30s
      maxEjectionPercent: 100
```

Apply it:

```sh
kubectl apply -f destinationrule-probe.yaml
```

Check it:

```sh
kubectl -n starfleet get destinationrule probe -o jsonpath='{.spec.trafficPolicy}{"\n"}'
```

The command prints the `outlierDetection` block with the four values, and no `loadBalancer` block. `maxEjectionPercent: 100` matters: the default of 10 percent cannot eject one endpoint out of two.

---

## Task Item 3: Count Which Pods Answer

> **Task item 3:** Prove that 20 requests from `shuttle` to `http://probe:8000/hostname` are all answered by `probe-zone-a`.

`istiod` needs a few seconds to push the change to the proxy of `shuttle`. Wait, then send 20 requests and count the pods that answered:

```sh
for i in $(seq 1 20); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-zone-[ab]'
done | sort | uniq -c
```

The count shows one line: 20 answers from `probe-zone-a`. `probe-zone-b` is still a healthy endpoint of the Service. You can confirm that in the endpoint list of the proxy:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|8000||probe.starfleet.svc.cluster.local" -o json \
  | grep -E '"zone"|"priority"'
```

Both zones appear, and the `zone-b` endpoint has a higher priority number than the `zone-a` endpoint. The proxy uses it only when the `zone-a` endpoint is not available.

---

## Submit

```sh
astrona submit -c sections/section-040/module-05/labs/lab-02
```

## Mistakes That Fail The Grader

- **Item 1: putting `trafficDistribution` in the `DestinationRule`.** The field belongs to the `Service` under `spec`. A `DestinationRule` has no such field.
- **Item 1: a value other than `PreferClose`.** The grader expects exactly `PreferClose`.
- **Item 2: leaving `maxEjectionPercent` at its default.** The grader expects `100`.
- **Item 2: adding `localityLbSetting`.** The task says the preference must come from the `Service`. The grader fails a `DestinationRule` with a `localityLbSetting`.
- **Item 3: scaling `probe-zone-b` to zero or changing a locality label.** That makes the count pass for the wrong reason. The grader checks three Deployments, their localities and that the proxy sees both zones.
- **Item 3: counting too early.** Wait a few seconds after the change.
