# Solution Walkthrough

This walkthrough follows the task from top to bottom and ends each section with a check. The Start section finds the cause. Item 1 is the fix. Items 2 to 7 prove the result and prove that you changed nothing else.

---

## Start: See The Symptom And Find The Cause

The task says that the `VirtualService` and the `DestinationRule` are both correct, but requests reach both `probe` versions. Send 10 requests with the header `x-mission: test`, and 10 without it, and count which version answered:

```sh
for i in $(seq 1 10); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s -H "x-mission: test" http://probe:8000/hostname | grep -o 'probe-v[0-9]'
done | sort | uniq -c
for i in $(seq 1 10); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-v[0-9]'
done | sort | uniq -c
```

```text
   3 probe-v1
   7 probe-v2
   4 probe-v1
   6 probe-v2
```

Both kinds of requests reach both versions, as if no `VirtualService` existed. Check that the objects exist, and ask `istioctl analyze` for its opinion:

```sh
kubectl -n starfleet get virtualservice,destinationrule
istioctl analyze -n starfleet
```

```text
NAME                                       GATEWAYS   HOSTS       AGE
virtualservice.networking.istio.io/probe              ["probe"]   3s

NAME                                        HOST    AGE
destinationrule.networking.istio.io/probe   probe   3s

✔ No validation issues found when analyzing namespace: starfleet.
```

Both objects exist and the analyzer finds nothing. So check whether the `VirtualService` ever reached the proxy of the client. The proxy is the Envoy container that Istio adds to a pod. Look at the route table of the `shuttle` proxy for port `8000`, and at its listener for the same port. A listener is the part of Envoy that accepts connections on an address and a port:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 8000
istioctl proxy-config listener deploy/shuttle -n starfleet --port 8000
```

```text
NAME     VHOST NAME     DOMAINS     MATCH     VIRTUAL SERVICE
ADDRESSES    PORT MATCH DESTINATION
10.96.80.215 8000 ALL   Cluster: outbound|8000||probe.starfleet.svc.cluster.local
```

The route table is empty. `probe` has no HTTP route, so the `http` rules of the `VirtualService` have nothing to attach to. The listener matches `ALL` connections and sends each one straight to the `probe` cluster without reading the request. That is a plain TCP listener. Your address will differ.

Istio decides the protocol of a port from the Service. It reads `appProtocol` first, and then the `name` of the port. Look at the ports of `probe`:

```sh
kubectl -n starfleet get svc probe -o jsonpath='{.spec.ports}{"\n"}{.spec.selector}{"\n"}'
```

```text
[{"name":"tcp","port":8000,"protocol":"TCP","targetPort":8080}]
{"app":"probe"}
```

The port is named `tcp`, and there is no `appProtocol`. Istio believes the name, so port `8000` is plain TCP. That is the fault.

Before you fix it, save the identity of the objects that must stay unchanged. Items 6 and 7 compare against it:

```sh
kubectl -n starfleet get virtualservice probe -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}'
kubectl -n starfleet get virtualservice probe -o jsonpath='{.spec.http}{"\n"}'
kubectl -n starfleet get destinationrule probe -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid | grep -E "NAME|probe"
kubectl -n starfleet get pods -l app=probe -L version
```

```text
generation=1 uid=eacf2467-524a-43d4-b105-957ec4ae87d7
[{"match":[{"headers":{"x-mission":{"exact":"test"}}}],"route":[{"destination":{"host":"probe","subset":"v2"}}]},{"route":[{"destination":{"host":"probe","subset":"v1"}}]}]
generation=1 uid=fb29d727-7bbf-40c6-80b3-79f3eeb9570b
NAME       UID
probe-v1   663484de-f2b4-4df3-af66-65afe3a1ba34
probe-v2   01d0d81d-c174-4b12-a2d6-f8a23a7a8ea9
NAME                        READY   STATUS    RESTARTS   AGE   VERSION
probe-v1-7888d6c6d5-9876p   2/2     Running   0          19s   v1
probe-v2-58767cc46-h6xwd    2/2     Running   0          19s   v2
```

---

## Item 1: Declare Port 8000 As HTTP

> **Task item 1:** Port `8000` of the `probe` Service is declared as HTTP: its `name` is `http` or starts with `http-`, or its `appProtocol` is `http`.

Rename the port to `http`. Keep the port numbers exactly as they are:

```sh
kubectl -n starfleet patch svc probe --type merge \
  -p '{"spec":{"ports":[{"name":"http","port":8000,"targetPort":8080}]}}'
