# Solution Walkthrough

Mission debrief, astronaut. Each drill goes on the flight plan of the ship you pretend is in trouble: the delay on `navcom`, the abort on `probe`. The communications officer of the ship that **sends** the signal carries the drill out, so that is where the evidence appears.

---

## Step 1: See the Fleet Before the Drills

List the flight plans, then send jason's signal to the scout twice and one signal to the probe:

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

Only the scout flight plan exists. The first signal is slow because the ships are still warming up. After that, everything answers in about 10 milliseconds.

---

## Step 2: Slow Navcom Down

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

Then send jason's signal again, and read scout v2's flight log. Scout v2 is the ship that calls navcom:

```sh
kubectl exec -n starfleet deploy/shuttle -- \
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" -H "end-user: jason" http://scout:9080/reviews/0
kubectl logs -n starfleet deploy/scout-v2 -c istio-proxy --tail=4 | grep ratings
```

```text
200 2.040386s
[2026-10-08T21:49:52.944Z] "GET /ratings/0 HTTP/1.1" 200 DI via_upstream - "-" 0 48 2007 5 "-" "curl/8.11.1" "be0b4463-5ad9-4bc4-aa1a-4d655d563009" "navcom:9080" "10.244.0.7:9080" outbound|9080|v1|navcom.starfleet.svc.cluster.local 10.244.0.12:40064 10.96.65.94:9080 10.244.0.12:43418 - -
```

Still a `200`, two seconds late. The flag `DI` (delay injected) is in scout v2's flight log: scout v2's communications officer held the signal for 2007 milliseconds. Navcom itself answered in 5. If the line does not show up yet, wait a moment: the flight log is written about once a second.

---

## Step 3: Make the Probe Seem Down

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

Then send one signal to the probe, and read the flight logs of the shuttle and the probe:

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

A `503` in 10 milliseconds. The shuttle's flight log shows `FI` (fault injected) and `fault_filter_abort`, and the address of the receiving ship is `"-"`: the signal never left the shuttle. The probe's own flight log has no line for it.

Then submit:

```sh
astrona submit -c sections/section-050/module-01/labs/lab-02
```

```text
PASS: navcom is delayed 2s and the probe aborted with 503; jason gets 200 after 2.125839s with DI in scout v2's flight log, and the probe signal fails with 503 FI after 0.006220s without ever reaching the probe
```

---

## Mistakes That Fail This Mission

- **Putting the delay on the scout flight plan.** That holds back the shuttle's signal to the scout, and scout v2's flight log never shows `DI`. The delay belongs on navcom, the ship you pretend is slow.
- **Using an abort for navcom or a delay for the probe.** Navcom must be slow but still answer. The probe must fail at once.
- **Setting `percentage.value` below 100.** Every signal must meet the drill.
- **Changing the scout flight plan.** jason's signals must still go to scout v2, the class that calls navcom.
- **Looking for the aborted signal in the probe's flight log.** It never arrives there. The evidence is in the shuttle's flight log.
