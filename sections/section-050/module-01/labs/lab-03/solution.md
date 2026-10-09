# Solution Walkthrough

Mission debrief, astronaut. The drill had no `match`, so every sender of navcom was in its blast radius. The fix keeps the drill, but moves it onto a first rule that only `end-user: tester` fits, with a plain rule below it for everyone else.

---

## Step 1: See the Problem

Send one ordinary signal to the scout, then look at the flight plans:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s http://scout:9080/reviews/0
kubectl get virtualservice -n starfleet
kubectl get virtualservice navcom -n starfleet \
  -o jsonpath='{.spec.http[0].match}|{.spec.http[0].fault.abort.httpStatus} {.spec.http[0].fault.abort.percentage.value}{"\n"}'
```

```text
{"id": "0","podname": "scout-v2-866c98b568-rmk4k","clustername": "null","reviews": [{  "reviewer": "Reviewer1",  "text": "An extremely entertaining play by Shakespeare. The slapstick humour is refreshing!", "rating": {"error": "Ratings service is currently unavailable"}},{  "reviewer": "Reviewer2",  "text": "Absolutely fun and entertaining. The play lacks thematic depth when compared to other plays by Shakespeare.", "rating": {"error": "Ratings service is currently unavailable"}}]}
NAME     GATEWAYS   HOSTS        AGE
navcom              ["navcom"]   9s
scout               ["scout"]    9s
|500 100
```

No star ratings, for a signal without any label. Navcom's flight plan has one rule with an empty `match` (before the `|`) and an abort with `500` for 100 percent of signals: an unscoped drill.

---

## Step 2: Scope the Drill to tester

Put the drill on a first rule that matches `end-user: tester`, and add a plain rule below it. Save this as `virtualservice-navcom.yaml`:

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

---

## Step 3: Prove It

Send one ordinary signal and one tester signal through the scout:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s http://scout:9080/reviews/0 | grep -o '"rating": {[^}]*}'
kubectl exec -n starfleet deploy/shuttle -- curl -s -H "end-user: tester" http://scout:9080/reviews/0 | grep -o '"rating": {[^}]*}'
```

```text
"rating": {"stars": 5, "color": "black"}
"rating": {"stars": 4, "color": "black"}
"rating": {"error": "Ratings service is currently unavailable"}
"rating": {"error": "Ratings service is currently unavailable"}
```

Star ratings are back for everyone, and the test crew's signals still meet the drill. That works because the scout passes the `end-user` label on to navcom.

Now send a tester signal and an ordinary signal straight to navcom, and read the shuttle's flight log:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" -H "end-user: tester" http://navcom:9080/ratings/0
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://navcom:9080/ratings/0
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=2
```

```text
500
200
[2026-10-08T21:55:15.820Z] "GET /ratings/0 HTTP/1.1" 500 FI fault_filter_abort - "-" 0 18 0 - "-" "curl/8.11.1" "7d9df658-cb04-4a1c-a70c-88856feec6f4" "navcom:9080" "-" outbound|9080|v1|navcom.starfleet.svc.cluster.local - 10.96.92.206:9080 10.244.0.14:37180 - -
[2026-10-08T21:55:15.897Z] "GET /ratings/0 HTTP/1.1" 200 - via_upstream - "-" 0 48 19 18 "-" "curl/8.11.1" "e902657e-1a00-43c7-8d59-a398b85fe3c0" "navcom:9080" "10.244.0.7:9080" outbound|9080|v1|navcom.starfleet.svc.cluster.local 10.244.0.14:44944 10.96.92.206:9080 10.244.0.14:37188 - -
```

The tester signal fails with `500 FI`: made by the shuttle's own communications officer, never sent to navcom. The ordinary signal reaches navcom and gets a `200`.

Then submit:

```sh
astrona submit -c sections/section-050/module-01/labs/lab-03
```

```text
PASS: the drill on navcom now only hits end-user: tester (500 FI), and every other signal gets its star ratings again
```

---

## Mistakes That Fail This Mission

- **Deleting the drill.** Everyone gets star ratings again, but the test crew loses its drill. The grader checks that tester still meets it.
- **Putting the plain rule first.** It fits every signal, so the drill rule below it is never reached.
- **Leaving the fault on the plain rule too.** Then everyone still meets the drill.
- **Changing the scout flight plan to send signals to v1.** Scout v1 never calls navcom, so the problem only hides. The grader checks that the scout flight plan is unchanged.
- **Matching with `prefix` or on another header.** The task asks for an exact match on `end-user: tester`.
