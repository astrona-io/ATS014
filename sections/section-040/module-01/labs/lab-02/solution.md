# Solution Walkthrough

Mission debrief, astronaut. The abort window was on the wrong rule. A rule with a `fault` ignores its own `timeout`, so the 1-second limit on navcom's delay drill never fired. The fix is to move it to the route the shuttle really uses: jason's rule in the scout flight plan.

---

## Step 1: See the Problem

Send one signal as jason and time it:

```sh
kubectl exec -n starfleet deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" -H "end-user: jason" http://scout:9080/reviews/0
```

```text
200 3.476322s
```

jason waits more than 3 seconds, although there is a `timeout: 1s` in the mesh. List the flight plans to find where it sits:

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

The `1s` timeout sits on navcom's first rule, the same rule as the 3-second delay drill. That rule has a `fault`, so Istio ignores its `timeout`.

---

## Step 2: Keep the Delay Drill, Remove the Useless Timeout

The delay drill must stay: it simulates a slow navigation computer. Save this as `virtualservice-navcom.yaml`:

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

## Step 3: Put the Abort Window on jason's Scout Rule

The shuttle's signals go to scout first, so the abort window belongs on the scout flight plan, on jason's rule. Keep both routes exactly as they were and add `timeout: 1s` to the first one. Save this as `virtualservice-scout.yaml`:

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

Send one signal as jason and one without a label:

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

jason now gives up after one second. Everyone else flies to scout v1, which never calls navcom, so their signals stay fast.

Read the shuttle's flight log for jason's signal:

```sh
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=3 | grep '504 UT'
```

```text
[2026-10-08T21:05:13.152Z] "GET /reviews/0 HTTP/1.1" 504 UT response_timeout - "-" 0 24 999 - "-" "curl/8.11.1" "c6c75722-28d1-43fe-a4e7-48df24ad7a5b" "scout:9080" "10.244.0.9:9080" outbound|9080|v2|scout.starfleet.svc.cluster.local 10.244.0.12:33072 10.96.224.116:9080 10.244.0.12:47780 - -
```

`504 UT` after `999` milliseconds: the shuttle's own communications officer made the `504`, because its abort window ran out.

Then submit:

```sh
astrona submit -c sections/section-040/module-01/labs/lab-02
```

```text
PASS: navcom keeps its 3s delay drill with no timeout, jason's scout rule has timeout 1s, jason gets 504 UT after 1.001937s from the shuttle's own sidecar, and everyone else still gets a fast 200
```

---

## Mistakes That Fail This Mission

- **Leaving `timeout: 1s` on navcom's rule.** It does nothing there, and the grader asks for it to be gone.
- **Removing the delay drill.** jason would be fast again, but you would no longer be testing the abort window.
- **Putting the timeout on the catch-all rule.** Only jason's signals go through scout v2 and navcom. The timeout belongs on his rule.
- **Changing jason's route to another subset.** The grader checks that jason still flies to v2 and everyone else to v1.
