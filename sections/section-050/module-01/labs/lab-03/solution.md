# Solution Walkthrough

The fault had no `match`, so it hit every client of `navcom`. The fix keeps the fault, but moves it onto a first rule that only requests with `end-user: tester` match, with a plain rule below it for every other request. A `VirtualService` is the Istio object that sets how requests to a host are routed, and a fault is a setting that makes the sidecar proxy return an error or add a delay. Items 1 to 3 describe the repaired object, and items 4 to 6 prove the result.

---

## Start: See The Problem

The task says that every response from `scout` says "Ratings service is currently unavailable". Look at the `VirtualService` objects, print the rule of `navcom`, and send a request without any header through `scout`. The `grep` keeps only the rating part of the answer:

```sh
kubectl -n starfleet get virtualservice
kubectl -n starfleet get virtualservice navcom -o jsonpath='{.spec.http}{"\n"}'
kubectl -n starfleet exec deploy/shuttle -- curl -s http://scout:9080/reviews/0 | grep -o '"rating": {[^}]*}'
```

```text
NAME     GATEWAYS   HOSTS        AGE
navcom              ["navcom"]   0s
scout               ["scout"]    0s
[{"fault":{"abort":{"httpStatus":500,"percentage":{"value":100}}},"route":[{"destination":{"host":"navcom","subset":"v1"}}]}]
"rating": {"error": "Ratings service is currently unavailable"}
"rating": {"error": "Ratings service is currently unavailable"}
```

There are no star ratings, even for a request without a header. The `navcom` object has one rule without a `match` and with an abort of `500` for 100 percent of requests. That is an unscoped fault.

Save the state that item 6 must keep:

```sh
kubectl -n starfleet get virtualservice scout -o jsonpath='generation={.metadata.generation}{"\n"}'
kubectl -n starfleet get virtualservice scout -o jsonpath='{.spec.http}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n starfleet get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port,SELECTOR:.spec.selector
```

```text
generation=1
[{"route":[{"destination":{"host":"scout","subset":"v2"}}]}]
NAME        REPLICAS   UID
bridge-v1   1          c49d0ca5-9466-4398-a92b-25ce0a140d55
cargo-v1    1          2e7b2b73-2ae2-4f28-888a-3656c6b27059
navcom-v1   1          18dfd661-04d7-4b46-aa31-a2956eda2ed4
probe-v1    1          b6f3a269-13e5-4879-b85b-ec16ed3671c2
probe-v2    1          cad1069e-5428-4bdd-9487-615889db59e9
scout-v1    1          c9926bfe-d3db-47b9-8e67-6c17b14fb9db
scout-v2    1          659b9ad2-079f-4d91-81a4-8053efff9ade
scout-v3    1          4a51d811-6610-4556-9d32-900e1746f5bd
shuttle     1          2138b948-c18d-4b94-80c7-2f846cf7d8d5
NAME     PORT   SELECTOR
bridge   9080   map[app:bridge]
cargo    9080   map[app:cargo]
navcom   9080   map[app:navcom]
probe    8000   map[app:probe]
scout    9080   map[app:scout]
```

---

## Items 1 To 3: Scope The Fault To `tester`

> **Task item 1:** The `VirtualService` named `navcom` has **exactly two** `http` rules.
>
> **Task item 2:** The first rule matches the header `end-user` with the exact value **`tester`**, keeps the fault (abort with `500` for every matching request), and routes to subset `v1`.
>
> **Task item 3:** The second rule has no `match` and no `fault`, and routes to subset `v1`.

The three items describe one object, so you write it once. The sidecar proxy reads the rules from top to bottom and uses the first one that matches. So the rule with the fault and the header match goes first, and the plain rule goes second. The sidecar proxy is the Envoy container that Istio adds to each pod. A subset is a named group of pods that a `DestinationRule` defines. Save this as `virtualservice-navcom.yaml`:

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
  - match:
    - headers:
        end-user:
          exact: tester
    fault:
      abort:
        httpStatus: 500
        percentage:
          value: 100
    route:
    - destination:
        host: navcom
        subset: v1
  - route:
    - destination:
        host: navcom
        subset: v1
```

Apply it:

```sh
kubectl apply -f virtualservice-navcom.yaml
```

```text
virtualservice.networking.istio.io/navcom configured
```

Check items 1 to 3. Print each rule with its match, its fault and its subset:

```sh
kubectl -n starfleet get virtualservice navcom \
  -o jsonpath='{range .spec.http[*]}{.match}{" fault="}{.fault}{" -> "}{.route[0].destination.subset}{"\n"}{end}'
```

```text
[{"headers":{"end-user":{"exact":"tester"}}}] fault={"abort":{"httpStatus":500,"percentage":{"value":100}}} -> v1
 fault= -> v1
```

There are exactly two rules. The first matches the header `end-user: tester`, keeps the abort with `500`, and routes to `v1`. The second has no match and no fault, and routes to `v1`.

---

## Item 4: Star Ratings Are Back

> **Task item 4:** A request from `shuttle` to `http://scout:9080/reviews/0` without the header gets star ratings again.

