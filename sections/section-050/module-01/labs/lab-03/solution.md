# Solution Walkthrough

The fault had no `match`, so it hit every client of `navcom`. The fix keeps the fault, but moves it onto a first rule that only requests with `end-user: tester` match, with a plain rule below it for every other request.

---

## Step 1: See the Problem

Send one request without a header to `scout`, then look at the `VirtualService` objects:

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

There are no star ratings, even for a request without any header. The `navcom` `VirtualService` has one rule with an empty `match` (before the `|`) and an abort with `500` for 100 percent of requests: an unscoped fault.

---

## Step 2: Scope the Fault to tester

Put the fault on a first rule that matches `end-user: tester`, and add a plain rule below it. The sidecar proxy uses the first rule that matches, so the order matters. Save this as `virtualservice-navcom.yaml`:

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

Then check the result. Send one request without a header and one with `end-user: tester` through `scout`:

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

Star ratings are back for every other request, and the requests of `tester` still get the fault. That works because the `scout` application copies the `end-user` header onto its own request to `navcom`.

Now send one request with `end-user: tester` and one without a header straight to `navcom`, and read the access log of `shuttle`:

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

The request of `tester` fails with `500 FI`: the sidecar proxy of `shuttle` made the response itself and never sent the request to `navcom`. The request without a header reaches `navcom` and gets a `200`.

Then send the lab for grading:

```sh
astrona submit -c sections/section-050/module-01/labs/lab-03
```

```text
PASS: the abort fault on navcom now only hits end-user: tester (500 FI), and every other request gets its star ratings again
```

---

## Mistakes That Fail This Lab

- **Deleting the fault.** Every request gets star ratings again, but the test team loses its fault. The grader checks that requests of `tester` still get it.
- **Putting the plain rule first.** It matches every request, so the proxy never reaches the fault rule below it.
- **Leaving the fault on the plain rule too.** Then every request still gets the fault.
- **Changing the `scout` `VirtualService` to send requests to v1.** `scout` v1 never calls `navcom`, so the problem only hides. The grader checks that the `scout` `VirtualService` is unchanged.
- **Matching with `prefix` or on another header.** The task asks for an exact match on `end-user: tester`.
