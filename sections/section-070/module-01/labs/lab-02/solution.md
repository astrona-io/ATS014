# Solution Walkthrough

The `ServiceEntry` of the relay looks right, but two faults stand between it and the `shuttle` pod. The entry lives in a namespace that the `Sidecar` of `starfleet` never takes configuration from. And its port is declared `TCP`, so the timeout in the `VirtualService` can never apply. A `ServiceEntry` adds a host outside the mesh to the service registry, which is the list of hosts that `istiod`, the Istio control plane, knows about. A `Sidecar` resource limits which hosts the sidecar proxies of a namespace know about. The Start section finds both faults. Fix 1 and fix 2 come first, and then the checks of the task prove the result. The addresses in this walkthrough come from one run. Yours are different.

---

## Start: Confirm The Failure And Find The First Fault

Find the two addresses, and send one request to the relay. Then read the last line of the access log of the `shuttle` pod. The sidecar proxy is the Envoy container that Istio adds to the pod, and its access log has one line for each request or connection:

```sh
kubectl get pods -n outpost -o wide | awk '{print $1,$2,$3,$6}'
RELAY=$(kubectl -n outpost get pod relay -o jsonpath='{.status.podIP}')
ROGUE=$(kubectl -n outpost get pod rogue -o jsonpath='{.status.podIP}')
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" --max-time 20 http://$RELAY:8080/get
sleep 2
kubectl -n starfleet logs deploy/shuttle -c istio-proxy --tail=1
```

```text
NAME READY STATUS IP
relay 1/1 Running 10.244.0.7
rogue 1/1 Running 10.244.0.8
000
command terminated with exit code 56
[2026-10-20T22:05:40.834Z] "- - -" 0 UH - - "-" 0 0 0 - "-" "-" "-" "-" "-" BlackHoleCluster - 10.244.0.7:8080 10.244.0.6:57010 - -
```

`BlackHoleCluster` means that the sidecar proxy of the `shuttle` pod refused the request. The relay pod runs, so this is a decision of the proxy and not a failure of the network. As far as this proxy knows, the relay is not in the service registry.

List every `ServiceEntry`, `Sidecar` and `VirtualService` of the cluster. Then look at which hosts the `Sidecar` of `starfleet` takes in, and at the listeners of the `shuttle` proxy on port `8080`. A listener is the part of Envoy that accepts connections on one port:

```sh
kubectl get serviceentry,sidecar,virtualservice -A
kubectl -n starfleet get sidecar default -o jsonpath='{.spec.egress[0].hosts}{"\n"}'
istioctl proxy-config listener deploy/shuttle -n starfleet --port 8080
kubectl -n charts get serviceentry relay -o jsonpath='{.spec}{"\n"}'
```

```text
NAMESPACE   NAME                                     HOSTS                       LOCATION        RESOLUTION   AGE
charts      serviceentry.networking.istio.io/relay   ["relay.outpost.example"]   MESH_EXTERNAL   STATIC       3s

NAMESPACE   NAME                                  AGE
starfleet   sidecar.networking.istio.io/default   3s

NAMESPACE   NAME                                       GATEWAYS   HOSTS                       AGE
starfleet   virtualservice.networking.istio.io/relay              ["relay.outpost.example"]   3s
["./*","istio-system/*"]
ADDRESSES PORT MATCH DESTINATION
{"addresses":["10.244.0.7"],"endpoints":[{"address":"10.244.0.7"}],"hosts":["relay.outpost.example"],"location":"MESH_EXTERNAL","ports":[{"name":"tcp","number":8080,"protocol":"TCP"}],"resolution":"STATIC"}
```

The `ServiceEntry` lives in the namespace `charts`, and the `shuttle` pod lives in `starfleet`. The `Sidecar` takes configuration only from `starfleet` and `istio-system`. So the entry in `charts` never reaches the `shuttle` pod, and its proxy has no listener for port `8080`. `istioctl analyze` reports nothing here, because each object is valid on its own. This is the first fault. The entry also declares its port as `TCP`. That is the second fault, and it shows only after the first one is fixed.

Save the state that the rules of the task say must not change:

```sh
kubectl -n starfleet get sidecar default -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}{.spec}{"\n"}'
kubectl -n starfleet get virtualservice relay -o jsonpath='generation={.metadata.generation} {.spec}{"\n"}'
kubectl -n outpost get pods -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n outpost get svc
```

