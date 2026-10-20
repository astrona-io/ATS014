# Solution Walkthrough

Each fault goes on the `VirtualService` of the service that should look slow or broken: the delay on `navcom`, the abort on `probe`. A `VirtualService` is the Istio object that sets how requests to a host are routed. A fault is a setting that makes a sidecar proxy add a delay or return an error. The sidecar proxy of the pod that sends the request applies the fault, so the evidence appears in the access log of that client. The sidecar proxy is the Envoy container that Istio adds to each pod, and the access log is where it writes one line for each request. Item 1 is the delay, item 2 is the abort, and items 3 and 4 prove them. Item 5 proves that you changed nothing else.

---

## Start: Check The Starting State

The task says that there is no fault yet. List the `VirtualService` objects. Then send a request as `jason` to `scout` twice, and one request to `probe`. Save the state that item 5 must keep:

```sh
kubectl -n starfleet get virtualservice
kubectl -n starfleet exec deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" -H "end-user: jason" http://scout:9080/reviews/0
kubectl -n starfleet exec deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" -H "end-user: jason" http://scout:9080/reviews/0
kubectl -n starfleet exec deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://probe:8000/get
kubectl -n starfleet get virtualservice scout -o jsonpath='generation={.metadata.generation}{"\n"}'
kubectl -n starfleet get virtualservice scout -o jsonpath='{.spec.http}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n starfleet get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port,SELECTOR:.spec.selector
```

```text
NAME    GATEWAYS   HOSTS       AGE
scout              ["scout"]   1s
200 0.354971s
200 0.018812s
200 0.012926s
generation=1
[{"match":[{"headers":{"end-user":{"exact":"jason"}}}],"route":[{"destination":{"host":"scout","subset":"v2"}}]},{"route":[{"destination":{"host":"scout","subset":"v1"}}]}]
NAME        REPLICAS   UID
bridge-v1   1          1152dfdb-ffdc-4c22-8988-bce2b62ef794
cargo-v1    1          02b9131f-1223-49a1-a9e9-61a9883e3736
navcom-v1   1          86bda7f3-298b-46b5-9885-388d17fbc826
probe-v1    1          c3c68e7a-1c43-47c2-9726-38ea37ba1d1d
probe-v2    1          b6a1d611-ddea-420a-b89e-5959818d497b
scout-v1    1          fa5fe363-1749-472c-90ae-e4de81518701
scout-v2    1          6072df9f-eb72-4f69-b8f1-fce1c4605a11
scout-v3    1          7a8520a1-800b-4d13-abb1-7b63cdcae488
shuttle     1          1d5be3cf-cf12-4111-909c-67ea827954dc
NAME     PORT   SELECTOR
bridge   9080   map[app:bridge]
cargo    9080   map[app:cargo]
navcom   9080   map[app:navcom]
probe    8000   map[app:probe]
scout    9080   map[app:scout]
```

Only the `scout` `VirtualService` exists. The first request is slow because the pods are still warming up. After that, every request gets a response in about 10 to 20 milliseconds.

---

## Item 1: Delay Every Request To `navcom`

> **Task item 1:** A `VirtualService` named `navcom` delays **every** request to `navcom` by **2 seconds** with `fault.delay`, and routes it to subset `v1`. It has no abort.

Use `fixedDelay: 2s` at 100%, and route to the subset `v1`. A subset is a named group of pods that the `DestinationRule` of `navcom` defines. Save this as `virtualservice-navcom.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: navcom
  namespace: starfleet
spec:
  hosts:
  - navcom
  http:
  - fault:
      delay:
        percentage:
          value: 100
        fixedDelay: 2s
    route:
    - destination:
        host: navcom
        subset: v1
```

Apply it:

```sh
kubectl apply -f virtualservice-navcom.yaml
```

```text
virtualservice.networking.istio.io/navcom created
```

Check item 1. Print the host and the rules:

```sh
kubectl -n starfleet get virtualservice navcom -o jsonpath='{.spec.hosts} {.spec.http}{"\n"}'
```

```text
["navcom"] [{"fault":{"delay":{"fixedDelay":"2s","percentage":{"value":100}}},"route":[{"destination":{"host":"navcom","subset":"v1"}}]}]
```

The object is for the host `navcom`. It has a delay of `2s` for 100 percent of requests, it has no `abort`, and it routes to subset `v1`.

---

## Item 2: Abort Every Request To `probe`

> **Task item 2:** A `VirtualService` named `probe` fails **every** request to `probe` with **503** with `fault.abort`. It has no delay.

Use `abort` with `httpStatus: 503` at 100%. Save this as `virtualservice-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe
  namespace: starfleet
spec:
  hosts:
  - probe
  http:
  - fault:
      abort:
        percentage:
          value: 100
        httpStatus: 503
    route:
    - destination:
        host: probe
```

Apply it:

```sh
kubectl apply -f virtualservice-probe.yaml
```

```text
virtualservice.networking.istio.io/probe created
```

Check item 2:

```sh
kubectl -n starfleet get virtualservice probe -o jsonpath='{.spec.hosts} {.spec.http}{"\n"}'
```

```text
["probe"] [{"fault":{"abort":{"httpStatus":503,"percentage":{"value":100}}},"route":[{"destination":{"host":"probe"}}]}]
```

The object is for the host `probe`. It has an abort with status `503` for 100 percent of requests, and it has no `delay`.

---

## Item 3: `jason` Is Slow, And The Log Shows `DI`

> **Task item 3:** A request from `shuttle` to `http://scout:9080/reviews/0` with the header `end-user: jason` still gets a **200**, about 2 seconds late, and the access log of `scout-v2` marks its request to `navcom` with the response flag **`DI`** (delay injected).