`istiod`, the Istio control plane, sends the new rules to the proxies. Wait a few seconds. Then send the request without a header:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s http://scout:9080/reviews/0 | grep -o '"rating": {[^}]*}'
```

```text
"rating": {"stars": 5, "color": "black"}
"rating": {"stars": 4, "color": "black"}
```

Both reviews show stars again. If you still see the error text, wait a few seconds and send the request again.

---

## Item 5: Test Requests Still Get The Fault

> **Task item 5:** The same request with `end-user: tester` still gets `"Ratings service is currently unavailable"`. A request with `end-user: tester` straight to `http://navcom:9080/ratings/0` gets a `500`, and the access log of `shuttle` marks it with the response flag **`FI`** (fault injected). A request without the header straight to `navcom` gets a `200`.

First send the request with the header through `scout`. The `scout` application copies the `end-user` header of its incoming request onto its own request to `navcom`, and that is why the match works on the second hop:

```sh
kubectl -n starfleet exec deploy/shuttle -- \
  curl -s -H "end-user: tester" http://scout:9080/reviews/0 | grep -o '"rating": {[^}]*}'
```

```text
"rating": {"error": "Ratings service is currently unavailable"}
"rating": {"error": "Ratings service is currently unavailable"}
```

Then send one request with the header and one without a header straight to `navcom`, and read the access log of `shuttle`. The proxy writes the log lines a moment after the requests:

```sh
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" -H "end-user: tester" http://navcom:9080/ratings/0
kubectl -n starfleet exec deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://navcom:9080/ratings/0
sleep 3
kubectl -n starfleet logs deploy/shuttle -c istio-proxy --tail=2
```

```text
500
200
[2026-10-20T21:32:43.812Z] "GET /ratings/0 HTTP/1.1" 500 FI fault_filter_abort - "-" 0 18 0 - "-" "curl/8.11.1" "4c5bd91f-34b3-481b-ba88-3ec95f2e9893" "navcom:9080" "-" outbound|9080|v1|navcom.starfleet.svc.cluster.local - 10.96.121.98:9080 10.244.0.14:53512 - -
[2026-10-20T21:32:43.891Z] "GET /ratings/0 HTTP/1.1" 200 - via_upstream - "-" 0 48 4 3 "-" "curl/8.11.1" "ae5b9fbe-eb77-4a16-baa7-b994456b5732" "navcom:9080" "10.244.0.7:9080" outbound|9080|v1|navcom.starfleet.svc.cluster.local 10.244.0.14:32884 10.96.121.98:9080 10.244.0.14:53528 - -
```

The request with the header fails with `500` and the flag `FI`: the proxy of `shuttle` made the response itself and never sent the request to `navcom`. The request without a header reaches `navcom` and gets `200`.

---

## Item 6: Nothing Else Changed

> **Task item 6:** The `scout` `VirtualService`, the Deployments and the Services stay unchanged.

Run the four commands from the Start section again:

```sh
kubectl -n starfleet get virtualservice scout -o jsonpath='generation={.metadata.generation}{"\n"}'
kubectl -n starfleet get virtualservice scout -o jsonpath='{.spec.http}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n starfleet get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port,SELECTOR:.spec.selector
```

```text
generation=1
[{"route":[{"destination":{"host":"scout","subset":"v2"}}]}]
NAME        REPLICAS   UID
bridge-v1   1          c49d0ca5-9466-4398-a92b-25ce0a140d55
cargo-v1    1          2e7b2b73-2ae2-4f28-888a-3656c6b27059
navcom-v1   1          18dfd661-04d7-4b46-aa31-a2956eda2ed4
probe-v1    1          b6f3a269-13e5-4879-b85b-ec16ed3671c2
probe-v2    1          cad1069e-5428-4bdd-9487-615889db59e9
scout-v1    1          c9926bfe-d3db-47b9-8e67-6c17b14fb9db
scout-v2    1          659b9ad2-079f-4d91-81a4-8053efff9ade
scout-v3    1          4a51d811-6610-4556-9d32-900e1746f5bd
shuttle     1          2138b948-c18d-4b94-80c7-2f846cf7d8d5
NAME     PORT   SELECTOR
bridge   9080   map[app:bridge]
cargo    9080   map[app:cargo]
navcom   9080   map[app:navcom]
probe    8000   map[app:probe]
scout    9080   map[app:scout]
```

The output is the same as before. The `scout` object still has `generation=1` and the same rule, and the Deployments and the Services are unchanged.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-050/module-01/labs/lab-03
```

The grader sends real requests from `shuttle`, reads its access log, and checks the `navcom` `VirtualService`.

---

## Mistakes That Fail The Grader

- **Deleting the fault (items 2 and 5).** Every request gets star ratings again, but the test team loses its fault.
- **Putting the plain rule first (items 1 and 2).** It matches every request, so the proxy never reaches the fault rule below it.
- **Leaving the fault on the plain rule too (item 3).** Then every request still gets the fault.
- **Changing the `scout` `VirtualService` to send requests to `v1` (item 6).** The `scout` `v1` version never calls `navcom`, so the problem only hides.
- **Matching with `prefix` or on another header (item 2).** The task asks for an exact match on `end-user: tester`.