```text
generation=1 uid=6c07d5e0-b8bd-4e96-8885-6db4957e5743
{"egress":[{"hosts":["./*","istio-system/*"]}],"outboundTrafficPolicy":{"mode":"REGISTRY_ONLY"}}
generation=1 {"hosts":["relay.outpost.example"],"http":[{"route":[{"destination":{"host":"relay.outpost.example"}}],"timeout":"2s"}]}
NAME    UID
relay   a3608a28-3ae5-4a09-bf9d-b13b231b87cf
rogue   8fc142b9-2ecf-4875-9bbf-d104a0f41b7e
No resources found in outpost namespace.
```

---

## Fix 1: Move The Entry To The Namespace Of The Caller

Two fixes work: add `charts/relay.outpost.example` to the `egress.hosts` of the `Sidecar`, or move the entry to `starfleet`. Moving the entry is cleaner. `./*` takes it in, and `exportTo: ["."]` keeps it from opening the relay for every other namespace. Do not change the `Sidecar`: the task says that it stays as it is.

Delete the old entry first, so that exactly one entry registers the relay. Replace `<RELAY_IP>` in the YAML with the address of your relay. To see it, run `echo $RELAY`. Keep the port as `TCP` for now, so that you can see the second fault. Save this as `serviceentry-relay.yaml`:

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

Delete the old entry, and apply the new one:

```sh
kubectl -n charts delete serviceentry relay
kubectl apply -f serviceentry-relay.yaml
```

```text
serviceentry.networking.istio.io "relay" deleted from charts namespace
serviceentry.networking.istio.io/relay created
```

Wait a few seconds for `istiod` to send the change. Then check the result with a fast call and a slow one, and look at the listener:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://$RELAY:8080/get
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://$RELAY:8080/delay/5
istioctl proxy-config listener deploy/shuttle -n starfleet --port 8080
```

```text
200 0.003013s
200 5.004824s
ADDRESSES  PORT MATCH DESTINATION
10.244.0.7 8080 ALL   Cluster: outbound|8080||relay.outpost.example
```

The relay answers now. But the slow call took the full 5 seconds: the timeout of 2 seconds did not fire. The listener shows why. It matches `ALL` traffic and sends it straight to the cluster, with no HTTP route in between. That is a plain TCP listener.

---

## Fix 2: Declare The Port As HTTP

A timeout in a `VirtualService` works only on a port that the sidecar proxy reads as HTTP. Change the port in `serviceentry-relay.yaml` to this:

```yaml
  ports:
  - number: 8080
    name: http
    protocol: HTTP
```

Apply the file again:

```sh
kubectl apply -f serviceentry-relay.yaml
```

```text
serviceentry.networking.istio.io/relay configured
```

---

## Item 1: The Relay Answers

> **Task check 1:** `GET http://<relay-ip>:8080/get` from `deploy/shuttle` in `starfleet` returns **200**.

Wait a few seconds for the proxy, then send the request:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://$RELAY:8080/get
```

```text
200 0.006059s
```

---

## Item 2: The Timeout Applies

> **Task check 2:** `GET http://<relay-ip>:8080/delay/5` from the `shuttle` pod returns **504** after about **2 seconds**: the timeout in the `VirtualService` applies.

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://$RELAY:8080/delay/5
```

```text
504 2.007191s
```

The slow call stops with `504` after 2 seconds. Before fix 2, the same call took 5 seconds.

---

## Item 3: The Rogue Stays Blocked

> **Task check 3:** `GET http://<rogue-ip>:8080/get` from the `shuttle` pod does **not** return 200.

