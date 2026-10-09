# Solution Walkthrough

Mission debrief, astronaut. The relay's chart entry looked right, but two things stood between it and the shuttle. It lived on a planet the shuttle's `Sidecar` never takes configuration from, and its port was declared `TCP`, so the timeout in the flight plan could never apply.

The addresses below come from one test run. Yours are different: read them from `kubectl get pods -n outpost -o wide`.

---

## Step 1: Confirm the failure

Find the two addresses, send one signal to the relay, and read the shuttle's flight log:

```sh
kubectl get pods -n outpost -o wide
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://<RELAY_IP>:8080/get
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

```text
NAME    READY   STATUS    RESTARTS   AGE   IP            ...
relay   1/1     Running   0          1m    10.244.0.10   ...
rogue   1/1     Running   0          1m    10.244.0.9    ...
000
command terminated with exit code 56
[2026-10-08T22:33:47.969Z] "- - -" 0 UH - - "-" 0 0 2 - "-" "-" "-" "-" "-" BlackHoleCluster - 10.244.0.10:8080 10.244.0.6:55252 - -
```

**`BlackHoleCluster`**: the shuttle's proxy refused the signal. The relay pod is running, so this is a mesh decision, not a network failure. As far as the shuttle knows, the relay is not on its star chart.

## Step 2: Find the first fault

List every chart entry, `Sidecar` and flight plan in the cluster:

```sh
kubectl get serviceentry,sidecar,virtualservice -A
```

```text
NAMESPACE   NAME                                     HOSTS                       LOCATION        RESOLUTION   AGE
charts      serviceentry.networking.istio.io/relay   ["relay.outpost.example"]   MESH_EXTERNAL   STATIC       63s

NAMESPACE   NAME                                  AGE
starfleet   sidecar.networking.istio.io/default   63s

NAMESPACE   NAME                                       GATEWAYS   HOSTS                       AGE
starfleet   virtualservice.networking.istio.io/relay              ["relay.outpost.example"]   63s
```

The `ServiceEntry` lives in `charts`, and the shuttle lives in `starfleet`. Look at what the `starfleet` `Sidecar` takes in, and at the shuttle's listeners on port `8080`:

```sh
kubectl get sidecar default -n starfleet -o jsonpath='{.spec.egress[0].hosts}{"\n"}'
istioctl proxy-config listener deploy/shuttle -n starfleet --port 8080
```

```text
["./*","istio-system/*"]
ADDRESSES PORT MATCH DESTINATION
```

The `Sidecar` takes configuration only from `starfleet` and `istio-system`. The entry in `charts` never reaches the shuttle, so its proxy has no listener for the relay, and every signal falls into the black hole. `istioctl analyze` reports nothing here, because each object is valid on its own.

## Step 3: Move the entry to the shuttle's planet

Two fixes work: add `charts/relay.outpost.example` to the `Sidecar`'s `egress.hosts`, or move the entry to `starfleet`. Moving it is cleaner: `./*` takes it in, and `exportTo: ["."]` keeps it from opening the relay for every other planet.

Read the current entry first:

```sh
kubectl get serviceentry relay -n charts -o yaml
```

You should see (trimmed to `spec`):

```text
spec:
  addresses:
  - 10.244.0.10
  endpoints:
  - address: 10.244.0.10
  hosts:
  - relay.outpost.example
  location: MESH_EXTERNAL
  ports:
  - name: tcp
    number: 8080
    protocol: TCP
  resolution: STATIC
```

Replace `<RELAY_IP>` with your relay's address. Save this as `serviceentry-relay.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: relay
  namespace: starfleet
spec:
  hosts:
  - relay.outpost.example
  exportTo:
  - "."
  addresses:
  - <RELAY_IP>
  ports:
  - number: 8080
    name: tcp
    protocol: TCP
  location: MESH_EXTERNAL
  resolution: STATIC
  endpoints:
  - address: <RELAY_IP>
```

Remove the old entry, so exactly one entry charts the relay:

```sh
kubectl delete serviceentry relay -n charts
```

Apply it:

```sh
kubectl apply -f serviceentry-relay.yaml
```

Then check the result, with a fast call and a slow one:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://<RELAY_IP>:8080/get
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://<RELAY_IP>:8080/delay/5
istioctl proxy-config listener deploy/shuttle -n starfleet --port 8080
```

```text
200 0.009402s
200 5.005099s
ADDRESSES   PORT MATCH DESTINATION
10.244.0.10 8080 ALL   Cluster: outbound|8080||relay.outpost.example
```

The relay answers now. But the slow call took the full 5 seconds: the 2 second timeout did not fire. The listener shows why. It matches `ALL` traffic and sends it straight to the cluster, with no HTTP route in between. That is a plain TCP listener.

## Step 4: Fix the second fault

A `VirtualService` timeout only works on a port the proxy reads as HTTP. Change the port in `serviceentry-relay.yaml`:

```yaml
  ports:
  - number: 8080
    name: http
    protocol: HTTP
```

Apply it:

```sh
kubectl apply -f serviceentry-relay.yaml
```

Then check the result, including the rogue:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://<RELAY_IP>:8080/get
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://<RELAY_IP>:8080/delay/5
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://<ROGUE_IP>:8080/get
istioctl proxy-config routes deploy/shuttle -n starfleet --name 8080
```

```text
200 0.015025s
504 2.007174s
502
NAME     VHOST NAME                     DOMAINS                                                       MATCH     VIRTUAL SERVICE
8080     relay.outpost.example:8080     relay.outpost.example, relay.outpost.example. + 1 more...     /*        relay.starfleet
8080     block_all                      *                                                             /*
```

The relay answers `200`, the slow call stops at `504` after 2 seconds, and the rogue gets `502` from the proxy's `block_all` route. The route table shows your flight plan, `relay.starfleet`, attached to the relay.

Now submit:

```sh
astrona submit -c sections/section-070/module-01/labs/lab-02
```

---

## Common Mistakes

- **Turning the `Sidecar` to `ALLOW_ANY`, or deleting it.** The relay answers, but so does every other host, and nothing is charted. The grader checks that the `Sidecar` is still `REGISTRY_ONLY`.
- **Adding `*/*` to the `Sidecar`.** It takes in every namespace's configuration. Add only `charts/relay.outpost.example`, or move the entry.
- **Copying the entry without deleting the old one.** Two entries for one host leave the result to chance. The grader wants exactly one.
- **Fixing only the visibility.** The relay answers `200`, but the slow call still takes 5 seconds. The port must be `HTTP`.
- **Adding the rogue's address to the entry.** The rogue must stay blocked.
- **Creating a Service in `outpost`.** It would put the pods on the star chart through the back door. The grader checks that there is none.
- **Testing too fast.** `kubectl apply` returns before the shuttle's proxy has the new orders. Wait a few seconds and send the signal again.
