# Solution Walkthrough

The timeout was on the wrong rule. A rule with a `fault` ignores its own `timeout`, so the 1-second limit on the delay rule of `navcom` never fired. The fix has two parts. Items 1 and 2 clean up the `navcom` `VirtualService`. Items 3 and 4 put the timeout on the route that `shuttle` really uses. Items 5 to 7 prove the result. A `VirtualService` is the Istio object that sets how requests to a host are routed, including timeouts and faults.

---

## Start: See The Problem

The task says that the `jason` requests wait more than 3 seconds. Send one request with the header `end-user: jason` from the `shuttle` pod, and time it. Then print the two `VirtualService` objects and the identity of the workloads. Items 3 and 7 compare against them:

```sh
kubectl -n starfleet exec deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" -H "end-user: jason" http://scout:9080/reviews/0
kubectl -n starfleet get virtualservice
kubectl -n starfleet get virtualservice navcom -o jsonpath='{.spec.http}{"\n"}'
kubectl -n starfleet get virtualservice scout -o jsonpath='{.spec.http}{"\n"}'
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n starfleet get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port,SELECTOR:.spec.selector
```

```text
200 3.508907s
NAME     GATEWAYS   HOSTS        AGE
navcom              ["navcom"]   5s
scout               ["scout"]    5s
[{"fault":{"delay":{"fixedDelay":"3s","percentage":{"value":100}}},"route":[{"destination":{"host":"navcom","subset":"v1"}}],"timeout":"1s"}]
[{"match":[{"headers":{"end-user":{"exact":"jason"}}}],"route":[{"destination":{"host":"scout","subset":"v2"}}]},{"route":[{"destination":{"host":"scout","subset":"v1"}}]}]
NAME        REPLICAS   UID
bridge-v1   1          6c7212bf-c579-46d1-bdae-7703ff603f6c
cargo-v1    1          b6935795-3b38-4700-8025-7d55556db24d
navcom-v1   1          f0f67a29-1d24-4d34-93c8-36aeb4916188
scout-v1    1          b769b772-d4c5-4a36-ac90-51806ac3ac4a
scout-v2    1          7e2a6599-12d5-4e6d-8830-63ac9d4602d8
scout-v3    1          b3071e28-ef21-43f8-a978-766ee0765d57
shuttle     1          70178054-e96b-43c1-9c13-9f1829bf39a1
NAME     PORT   SELECTOR
bridge   9080   map[app:bridge]
cargo    9080   map[app:cargo]
navcom   9080   map[app:navcom]
scout    9080   map[app:scout]
```

The request takes more than 3 seconds, although a `timeout` of `1s` exists. In the `navcom` object, that `timeout` sits on the same rule as the delay fault `fixedDelay: 3s`. A delay fault is a setting that makes the sidecar proxy hold each request before it forwards it. A sidecar proxy is the Envoy container that Istio adds to each pod. The rule has a `fault`, so Istio ignores its `timeout`.

---

## Items 1 And 2: Keep The Delay, Remove The Timeout On `navcom`

> **Task item 1:** The `navcom` `VirtualService` keeps the delay fault exactly as it is: `fixedDelay: 3s` for 100 percent of requests, routed to subset `v1`.
>
> **Task item 2:** The `navcom` `VirtualService` has **no** `timeout` on any rule.

The delay must stay. It makes `navcom` slow on purpose, so that you can test the timeout. Only the `timeout` goes away. Save this as `virtualservice-navcom.yaml`:

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
        fixedDelay: 3s
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
virtualservice.networking.istio.io/navcom configured
```

Check items 1 and 2. Print the whole `http` list, and then print the delay and the timeout:

```sh
kubectl -n starfleet get virtualservice navcom -o jsonpath='{.spec.http}{"\n"}'
kubectl -n starfleet get virtualservice navcom -o jsonpath='delay={.spec.http[0].fault.delay} timeout=[{.spec.http[0].timeout}]{"\n"}'
```

```text
[{"fault":{"delay":{"fixedDelay":"3s","percentage":{"value":100}}},"route":[{"destination":{"host":"navcom","subset":"v1"}}]}]
delay={"fixedDelay":"3s","percentage":{"value":100}} timeout=[]
```

The delay is `3s` for 100 percent of requests, the route goes to subset `v1`, and the timeout is empty. The `jason` request is still slow, because the timeout is not in the right place yet:

```sh
kubectl -n starfleet exec deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" -H "end-user: jason" http://scout:9080/reviews/0
```

```text
200 3.106689s
```

---

## Items 3 And 4: Put The Timeout On The `jason` Rule Of `scout`

> **Task item 3:** The `scout` `VirtualService` still sends `end-user: jason` to subset `v2` in its first rule, and everything else to subset `v1` in its last rule.
>
> **Task item 4:** The `jason` rule in the `scout` `VirtualService` has a `timeout` of **at most 1 second**.

The requests from `shuttle` go to `scout` first. So the sidecar proxy of `shuttle` applies the timeout of the `scout` route. Keep both rules as they are, and add `timeout: 1s` to the first one. Save this as `virtualservice-scout.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: scout
  namespace: starfleet