```

```text
service/probe patched
```

Setting `appProtocol: http` on the port works too, even if the name stays `tcp`, because Istio checks `appProtocol` before the name.

Check item 1:

```sh
kubectl -n starfleet get svc probe -o jsonpath='name={.spec.ports[0].name} appProtocol={.spec.ports[0].appProtocol}{"\n"}'
```

```text
name=http appProtocol=
```

The port name is `http`.

---

## Item 2: The Ports And The Selector Are Unchanged

> **Task item 2:** The port numbers (`8000` to `8080`) and the Service selector stay unchanged.

```sh
kubectl -n starfleet get svc probe -o jsonpath='port={.spec.ports[0].port} targetPort={.spec.ports[0].targetPort} selector={.spec.selector}{"\n"}'
```

```text
port=8000 targetPort=8080 selector={"app":"probe"}
```

The Service still maps `8000` to `8080`, and it still selects `app: probe`. The merge patch changed only the name.

---

## Item 3: `probe` Is Back In The Route Table

> **Task item 3:** `probe` appears again in the route table of the `shuttle` proxy for port `8000` (`istioctl proxy-config routes deploy/shuttle -n starfleet --name 8000`).

`istiod`, the Istio control plane, sends the new configuration to every proxy. Wait a few seconds, then run the command from the task:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 8000
```

```text
NAME     VHOST NAME                                 DOMAINS                                                   MATCH     VIRTUAL SERVICE
8000     probe.starfleet.svc.cluster.local:8000     probe.starfleet.svc.cluster.local., probe + 2 more...     /*        probe.starfleet
8000     probe.starfleet.svc.cluster.local:8000     probe.starfleet.svc.cluster.local., probe + 2 more...     /*        probe.starfleet
```

`probe` is back, with two routes (one for each rule). The `VIRTUAL SERVICE` column shows `probe.starfleet`, so the proxy reads the `VirtualService` again. If the table is still empty, wait a few seconds and run the command again.

---

## Item 4: The `x-mission: test` Header Reaches `probe-v2`

> **Task item 4:** All 10 out of 10 requests sent to `http://probe:8000/hostname` with the header `x-mission: test` are answered by `probe-v2`.

```sh
for i in $(seq 1 10); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s -H "x-mission: test" http://probe:8000/hostname | grep -o 'probe-v[0-9]'
done | sort | uniq -c
```

```text
  10 probe-v2
```

All 10 requests reached `probe-v2`. If every `curl` fails right after the rename, Kubernetes has not yet updated the endpoints. Wait a few seconds and run the loop again.

---

## Item 5: Everyone Else Reaches `probe-v1`

> **Task item 5:** All 10 out of 10 requests sent without that header are answered by `probe-v1`.

```sh
for i in $(seq 1 10); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-v[0-9]'
done | sort | uniq -c
```

```text
  10 probe-v1
```

All 10 requests reached `probe-v1`.

---

## Item 6: The `VirtualService` Is Unchanged

> **Task item 6:** The `VirtualService` keeps its `http` rules unchanged. Do not rewrite it as a `tcp` rule.

Run the two `VirtualService` commands from the Start section again:

```sh
kubectl -n starfleet get virtualservice probe -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}'
kubectl -n starfleet get virtualservice probe -o jsonpath='{.spec.http}{"\n"}'
```

```text
generation=1 uid=eacf2467-524a-43d4-b105-957ec4ae87d7
[{"match":[{"headers":{"x-mission":{"exact":"test"}}}],"route":[{"destination":{"host":"probe","subset":"v2"}}]},{"route":[{"destination":{"host":"probe","subset":"v1"}}]}]
```

The `generation` is still `1`, and the `http` rules are the same. A `tcp` rule could not read the header `x-mission` anyway.

---

## Item 7: The Other Objects Are Unchanged

> **Task item 7:** Leave the `DestinationRule`, the Deployments and their pod labels unchanged. Do not add or remove workloads.

Run the remaining commands from the Start section again:

```sh
kubectl -n starfleet get destinationrule probe -o jsonpath='generation={.metadata.generation} uid={.metadata.uid}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid | grep -E "NAME|probe"
kubectl -n starfleet get pods -l app=probe -L version
```

```text
generation=1 uid=fb29d727-7bbf-40c6-80b3-79f3eeb9570b
NAME       UID
probe-v1   663484de-f2b4-4df3-af66-65afe3a1ba34
probe-v2   01d0d81d-c174-4b12-a2d6-f8a23a7a8ea9
NAME                        READY   STATUS    RESTARTS   AGE   VERSION
probe-v1-7888d6c6d5-9876p   2/2     Running   0          29s   v1
probe-v2-58767cc46-h6xwd    2/2     Running   0          29s   v2
```

The `DestinationRule` still has `generation=1`. The Deployments have the same `UID` values, and the same two pods run with the same labels.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-010/module-01/labs/lab-05
```

The grader sends real requests from the `shuttle` pod.

---

## Mistakes That Fail The Grader

- **Rewriting the `VirtualService` as a `tcp` rule (item 6).** A `tcp` rule cannot read the header `x-mission`. The `VirtualService` was correct. The port declaration was wrong.
- **Changing the port numbers (item 2).** Only the protocol declaration is wrong. The mapping `8000` to `8080` must stay.
- **Changing the Service selector or relabelling the pods (items 2 and 7).** The routing between versions is the job of Istio, not of the Service.
- **Naming the port something Istio does not know, such as `web` (item 1).** Istio then guesses the protocol for each connection. Declare it: `http`, `http-<something>`, or `appProtocol: http`.
- **Testing straight after the rename (items 3 to 5).** The endpoints and the route need a few seconds to reach the proxy of `shuttle`.
