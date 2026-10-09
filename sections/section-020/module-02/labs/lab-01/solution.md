# Solution Walkthrough

You need two objects: a `DestinationRule` with the subsets and a `VirtualService` with a route and a mirror. The hard part is the proof. The proxy throws away the release candidate's responses, so the client's output is the same whether the mirror works or not. You must check the receiving side.

---

## Step 1: Read the starting state

List the pods with their labels, check that no Istio routing objects exist, and send 20 requests from `tester`:

```sh
kubectl -n mirror-demo get pods --show-labels
kubectl -n mirror-demo get destinationrule,virtualservice
kubectl -n mirror-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 20); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
```

```text
notification-service-v1-5b9c7d8f4-2ktzn   2/2   Running   app=notification-service,version=v1,...
notification-service-v2-7f8d6c5b9-lq4wm   2/2   Running   app=notification-service,version=v2,...
tester-6d4f8b7c5-9xnpk                    2/2   Running   app=tester,...
No resources found in mirror-demo namespace.
  12 ["EMAIL"]
   8 ["EMAIL","SMS"]
```

Right now both versions send responses to clients, because the Service selects pods on the `app` label only. At the end, clients must get only `["EMAIL"]`, while `v2` receives more requests than it does now.

---

## Step 2: Define the subsets

A subset is a named group of a Service's pods, selected by labels. A `DestinationRule` defines subsets, and both the route and the mirror refer to them by name.

Save this as `destinationrule-notification-service.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: notification-service
  namespace: mirror-demo
spec:
  host: notification-service
  subsets:
    - name: v1
      labels:
        version: v1
    - name: v2
      labels:
        version: v2
```

Apply it:

```sh
kubectl apply -f destinationrule-notification-service.yaml
```

The `v2` subset matters more than usual here. A `mirror` that points at a subset that does not exist, or at one whose labels select no pod, **silently sends nothing**, and the client cannot tell. Check that the `v2` cluster in the `tester` proxy has an endpoint (a pod address):

```sh
istioctl proxy-config endpoints deploy/tester -n mirror-demo \
  --cluster "outbound|80|v2|notification-service.mirror-demo.svc.cluster.local"
```

```text
ENDPOINT            STATUS    OUTLIER CHECK   CLUSTER
10.244.0.15:8084    HEALTHY   OK              outbound|80|v2|notification-service...
```

One healthy endpoint, so the mirror will have a pod to send copies to.

---

## Step 3: Route to v1 and mirror to v2

Save this as `virtualservice-notification.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: notification
  namespace: mirror-demo
spec:
  hosts:
    - notification-service
  http:
    - route:
        - destination:
            host: notification-service
            subset: v1
          weight: 100
      mirror:
        host: notification-service
        subset: v2
      mirrorPercentage:
        value: 100.0
```

Apply it:

```sh
kubectl apply -f virtualservice-notification.yaml
```

Then check the result:

```sh
istioctl analyze -n mirror-demo
```

```text
virtualservice.networking.istio.io/notification created
✔ No validation issues found when analyzing namespace: mirror-demo.
```

The indentation is the whole task. `mirror` and `mirrorPercentage` are **siblings of `route`** on the same `http` rule, not entries inside the `route` list. If you write `v2` as a second destination in `route`, you get a weighted split. Clients then start to get `["EMAIL","SMS"]`, and the grader rejects it.

`mirror` is also a single destination with no `weight`. The copy is extra traffic on top of the route, not a share of it.

---

## Step 4: Check that clients get only v1

Send 30 requests, as the grader does:

```sh
kubectl -n mirror-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 30); do curl -s -X POST http://notification-service/notify; echo; done' | sort | uniq -c
```

```text
  30 ["EMAIL"]
```

Thirty requests, one distinct response. Any `["EMAIL","SMS"]` here means that `v2` ended up in the `route` list instead of in the `mirror`.

This output is exactly what you would get with no mirror at all. So it proves only half of the task.

---

## Step 5: Prove that v2 received the copies

The proof is on the **receiving** side, in the access log of the `v2` sidecar proxy. The access log has one line per request that passes through the proxy. The route sends nothing to `v2`, so every request in its access log is a copy.

The log may already hold copies from an earlier try, so count the lines before and after a test and take the difference:

```sh
BEFORE=$(kubectl -n mirror-demo logs -l version=v2 -c istio-proxy --tail=-1 | grep -c 'POST /notify')
kubectl -n mirror-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 40); do curl -s -o /dev/null -X POST http://notification-service/notify; done'
sleep 3
AFTER=$(kubectl -n mirror-demo logs -l version=v2 -c istio-proxy --tail=-1 | grep -c 'POST /notify')
echo "mirrored this run: $((AFTER - BEFORE)) of 40"
```

```text
mirrored this run: 40 of 40
```

All 40 requests were copied to `v2`. Look at one of the lines to see why it counts as proof:

```sh
kubectl -n mirror-demo logs -l version=v2 -c istio-proxy --tail=3
```

```text
[2026-09-28T18:11:49.139Z] "POST /notify HTTP/1.1" 200 - via_upstream - "-" 0 15 0 0 "10.244.0.10" "curl/8.22.0" "c03f8616..." "notification-service" "10.244.0.9:8084" inbound|8084|| ...
```

The authority (the host name the request was sent to) is the plain `notification-service`. Istio 1.30 sends the copy unchanged; older Istio releases added a `-shadow` suffix, but it is not there now. The line is proof because it exists at all: the route sends 100% of client requests to `v1`, so `v2` can only see copies. The `200` is the response of `v2`, which the client never saw. If `v2` returned `500` errors, they would show here, and the client would still get normal responses.

---

## Step 6: Check the mirror policy in the client's proxy

The sidecar proxy of the **client** sends the copy, so the mirror policy lives in the route table of the `tester` proxy. This check tells "the mirror is not configured" apart from "the mirror target has no endpoints":

```sh
istioctl proxy-config routes deploy/tester -n mirror-demo -o json | grep -i -A6 requestMirrorPolicies
```

You should see (shortened):

```text
"requestMirrorPolicies": [
  {
    "cluster": "outbound|80|v2|notification-service.mirror-demo.svc.cluster.local",
```

The `|v2|` in the cluster name shows that the copies go to the `v2` subset.

The two checks together give three states:

| `requestMirrorPolicies` | Access log of v2 | Means |
| --- | --- | --- |
| missing | empty | no `mirror` in the object, or the configuration never reached the proxy |
| present | empty | the mirror cluster has no endpoints |
| present | shows requests the route never sent it | working |

---

## Common mistakes

- **`mirror` indented as an entry of `route`.** It is a sibling of `route`, and a single destination, not a list.
- **Putting `v2` in the `route` list as a weighted destination.** That is traffic shifting, and clients start to get the release candidate's responses.
- **Mirroring to an undefined subset.** It fails silently: the client is fine and `v2` receives nothing. `istioctl analyze` names the problem.
- **Counting the access log of v2 without a baseline.** The log holds copies from earlier runs. Take a `BEFORE` count first.
- **Reading the application log instead of the proxy's access log.** The grader counts the lines in the `istio-proxy` container's log.
- **Searching for a `-shadow` authority.** Older Istio added it; 1.30 does not, so the search finds nothing.
- **Expecting the mirrored response to matter.** The proxy throws it away, together with its delay. Mirroring cannot compare responses.
- **Leaving out `mirrorPercentage` and assuming nothing is mirrored.** The default is 100%. The task asks you to set it anyway.
