# Solution Walkthrough

The timeout was on the wrong rule. A rule with a `fault` ignores its own `timeout`, so the 1-second limit on the `navcom` delay rule never fired. The fix is to move it to the route that `shuttle` really uses: the `jason` rule in the `scout` `VirtualService`. A `VirtualService` is the Istio object that sets how requests to a host are routed, including timeouts and faults.

---

## Step 1: See the Problem

Send one request with the `end-user: jason` header and time it:

```sh
kubectl exec -n starfleet deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" -H "end-user: jason" http://scout:9080/reviews/0
```

```text
200 3.476322s
```

The request takes more than 3 seconds, although there is a `timeout: 1s` in the namespace. List the `VirtualService` objects and print the delay and the timeout of the first `navcom` rule:

```sh
kubectl get virtualservice -n starfleet
kubectl get virtualservice navcom -n starfleet -o jsonpath='{.spec.http[0].fault.delay.fixedDelay} {.spec.http[0].timeout}{"\n"}'
```

```text
NAME     GATEWAYS   HOSTS        AGE
navcom              ["navcom"]   29s
scout               ["scout"]    29s
3s 1s
```

The `1s` timeout sits on the first `navcom` rule, the same rule as the 3-second delay fault. That rule has a `fault`, so Istio ignores its `timeout`.

---

## Step 2: Keep the Delay Fault, Remove the Timeout

The delay fault must stay: it makes `navcom` slow on purpose, so you can test the timeout. Save this as `virtualservice-navcom.yaml`:

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

---

## Step 3: Put the Timeout on the `jason` Rule of `scout`

The requests from `shuttle` go to `scout` first, so the `shuttle` sidecar proxy applies the timeout of the `scout` route. Keep both routes exactly as they were and add `timeout: 1s` to the first one. Save this as `virtualservice-scout.yaml`:

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

---

## Step 4: Prove It

Send one request with the `jason` header and one without it:

```sh
kubectl exec -n starfleet deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" -H "end-user: jason" http://scout:9080/reviews/0
kubectl exec -n starfleet deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://scout:9080/reviews/0
```

```text
504 1.003298s
200 0.010326s
```

The `jason` request now stops after one second. Every other request goes to `scout` v1, which never calls `navcom`, so those requests stay fast.

Read the `shuttle` sidecar proxy's access log line for the `jason` request:

```sh
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=3 | grep '504 UT'
```

```text
[2026-10-08T21:05:13.152Z] "GET /reviews/0 HTTP/1.1" 504 UT response_timeout - "-" 0 24 999 - "-" "curl/8.11.1" "c6c75722-28d1-43fe-a4e7-48df24ad7a5b" "scout:9080" "10.244.0.9:9080" outbound|9080|v2|scout.starfleet.svc.cluster.local 10.244.0.12:33072 10.96.224.116:9080 10.244.0.12:47780 - -
```

`504 UT` after `999` milliseconds: the `shuttle` pod's own sidecar proxy created the `504`, because its timeout ran out. `UT` is the response flag for "upstream timeout".

Then submit:

```sh
astrona submit -c sections/section-040/module-01/labs/lab-02
```

```text
PASS: navcom keeps its 3s delay drill with no timeout, jason's scout rule has timeout 1s, jason gets 504 UT after 1.001937s from the shuttle's own sidecar, and everyone else still gets a fast 200
```

---

## Mistakes That Fail This Lab

- **Leaving `timeout: 1s` on the `navcom` rule.** It does nothing there, and the grader checks that it is gone.
- **Removing the delay fault.** The `jason` requests would be fast again, but the grader checks that the delay stays.
- **Putting the timeout on the catch-all rule.** Only the `jason` requests go through `scout` v2 and `navcom`. The timeout belongs on the `jason` rule.
- **Changing the `jason` route to another subset.** The grader checks that `jason` still goes to v2 and every other request to v1.
