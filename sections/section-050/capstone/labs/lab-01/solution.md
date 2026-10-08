# Solution Walkthrough

Mission debrief, astronaut. One object, three rules, two independent simulation drills — and the first drill's result is the lesson.

---

## Step 1: Baseline, And Note Who Else Is Here

```sh
kubectl -n orders get virtualservice
kubectl -n orders run t0 --rm -i --restart=Never --image=curlimages/curl -- \
  curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' -X POST http://booking-service/book
```

```text
No resources found in orders namespace.
200 0.041s
```

The namespace is shared: other crews live on this planet. Every rule you add that lacks a `match` block is a change to somebody else's signals, which is why both experiments get their own header and a clean catch-all goes last.

---

## Step 2: Predict Experiment 1 Before Running It

The first rule aborts with 503 **and** carries a retry policy that retries on `gateway-error` — which covers 503. So how many attempts do you expect?

The intuitive answer is three: the original plus two retries, each one re-faulted.
The actual answer is **one**, and the reason is the filter chain:

```text
  client request
        │
        ▼
  ┌───────────────┐
  │ fault filter  │ ── abort: answer 503 right here (FI)
  └───────────────┘
        │  ✗ never continues
        ▼
  ┌───────────────┐
  │    router     │ ← the retry policy lives here, and is never consulted
  └───────────────┘
```

The fault filter sits **before** the router. An injected abort is a local reply:
the router never dispatches an upstream request, so there is no failed attempt
for it to retry. The retry policy is perfectly valid configuration and simply
never runs.

That is the point of the experiment, and it is a sharper version of the usual
lesson. Retries recover from *transient upstream* failures. An injected fault is
not upstream at all — it never leaves the caller's proxy.

Check the budget too, since the rule has both: `attempts: 2` plus the original
would be 3 attempts × `perTryTimeout: 1s` = 3s, and `timeout: 5s` leaves room —
so if retries were going to run, nothing here would truncate them.

---

## Step 3: Write All Three Rules

Write the manifest to a file and apply the file. It is the habit the exam rewards — you get something you can re-read, edit and re-apply, instead of a heredoc that is gone the moment it runs.

```sh
cat > virtualservice-notification.yaml <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: orders
spec:
  hosts:
    - notification-service
  http:
    - match:
        - headers:
            x-chaos:
              exact: abort
      fault:
        abort:
          httpStatus: 503
          percentage:
            value: 100
      retries:
        attempts: 2
        perTryTimeout: 1s
        retryOn: gateway-error
      timeout: 5s
      route:
        - destination:
            host: notification-service
    - match:
        - headers:
            x-chaos:
              exact: delay
      fault:
        delay:
          fixedDelay: 7s
          percentage:
            value: 100
      route:
        - destination:
            host: notification-service
    - route:
        - destination:
            host: notification-service
EOF
kubectl apply -f virtualservice-notification.yaml
cat > virtualservice-booking.yaml <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: booking
  namespace: orders
spec:
  hosts:
    - booking-service
  http:
    - timeout: 2s
      route:
        - destination:
            host: booking-service
EOF
kubectl apply -f virtualservice-booking.yaml
istioctl analyze -n orders
```

```text
virtualservice.networking.istio.io/notification created
✔ No validation issues found when analyzing namespace: orders.
```

Both chaos rules are above the catch-all, each matching a different value of the same header. The third rule has no `fault`, no `timeout` and no `retries` — the grader checks all three are absent.

---

## Step 4: Verify Unmarked Traffic First

Always this order. If the scoping is wrong, you want to find out before you start generating failures.

```sh
for i in 1 2 3 4 5; do
  kubectl -n orders run "u$i" --rm -i --restart=Never --image=curlimages/curl --quiet -- \
    curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' -X POST http://booking-service/book
done
```

```text
200 0.039s
200 0.042s
200 0.040s
200 0.043s
200 0.038s
```

---

## Step 5: Run Experiment 1 And Count the Attempts

```sh
BEFORE=$(kubectl -n orders logs -l app=booking-service -c istio-proxy --tail=-1 | grep -c ' FI ')
kubectl -n orders exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' -H "x-chaos: abort" -X POST http://booking-service/book
sleep 3
AFTER=$(kubectl -n orders logs -l app=booking-service -c istio-proxy --tail=-1 | grep -c ' FI ')
echo "FI-flagged attempts: $((AFTER - BEFORE))"
kubectl -n orders logs -l app=booking-service -c istio-proxy --tail=5 | grep ' FI ' | head -1
```

```text
503 0.008s
FI-flagged attempts: 1
[2026-09-28T19:12:22.462Z] "POST /notify HTTP/1.1" 503 FI fault_filter_abort - "-" 0 18 0 - ...
```

One attempt for one client request, flagged `FI`, finished in 8 milliseconds. If
you expected three, re-read step 2: the retry policy is there, it is correct, and
the router never got the chance to use it. Confirm that nothing reached the
dependency:

```sh
kubectl -n orders logs -l app=notification-service -c istio-proxy --tail=20 | grep -c ' 503 '
```

```text
0
```

The dependency never heard about any of it.

---

## Step 6: Run Experiment 2

```sh
kubectl -n orders exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' -H "x-chaos: delay" -X POST http://booking-service/book
sleep 2
kubectl -n orders logs deploy/tester -c istio-proxy --tail=-1 | grep ' 504 UT ' | tail -1
kubectl -n orders logs -l app=booking-service -c istio-proxy --tail=5 | grep ' FI ' | tail -1
```

```text
504 2.041s
[2026-09-28T19:03:07.140Z] "POST /book HTTP/1.1" 504 UT response_timeout - "-" 0 24 2000 - ...
[2026-09-28T19:03:07.140Z] "POST /notify HTTP/1.1" 500 FI - "-" ...
```

Two seconds, not seven — the timeout cut the delay off. Note which proxy logged
what: `UT` is in the **client's** log against `booking-service`, because that is
where the 2-second timeout is enforced; `FI` is in **`booking-service`'s** log
against `notification-service`, because that is where the fault filter is
holding the request.

Those two flags side by side are the section's diagnostic payoff: `FI` means
"I fabricated this", `UT` means "my deadline expired" — and they appear one hop
apart, which is exactly why the timeout had to go on the other object.

---

## Step 7: Clean Up

```sh
kubectl -n orders delete virtualservice notification
```

A fault is configuration. Left in place, the `x-chaos` rules are harmless — nobody sends that header — but the habit of deleting is what stops an unscoped one becoming an outage.

---

## Common Mistakes

- **Expecting retries to rescue the abort, or even to run.** They do not run: the fault filter answers before the router, so exactly one `FI` line appears. Counting it is the proof.
- **Expecting the retry policy to produce three attempts.** It produces one. The fault filter answers before the router, so the retries never run — that is the experiment's whole result.
- **Putting the 2s timeout next to the delay on rule 2.** Inert: the fault filter holds the request before the router starts timing it, so the call takes the full seven seconds and no `UT` is ever logged.
- **Adding retries to rule 2.** The task asks for none, and the grader checks.
- **Anything on the catch-all rule.** No fault, no timeout, no retries — unscoped traffic must be untouched.
- **Both chaos rules matching the same header value.** They need distinct values; first match wins.
- **The catch-all placed first.** It matches everything and neither experiment ever runs.
- **Putting the faults on `booking-service`.** That delays the inbound request and tests the wrong hop.
- **Reading only the outer status.** The `FI` evidence is in the intermediate service's proxy log, and the `UT` evidence is in the client's.