spec:
  hosts:
  - scout
  http:
  - match:
    - headers:
        end-user:
          exact: jason
    route:
    - destination:
        host: scout
        subset: v2
    timeout: 1s
  - route:
    - destination:
        host: scout
        subset: v1
```

Apply it:

```sh
kubectl apply -f virtualservice-scout.yaml
```

```text
virtualservice.networking.istio.io/scout configured
```

Check items 3 and 4. Print each rule with its match, its subset and its timeout:

```sh
kubectl -n starfleet get virtualservice scout \
  -o jsonpath='{range .spec.http[*]}{.match}{" -> "}{.route[0].destination.subset}{" timeout=["}{.timeout}{"]\n"}{end}'
```

```text
[{"headers":{"end-user":{"exact":"jason"}}}] -> v2 timeout=[1s]
 -> v1 timeout=[]
```

The first rule sends `end-user: jason` to `v2` with a timeout of `1s`. The last rule sends everything else to `v1`, with no timeout.

---

## Item 5: `jason` Gets A 504 After About One Second

> **Task item 5:** A request from `shuttle` to `http://scout:9080/reviews/0` with `end-user: jason` gets a **504** after about one second, and the `shuttle` sidecar proxy's access log shows it with the response flag **`UT`**.

`istiod`, the Istio control plane, sends the new rule to the proxy. Wait a few seconds. Then send the request, and read the access log of the `shuttle` proxy:

```sh
kubectl -n starfleet exec deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" -H "end-user: jason" http://scout:9080/reviews/0
sleep 2
kubectl -n starfleet logs deploy/shuttle -c istio-proxy --tail=3 | grep '504 UT'
```

```text
504 1.027249s
[2026-10-20T20:58:56.930Z] "GET /reviews/0 HTTP/1.1" 504 UT response_timeout - "-" 0 24 1002 - "-" "curl/8.11.1" "8a089701-91a3-4f55-a813-83e53faff669" "scout:9080" "10.244.0.8:9080" outbound|9080|v2|scout.starfleet.svc.cluster.local 10.244.0.11:47828 10.96.210.224:9080 10.244.0.11:50186 - -
```

The request stops after 1 second with a `504`. The access log line shows `504 UT` after 1002 milliseconds. The proxy of the `shuttle` pod created the `504` itself, because its timeout ran out. `UT` is the response flag for "upstream timeout". If the request still takes 3 seconds, wait a few seconds and send it again.

---

## Item 6: Other Requests Stay Fast

> **Task item 6:** A request without the `end-user: jason` header still gets a **200** in well under a second.

```sh
kubectl -n starfleet exec deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://scout:9080/reviews/0
```

```text
200 0.510412s
```

The request returns `200` in about half a second. It goes to `scout` `v1`, which does not call `navcom`, so the delay does not touch it.

---

## Item 7: The Workloads Are Unchanged

> **Task item 7:** Leave the Deployments and Services unchanged.

Run the Deployment and Service commands from the Start section again:

```sh
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n starfleet get svc -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port,SELECTOR:.spec.selector
```

```text
NAME        REPLICAS   UID
bridge-v1   1          6c7212bf-c579-46d1-bdae-7703ff603f6c
cargo-v1    1          b6935795-3b38-4700-8025-7d55556db24d
navcom-v1   1          f0f67a29-1d24-4d34-93c8-36aeb4916188
scout-v1    1          b769b772-d4c5-4a36-ac90-51806ac3ac4a
scout-v2    1          7e2a6599-12d5-4e6d-8830-63ac9d4602d8
scout-v3    1          b3071e28-ef21-43f8-a978-766ee0765d57
shuttle     1          70178054-e96b-43c1-9c13-9f1829bf39a1
NAME     PORT   SELECTOR
bridge   9080   map[app:bridge]
cargo    9080   map[app:cargo]
navcom   9080   map[app:navcom]
scout    9080   map[app:scout]
```

The output is the same as before. The same seven Deployments exist with the same `UID` values, and the Services are the same.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-040/module-01/labs/lab-02
```

The grader sends real requests from `shuttle`, reads its access log, and checks both `VirtualService` objects.

---

## Mistakes That Fail The Grader

- **Leaving `timeout: 1s` on the `navcom` rule (item 2).** It does nothing there, and the grader checks that it is gone.
- **Removing the delay fault (item 1).** The `jason` requests would be fast again, but the grader checks that the delay stays.
- **Putting the timeout on the catch-all rule (item 4).** Only the `jason` requests go through `scout` `v2` and `navcom`. The timeout belongs on the `jason` rule.
- **Changing the `jason` route to another subset (item 3).** The grader checks that `jason` still goes to `v2` and every other request to `v1`.
