# Solution Walkthrough

The relay's `ServiceEntry` looked right, but two faults stood between it and the `shuttle` pod. The entry lived in a namespace that the `starfleet` `Sidecar` resource never takes configuration from. And its port was declared `TCP`, so the timeout in the `VirtualService` could never apply.

The addresses below come from one test run. Yours are different: read them from `kubectl get pods -n outpost -o wide`.

---

## Step 1: Confirm the failure

Find the two addresses, send one request to the relay, and read the last line of the `shuttle` pod's access log, where its sidecar proxy writes one line per request or connection:

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

**`BlackHoleCluster`** means the `shuttle` pod's sidecar proxy refused the request. The relay pod is running, so this is a decision of the proxy, not a network failure. As far as this proxy knows, the relay is not in the service registry.

## Step 2: Find the first fault

List every `ServiceEntry`, `Sidecar` and `VirtualService` in the cluster:

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

The `ServiceEntry` lives in `charts`, and the `shuttle` pod lives in `starfleet`. Look at what the `starfleet` `Sidecar` takes in, and at the `shuttle` pod's listeners on port `8080`. A listener is the part of Envoy that accepts connections on one port:

```sh
kubectl get sidecar default -n starfleet -o jsonpath='{.spec.egress[0].hosts}{"\n"}'
istioctl proxy-config listener deploy/shuttle -n starfleet --port 8080
```

```text
["./*","istio-system/*"]
ADDRESSES PORT MATCH DESTINATION
```

The `Sidecar` takes configuration only from `starfleet` and `istio-system`. The entry in `charts` never reaches the `shuttle` pod, so its proxy has no listener for the relay and refuses every request. `istioctl analyze` reports nothing here, because each object is valid on its own.

## Step 3: Move the entry to the caller's namespace

Two fixes work: add `charts/relay.outpost.example` to the `Sidecar`'s `egress.hosts`, or move the entry to `starfleet`. Moving it is cleaner: `./*` takes it in, and `exportTo: ["."]` keeps it from opening the relay for every other namespace.

Read the current entry first:

```sh
kubectl get serviceentry relay -n charts -o yaml
```

You should see (shortened to `spec`):

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

Remove the old entry, so that exactly one entry registers the relay:

```sh
kubectl delete serviceentry relay -n charts
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

A `VirtualService` timeout only works on a port that the sidecar proxy reads as HTTP. Change the port in `serviceentry-relay.yaml` to this:

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

The relay answers `200`, the slow call stops at `504` after 2 seconds, and the rogue gets `502` from the proxy's `block_all` route. The route table shows your `VirtualService`, `relay.starfleet`, attached to the relay's host.

Now submit:

```sh
astrona submit -c sections/section-070/module-01/labs/lab-02
```

---

## Common Mistakes

- **Switching the `Sidecar` to `ALLOW_ANY`, or deleting it.** The relay answers, but so does every other host, and nothing is in the registry on purpose. The grader checks that the `Sidecar` is still `REGISTRY_ONLY`.
- **Adding `*/*` to the `Sidecar`.** It takes in every namespace's configuration. Add only `charts/relay.outpost.example`, or move the entry.
- **Copying the entry without deleting the old one.** Two entries for one host make the result unpredictable. The grader wants exactly one.
- **Fixing only the visibility.** The relay answers `200`, but the slow call still takes 5 seconds. The port must be `HTTP`.
- **Adding the rogue's address to the entry.** The rogue must stay blocked.
- **Creating a Service in `outpost`.** It would put the pods in the registry another way. The grader checks that there is none.
- **Testing too fast.** `kubectl apply` returns before the `shuttle` pod's sidecar proxy has the new configuration. Wait a few seconds and send the request again.
