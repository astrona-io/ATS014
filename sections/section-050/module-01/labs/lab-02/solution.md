# Solution Walkthrough

Each fault goes on the `VirtualService` of the service that should look slow or broken: the delay on `navcom`, the abort on `probe`. The sidecar proxy of the pod that **sends** the request applies the fault, so the evidence appears in the access log of that client. The sidecar proxy is the Envoy container that Istio adds to each pod, and the access log is where it writes one line for every request.

---

## Step 1: Check the Starting State

List the `VirtualService` objects. Then send a request as `jason` to `scout` twice, and one request to `probe`:

```sh
kubectl get virtualservice -n starfleet
kubectl exec -n starfleet deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" -H "end-user: jason" http://scout:9080/reviews/0
kubectl exec -n starfleet deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" -H "end-user: jason" http://scout:9080/reviews/0
kubectl exec -n starfleet deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://probe:8000/get
```

```text
NAME    GATEWAYS   HOSTS       AGE
scout              ["scout"]   16s
200 0.414204s
200 0.010278s
200 0.009433s
```

Only the `scout` `VirtualService` exists. The first request is slow because the pods are still warming up. After that, every request gets a response in about 10 milliseconds.

---

## Step 2: Delay Every Request to navcom

Save this as `virtualservice-navcom.yaml`:

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

Then check the result. Send the request as `jason` again, and read the access log of `scout-v2`, the pod that calls `navcom`:

```sh
kubectl exec -n starfleet deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" -H "end-user: jason" http://scout:9080/reviews/0
kubectl logs -n starfleet deploy/scout-v2 -c istio-proxy --tail=4 | grep ratings
```

```text
200 2.040386s
[2026-10-08T21:49:52.944Z] "GET /ratings/0 HTTP/1.1" 200 DI via_upstream - "-" 0 48 2007 5 "-" "curl/8.11.1" "be0b4463-5ad9-4bc4-aa1a-4d655d563009" "navcom:9080" "10.244.0.7:9080" outbound|9080|v1|navcom.starfleet.svc.cluster.local 10.244.0.12:40064 10.96.65.94:9080 10.244.0.12:43418 - -
```

The status is still `200`, two seconds late. The response flag `DI` (delay injected) is in the access log of `scout-v2`: its sidecar proxy held the request, and the whole request took 2007 milliseconds. `navcom` itself answered in 5. If the line does not show up yet, wait a moment: the proxy writes the access log about once a second.

---

## Step 3: Abort Every Request to probe

Save this as `virtualservice-probe.yaml`:

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

Then check the result. Send one request to `probe`, and read the access logs of `shuttle` and `probe`:

```sh
kubectl exec -n starfleet deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://probe:8000/get
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=2 | grep probe
kubectl logs -n starfleet -l app=probe -c istio-proxy --since=15s | grep -c 'GET /get'
```

```text
503 0.009951s
[2026-10-08T21:50:12.886Z] "GET /get HTTP/1.1" 503 FI fault_filter_abort - "-" 0 18 6 - "-" "curl/8.11.1" "410a53b3-56fe-40fb-bc56-5516a69eeb4b" "probe:8000" "-" outbound|8000||probe.starfleet.svc.cluster.local - 10.96.14.90:8000 10.244.0.14:50074 - -
0
```

The response is a `503` in 10 milliseconds. The access log of `shuttle` shows `FI` (fault injected) and `fault_filter_abort`, and the address of the destination pod is `"-"`: the request never left the `shuttle` pod. The access log of `probe` has no line for it.

Then send the lab for grading:

```sh
astrona submit -c sections/section-050/module-01/labs/lab-02
```

```text
PASS: navcom is delayed 2s and the probe aborted with 503; jason gets 200 after 2.125839s with DI in scout v2's access log, and the probe request fails with 503 FI after 0.006220s without ever reaching the probe
```

---

## Mistakes That Fail This Lab

- **Putting the delay on the `scout` `VirtualService`.** That delays the request from `shuttle` to `scout`, and the access log of `scout-v2` never shows `DI`. The delay belongs on `navcom`, the service that should look slow.
- **Using an abort for `navcom` or a delay for `probe`.** `navcom` must be slow but still answer. `probe` must fail at once.
- **Setting `percentage.value` below 100.** Every request must get the fault.
- **Changing the `scout` `VirtualService`.** Requests from `jason` must still go to `scout` v2, the version that calls `navcom`.
- **Looking for the aborted request in the access log of `probe`.** It never arrives there. The evidence is in the access log of `shuttle`.
