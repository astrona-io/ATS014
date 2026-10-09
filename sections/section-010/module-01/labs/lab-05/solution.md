# Solution Walkthrough

Mission debrief, astronaut. The flight plan was never the problem. One word in the probe Service told Istio that port `8000` carries plain TCP, so the proxy never read the flight plan's `http` rules at all.

---

## Step 1: See the symptom

Send 10 signals with the mission header, and 10 without:

```sh
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -H "x-mission: test" http://probe:8000/hostname | grep -o 'probe-v[0-9]'
done | sort | uniq -c
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-v[0-9]'
done | sort | uniq -c
```

```text
   5 probe-v1
   5 probe-v2
   5 probe-v1
   5 probe-v2
```

Both kinds of signals land on both versions, as if there were no flight plan. Yet the objects exist, and Istio sees nothing wrong:

```sh
kubectl get virtualservice,destinationrule -n starfleet
istioctl analyze -n starfleet
```

```text
NAME                                       GATEWAYS   HOSTS       AGE
virtualservice.networking.istio.io/probe              ["probe"]   8s

NAME                                        HOST    AGE
destinationrule.networking.istio.io/probe   probe   8s
✔ No validation issues found when analyzing namespace: starfleet.
```

---

## Step 2: Ask the shuttle's proxy

When a correct flight plan does nothing, check whether it ever reached the sender. Look at the shuttle's route table for port `8000`:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 8000
```

```text
NAME     VHOST NAME     DOMAINS     MATCH     VIRTUAL SERVICE
```

The table is empty: the probe has no HTTP route at all, so there is nothing for the `http` rules to attach to. Now look at the listener for the same port:

```sh
istioctl proxy-config listener deploy/shuttle -n starfleet --port 8000
```

```text
ADDRESSES    PORT MATCH DESTINATION
10.96.129.24 8000 ALL   Cluster: outbound|8000||probe.starfleet.svc.cluster.local
```

That is a plain TCP listener: it matches `ALL` connections and sends each one straight to the probe cluster, without reading the signal. (Your address will be different.) The proxy treats port `8000` as TCP.

---

## Step 3: Find the word that did it

Istio decides a port's protocol from the Service: first `appProtocol`, then the port's `name`. Look at the probe's port:

```sh
kubectl get svc probe -n starfleet -o yaml
```

The part that matters (trimmed):

```text
  ports:
  - name: tcp
    port: 8000
    protocol: TCP
    targetPort: 8080
```

The port is named `tcp`, and there is no `appProtocol`. Istio believes the name, so port `8000` is plain TCP and the flight plan's `http` list is never read.

---

## Step 4: Declare the port as HTTP

Rename the port to `http`. Keep the numbers exactly as they are:

```sh
kubectl patch svc probe -n starfleet --type merge \
  -p '{"spec":{"ports":[{"name":"http","port":8000,"targetPort":8080}]}}'
```

```text
service/probe patched
```

Setting `appProtocol: http` on the port works too, even with the name left as `tcp`: Istio checks `appProtocol` before the name.

---

## Step 5: Prove it

Wait a few seconds, then look at the route table again:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 8000
```

```text
NAME     VHOST NAME                                 DOMAINS                                                   MATCH     VIRTUAL SERVICE
8000     probe.starfleet.svc.cluster.local:8000     probe.starfleet.svc.cluster.local., probe + 2 more...     /*        probe.starfleet
8000     probe.starfleet.svc.cluster.local:8000     probe.starfleet.svc.cluster.local., probe + 2 more...     /*        probe.starfleet
```

The probe is back, and the `VIRTUAL SERVICE` column shows `probe.starfleet`: the flight plan is read again. Now send the signals again:

```sh
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -H "x-mission: test" http://probe:8000/hostname | grep -o 'probe-v[0-9]'
done | sort | uniq -c
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-v[0-9]'
done | sort | uniq -c
```

```text
  10 probe-v2
  10 probe-v1
```

If every `curl` fails with exit code `56` right after the rename, Kubernetes has not yet updated the probe's endpoint list. Wait a few seconds and run the loops again.

Send it for grading:

```sh
astrona submit -c sections/section-010/module-01/labs/lab-05
```

```text
PASS: the probe's port 8000 is declared as HTTP (http), the probe is back in the shuttle's route table, the flight plan's http rule is read, x-mission: test reaches probe-v2 and everyone else probe-v1
```

---

## Mistakes that fail the grader

- **Rewriting the flight plan as a `tcp` rule.** A `tcp` rule cannot read the `x-mission` header. The flight plan was correct; the port declaration was wrong.
- **Changing the port numbers.** Only the protocol declaration is wrong. `8000` to `8080` must stay.
- **Changing the Service selector, or relabelling the pods.** The routing between versions is Istio's job.
- **Naming the port something Istio does not know, like `web`.** Then Istio guesses per connection. Declare it: `http`, `http-<something>`, or `appProtocol: http`.
- **Testing straight after the rename.** The endpoint list and the route need a few seconds to reach the shuttle.