Send the request to the rogue, and read the route table of the proxy for port `8080`:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://$ROGUE:8080/get
istioctl proxy-config routes deploy/shuttle -n starfleet --name 8080
```

```text
502
NAME     VHOST NAME                     DOMAINS                                                       MATCH     VIRTUAL SERVICE
8080     relay.outpost.example:8080     relay.outpost.example, relay.outpost.example. + 1 more...     /*        relay.starfleet
8080     block_all                      *                                                             /*        
```

The rogue gets `502` from the `block_all` route of the proxy. The route table shows your `VirtualService`, `relay.starfleet`, attached to the host of the relay.

---

## Item 4: Exactly One Entry, With An HTTP Port

> **Task check 4:** Exactly one `ServiceEntry` registers `relay.outpost.example`, with port `8080` declared as protocol **`HTTP`**. It must not list the rogue's address.

```sh
kubectl get serviceentry -A
kubectl -n starfleet get serviceentry relay -o jsonpath='{.spec.ports} {.spec.addresses} {.spec.endpoints}{"\n"}'
echo "rogue is $ROGUE"
```

```text
NAMESPACE   NAME    HOSTS                       LOCATION        RESOLUTION   AGE
starfleet   relay   ["relay.outpost.example"]   MESH_EXTERNAL   STATIC       25s
[{"name":"http","number":8080,"protocol":"HTTP"}] ["10.244.0.7"] [{"address":"10.244.0.7"}]
rogue is 10.244.0.8
```

There is one `ServiceEntry` in the whole cluster. Its port is `HTTP`, and it lists only the address of the relay, `10.244.0.7`. The address of the rogue is `10.244.0.8`.

---

## Item 5: The Proxy Has A Listener On Port 8080

> **Task check 5:** The `shuttle` pod's sidecar proxy has a listener on port `8080`.

```sh
istioctl proxy-config listener deploy/shuttle -n starfleet --port 8080
```

```text
ADDRESSES PORT MATCH                                DESTINATION
0.0.0.0   8080 Trans: raw_buffer; App: http/1.1,h2c Route: 8080
0.0.0.0   8080 ALL                                  Non-HTTP/Non-TCP
```

The listener on port `8080` exists, and it has an HTTP route now. Before fix 1, the list was empty.

---

## What Must Not Change

> **Task rules:** The `Sidecar` `default` in `starfleet` stays, with `outboundTrafficPolicy.mode: REGISTRY_ONLY`, no `workloadSelector`, and no `*/*` in `egress.hosts`. Do not add a second `Sidecar`. The `VirtualService` `relay` keeps its host and its `2s` timeout. Leave the pods in `outpost` alone, and do not create a Service there.

Run the four commands from the Start section again, and list the `Sidecar` objects:

```sh
kubectl -n starfleet get sidecar default -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}{.spec}{"\n"}'
kubectl -n starfleet get sidecar
kubectl -n starfleet get virtualservice relay -o jsonpath='generation={.metadata.generation} {.spec}{"\n"}'
kubectl -n outpost get pods -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n outpost get svc
```

```text
generation=1 uid=6c07d5e0-b8bd-4e96-8885-6db4957e5743
{"egress":[{"hosts":["./*","istio-system/*"]}],"outboundTrafficPolicy":{"mode":"REGISTRY_ONLY"}}
NAME      AGE
default   29s
generation=1 {"hosts":["relay.outpost.example"],"http":[{"route":[{"destination":{"host":"relay.outpost.example"}}],"timeout":"2s"}]}
NAME    UID
relay   a3608a28-3ae5-4a09-bf9d-b13b231b87cf
rogue   8fc142b9-2ecf-4875-9bbf-d104a0f41b7e
No resources found in outpost namespace.
```

The output is the same as before. The `Sidecar` and the `VirtualService` still have `generation=1`, there is one `Sidecar`, the pods have the same `UID` values, and there is no Service in `outpost`.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-070/module-01/labs/lab-02
```

The grader calls the relay and the rogue from the `shuttle` pod, and reads the objects.

---

## Mistakes That Fail The Grader

- **Switching the `Sidecar` to `ALLOW_ANY`, or deleting it (rules).** The relay answers, but so does every other host, and nothing is in the registry on purpose.
- **Adding `*/*` to the `Sidecar` (rules).** It takes in the configuration of every namespace. Add only `charts/relay.outpost.example`, or move the entry.
- **Copying the entry without deleting the old one (item 4).** Two entries for one host make the result unpredictable. The task wants exactly one.
- **Fixing only the visibility (items 1 and 2).** The relay answers `200`, but the slow call still takes 5 seconds. The port must be `HTTP`.
- **Adding the address of the rogue to the entry (items 3 and 4).** The rogue must stay blocked.
- **Creating a Service in `outpost` (rules).** It would put the pods in the registry another way.
- **Testing too fast (items 1 to 5).** `kubectl apply` returns before the sidecar proxy of the `shuttle` pod has the new configuration. Wait a few seconds and send the request again.