Only `scout` `v2` and `v3` call `navcom`, and the rule of `scout` sends `jason` to `v2`. `istiod`, the Istio control plane, sends the new rules to the proxies. Wait a few seconds. Then send the request as `jason`, and read the access log of `scout-v2`:

```sh
kubectl -n starfleet exec deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" -H "end-user: jason" http://scout:9080/reviews/0
sleep 3
kubectl -n starfleet logs deploy/scout-v2 -c istio-proxy --tail=6 | grep ratings | tail -1
```

```text
200 2.055833s
[2026-10-20T21:29:42.208Z] "GET /ratings/0 HTTP/1.1" 200 DI via_upstream - "-" 0 48 2010 9 "-" "curl/8.11.1" "5d1af26e-a0b0-488b-b04a-302f36367ab8" "navcom:9080" "10.244.0.7:9080" outbound|9080|v1|navcom.starfleet.svc.cluster.local 10.244.0.9:39232 10.96.38.116:9080 10.244.0.9:43102 - -
```

The status is still `200`, two seconds late. The response flag `DI` ("delay injected") is in the access log of `scout-v2`: its sidecar proxy held the request, and the whole request took 2010 milliseconds. `navcom` itself answered in 9. If the line is not there yet, wait a moment, because the proxy writes the log line a moment after the request.

---

## Item 4: `probe` Fails At Once, And Never Receives The Request

> **Task item 4:** A request from `shuttle` to `http://probe:8000/get` gets a **503** at once, the access log of `shuttle` marks it with the response flag **`FI`** (fault injected), and `probe` never receives it.

Send one request. Read the access log of `shuttle`, and count the `GET /get` lines in the logs of the probe pods before and after:

```sh
BEFORE=$(kubectl -n starfleet logs -l app=probe -c istio-proxy --tail=-1 | grep -c 'GET /get')
kubectl -n starfleet exec deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://probe:8000/get
sleep 3
kubectl -n starfleet logs deploy/shuttle -c istio-proxy --tail=3 | grep probe | tail -1
AFTER=$(kubectl -n starfleet logs -l app=probe -c istio-proxy --tail=-1 | grep -c 'GET /get')
echo "probe received: $((AFTER - BEFORE))"
```

```text
503 0.003097s
[2026-10-20T21:29:47.457Z] "GET /get HTTP/1.1" 503 FI fault_filter_abort - "-" 0 18 0 - "-" "curl/8.11.1" "9579defd-0504-41d0-a488-4682f789c20a" "probe:8000" "-" outbound|8000||probe.starfleet.svc.cluster.local - 10.96.58.207:8000 10.244.0.14:36196 - -
probe received: 0
```

The response is a `503` after 3 milliseconds. The access log of `shuttle` shows `FI` ("fault injected") and `fault_filter_abort`. The address of the destination pod is `"-"`, because the request never left the `shuttle` pod. The probe pods received 0 requests. The evidence for an aborted request is in the log of the client, not in the log of the server.

---

## Item 5: Nothing Else Changed

> **Task item 5:** The `scout` `VirtualService`, the Deployments and the Services stay unchanged.

Run the four commands from the Start section again that print the `scout` object, the Deployments and the Services:

```sh
kubectl -n starfleet get virtualservice scout -o jsonpath='generation={.metadata.generation}{"\n"}'
kubectl -n starfleet get virtualservice scout -o jsonpath='{.spec.http}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n starfleet get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port,SELECTOR:.spec.selector
```

```text
generation=1
[{"match":[{"headers":{"end-user":{"exact":"jason"}}}],"route":[{"destination":{"host":"scout","subset":"v2"}}]},{"route":[{"destination":{"host":"scout","subset":"v1"}}]}]
NAME        REPLICAS   UID
bridge-v1   1          1152dfdb-ffdc-4c22-8988-bce2b62ef794
cargo-v1    1          02b9131f-1223-49a1-a9e9-61a9883e3736
navcom-v1   1          86bda7f3-298b-46b5-9885-388d17fbc826
probe-v1    1          c3c68e7a-1c43-47c2-9726-38ea37ba1d1d
probe-v2    1          b6a1d611-ddea-420a-b89e-5959818d497b
scout-v1    1          fa5fe363-1749-472c-90ae-e4de81518701
scout-v2    1          6072df9f-eb72-4f69-b8f1-fce1c4605a11
scout-v3    1          7a8520a1-800b-4d13-abb1-7b63cdcae488
shuttle     1          1d5be3cf-cf12-4111-909c-67ea827954dc
NAME     PORT   SELECTOR
bridge   9080   map[app:bridge]
cargo    9080   map[app:cargo]
navcom   9080   map[app:navcom]
probe    8000   map[app:probe]
scout    9080   map[app:scout]
```

The output is the same as before. The `scout` object still has `generation=1`, and the Deployments and the Services are unchanged.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-050/module-01/labs/lab-02
```

The grader sends real requests from `shuttle`, reads the access logs of `shuttle`, `scout-v2` and `probe`, and checks both `VirtualService` objects.

---

## Mistakes That Fail The Grader

- **Putting the delay on the `scout` `VirtualService` (item 1).** That delays the request from `shuttle` to `scout`, and the access log of `scout-v2` never shows `DI`. The delay belongs on `navcom`, the service that should look slow.
- **Using an abort for `navcom` or a delay for `probe` (items 1 and 2).** `navcom` must be slow but still answer. `probe` must fail at once.
- **Setting `percentage.value` below 100 (items 1 and 2).** Every request must get the fault.
- **Changing the `scout` `VirtualService` (item 5).** Requests from `jason` must still go to `scout` `v2`, the version that calls `navcom`.
- **Looking for the aborted request in the access log of `probe` (item 4).** It never arrives there. The evidence is in the access log of `shuttle`.
