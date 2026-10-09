# Solution Walkthrough

Mission debrief, astronaut. Every ship was fine. The beacon that is supposed to find the supply ship was looking for a name no ship carries, so it found nothing, and every signal to it had nowhere to land.

---

## Step 1: Does it exist?

Start at the top of the checklist. Confirm the failure, then list the ships and beacons:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s http://bridge:9080/productpage | grep -oE 'Error fetching product details|ISBN-10'
```

```text
Error fetching product details
```

```sh
kubectl -n starfleet get deploy,svc
```

```text
NAME                        READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/bridge-v1   1/1     1            1           75s
deployment.apps/cargo-v1    1/1     1            1           75s
deployment.apps/navcom-v1   1/1     1            1           75s
deployment.apps/scout-v1    1/1     1            1           75s
deployment.apps/scout-v2    1/1     1            1           75s
deployment.apps/scout-v3    1/1     1            1           75s
deployment.apps/shuttle     1/1     1            1           75s

NAME             TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/bridge   ClusterIP   10.96.102.2     <none>        9080/TCP   75s
service/cargo    ClusterIP   10.96.157.127   <none>        9080/TCP   75s
service/navcom   ClusterIP   10.96.235.205   <none>        9080/TCP   75s
service/scout    ClusterIP   10.96.4.24      <none>        9080/TCP   75s
```

Everything exists, and every ship is ready. `kubectl get` cannot see the problem.

## Step 2: Do the objects agree?

```sh
istioctl analyze -n starfleet
```

```text
✔ No validation issues found when analyzing namespace: starfleet.
```

Clean, because there are no Istio objects to check against each other. A clean result is not proof: the problem is one rung lower.

## Step 3: What really happened to the signal?

Send one signal to cargo, wait a second, and read the shuttle's flight log:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}\n' http://cargo:9080/details/0
kubectl -n starfleet logs deploy/shuttle -c istio-proxy --tail=1
```

```text
503
[2026-10-08T20:06:53.230Z] "GET /details/0 HTTP/1.1" 503 UH no_healthy_upstream - "-" 0 19 0 - "-" "curl/8.11.1" "b4709687-2435-427d-8cfe-bc70757879ae" "cargo:9080" "-" outbound|9080||cargo.starfleet.svc.cluster.local - 10.96.157.127:9080 10.244.0.12:43192 - default
```

The flag is **`UH`**, "no healthy upstream": the destination `outbound|9080||cargo…` is known, but it holds no ship. The chosen ship is `"-"`: there was nobody to choose. This is a destination problem, not a routing problem.

## Step 4: What does the proxy hold?

Ask the shuttle's proxy for the endpoints in the cargo cluster, and Kubernetes for the cargo EndpointSlice:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|9080||cargo.starfleet.svc.cluster.local"
kubectl -n starfleet get endpointslices -l kubernetes.io/service-name=cargo
```

```text
ENDPOINT     STATUS     OUTLIER CHECK     CLUSTER
NAME          ADDRESSTYPE   PORTS     ENDPOINTS   AGE
cargo-mgzfg   IPv4          <unset>   <unset>     78s
```

Both are empty. The cargo ship is running, but the cargo beacon has no endpoints. A Service gets its endpoints from its selector, so compare the selector with the cargo pod's labels:

```sh
kubectl -n starfleet get service cargo -o jsonpath='{.spec.selector}{"\n"}'
kubectl -n starfleet get pods --show-labels | grep cargo
```

```text
{"app":"carg0"}
cargo-v1-6f787f8bd5-24jvp    2/2     Running   0          78s   app=cargo,pod-template-hash=6f787f8bd5,security.istio.io/tlsMode=istio,service.istio.io/canonical-name=cargo,service.istio.io/canonical-revision=v1,version=v1
```

There it is: the beacon looks for `app=carg0`, with a zero, and the ship carries `app=cargo`. A selector that matches no pod is valid, so nothing ever complained.

## Step 5: Fix the beacon

This is one value in the Service, so a short `kubectl patch` is enough:

```sh
kubectl -n starfleet patch service cargo --type merge \
  -p '{"spec":{"selector":{"app":"cargo"}}}'
```

```text
service/cargo patched
```

## Step 6: Prove it

Wait a few seconds, then check the proxy, a signal, and the bridge page:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|9080||cargo.starfleet.svc.cluster.local"
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w '%{http_code}\n' http://cargo:9080/details/0
kubectl -n starfleet exec deploy/shuttle -- curl -s http://bridge:9080/productpage | grep -oE 'Error fetching product details|ISBN-10'
```

```text
ENDPOINT            STATUS      OUTLIER CHECK     CLUSTER
10.244.0.6:9080     HEALTHY     OK                outbound|9080||cargo.starfleet.svc.cluster.local
200
ISBN-10
```

The cargo cluster holds a healthy ship again, the signal answers `200`, and the bridge page shows the product details. Submit:

```sh
astrona submit -c sections/section-000/module-01/labs/lab-02
```

```text
PASS: the cargo Service selects the cargo ships again, the shuttle's proxy holds a healthy cargo endpoint, 10 of 10 signals to cargo answered 200, and the bridge page shows the product details
```

---

## Mistakes that fail the grader

- **Relabelling the cargo pods to `app: carg0`.** The bridge would work, but the ships were never the problem. The grader checks that the pods still carry `app: cargo`.
- **Deleting and recreating the Service with a different port.** The grader expects port `9080`.
- **Stopping at `istioctl analyze`.** It stays clean the whole time. The flag `UH` and the empty endpoint list are what point at the beacon.
- **Testing straight after the patch.** The new endpoint takes a few seconds to reach the shuttle's proxy. Wait, then check again.
