# Solution Walkthrough

One `DestinationRule` with four outlier detection fields solves this task. Outlier detection means that a sidecar proxy removes an endpoint from its load balancing pool for a while after the endpoint returns too many errors. One of the four fields is the real test: its default value makes the rule do nothing on a Service with only two endpoints. The walkthrough applies the rule twice to show this. Items 1 and 2 are the rule. Items 3 to 9 prove the result.

---

## Start: See The Problem

The task says that one pod fails every request but Kubernetes reports it as ready. Look at the pods, the Service endpoints, the Istio objects, and the error rate. The loop sends 20 requests from the `tester` pod to the Service and counts the status codes:

```sh
kubectl -n outlier-demo get pods -o wide | awk '{print $1,$2,$3,$6}'
kubectl -n outlier-demo get endpoints httpbin
kubectl -n outlier-demo get destinationrule,virtualservice
kubectl -n outlier-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code}\n" http://httpbin:8000/get; done' | sort | uniq -c
```

```text
NAME READY STATUS IP
httpbin-bad-854489b47f-pfdcf 2/2 Running 10.244.0.9
httpbin-good-664569f479-4zw64 2/2 Running 10.244.0.8
tester-69699fd775-2ghml 2/2 Running 10.244.0.10
NAME      ENDPOINTS                         AGE
httpbin   10.244.0.8:8080,10.244.0.9:8080   5s
No resources found in outlier-demo namespace.
   4 200
  16 503
```

Each pod shows `2/2`: the application container and its sidecar proxy. The sidecar proxy is the Envoy container that Istio adds to each pod. `httpbin-bad` is `Running` and listed as an endpoint of the Service, so Kubernetes sees nothing wrong. Many of the requests return `503`. Write down the address of `httpbin-bad`, here `10.244.0.9`. This is the endpoint that the proxy must learn to avoid. Your numbers and addresses will differ.

Save the identity of the workloads. Items 3 and 8 compare against it:

```sh
kubectl -n outlier-demo get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n outlier-demo get svc httpbin -o jsonpath='{.spec.selector} {.spec.ports[0].port}{"\n"}'
```

```text
NAME           REPLICAS   UID
httpbin-bad    1          cbcb2c36-10cb-415f-8d6b-e38bca42e7ec
httpbin-good   1          f08a091e-1749-4af8-9565-c55b79e5e184
tester         1          e6a33c95-d81d-48b7-a6ea-26f1b36a0a38
{"app":"httpbin"} 8000
```

---

## Items 1 And 2: Create The Rule, And Choose `maxEjectionPercent`

> **Task item 1:** Create a `DestinationRule` named `httpbin` for the host `httpbin` in `outlier-demo`.
>
> **Task item 2:** In its `trafficPolicy.outlierDetection`, set:
>
> * `consecutive5xxErrors` to **3**
> * `interval` to **`5s`**
> * `baseEjectionTime` to **`30s`**
> * `maxEjectionPercent` to a value that lets an ejection **really happen on a Service with two endpoints**. Think about what the default value does here before you pick a number.

A `DestinationRule` is the Istio object that holds policies for traffic to one host. The four fields work like this. `consecutive5xxErrors: 3` ejects an endpoint after three `5xx` answers in a row. `interval: 5s` is how often the proxy checks. `baseEjectionTime: 30s` is how long the first ejection lasts. `maxEjectionPercent` is the largest share of the pool that the proxy may eject at the same time. Its default is 10%.

First see what the default does. Save this as `destinationrule-httpbin.yaml`, without `maxEjectionPercent`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin
  namespace: outlier-demo
spec:
  host: httpbin
  trafficPolicy:
    outlierDetection:
      consecutive5xxErrors: 3
      interval: 5s
      baseEjectionTime: 30s
```

Apply it:

```sh
kubectl apply -f destinationrule-httpbin.yaml
```

```text
destinationrule.networking.istio.io/httpbin created
```

Outlier detection is passive: the proxy learns only from real responses. Send 60 requests, and then ask the `tester` proxy for the health of the endpoints. `OUTLIER CHECK` is the verdict of this proxy about each endpoint:

```sh
kubectl -n outlier-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 60); do curl -s -o /dev/null -w "%{http_code}\n" http://httpbin:8000/get; done' | sort | uniq -c
istioctl proxy-config endpoints deploy/tester -n outlier-demo \
  --cluster "outbound|8000||httpbin.outlier-demo.svc.cluster.local"
```

```text
  36 200
  24 503
ENDPOINT            STATUS      OUTLIER CHECK     CLUSTER
10.244.0.8:8080     HEALTHY     OK                outbound|8000||httpbin.outlier-demo.svc.cluster.local
10.244.0.9:8080     HEALTHY     OK                outbound|8000||httpbin.outlier-demo.svc.cluster.local
```

24 of 60 requests failed, and both endpoints show `OUTLIER CHECK: OK`. Nothing was ejected, and no error or warning tells you so. Before each ejection, Envoy works out what share of the pool would be ejected. With two endpoints, ejecting one is 50% of the pool. That is more than the 10% default, so the rule counts the failures but never ejects.

You need at least `50` for one of two endpoints to be removable, and the task asks for at least `50`. Use `100`: with two endpoints and one of them always broken, you would rather send every request to the good endpoint than keep half of them failing. Add the field and apply the file again:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin
  namespace: outlier-demo
spec:
  host: httpbin
  trafficPolicy:
    outlierDetection:
      consecutive5xxErrors: 3
      interval: 5s
      baseEjectionTime: 30s
      maxEjectionPercent: 100
```

```sh
kubectl apply -f destinationrule-httpbin.yaml
```

```text
destinationrule.networking.istio.io/httpbin configured
```

Check items 1 and 2. Print the host and the outlier detection settings:

```sh
kubectl -n outlier-demo get destinationrule httpbin -o jsonpath='{.spec.host} {.spec.trafficPolicy.outlierDetection}{"\n"}'
```

```text
httpbin {"baseEjectionTime":"30s","consecutive5xxErrors":3,"interval":"5s","maxEjectionPercent":100}
```

The host is `httpbin`, and the four fields have the values that the task asks for.

---

## Item 3: No `VirtualService`, And The Bad Pod Is Not Touched

> **Task item 3:** Do **not** create any `VirtualService` in `outlier-demo`. Do not scale or delete `httpbin-bad`, and do not change the Service selector. The `tester` proxy must remove the bad endpoint on its own; you must not remove it.

```sh
kubectl -n outlier-demo get virtualservice
kubectl -n outlier-demo get deploy httpbin-bad
kubectl -n outlier-demo get svc httpbin -o jsonpath='{.spec.selector}{"\n"}'
```

```text
No resources found in outlier-demo namespace.
NAME          READY   UP-TO-DATE   AVAILABLE   AGE
httpbin-bad   1/1     1            1           23s
{"app":"httpbin"}
```

There is no `VirtualService`. A `VirtualService` with retries would hide the failures that outlier detection needs to see. `httpbin-bad` still runs, and the Service still selects on `app` only.

---

## Item 4: The Workloads Are Ready, The Service Has Two Endpoints

> **Task item 4:** `httpbin-good`, `httpbin-bad` and `tester` each have a ready replica, the `httpbin` Service lists exactly two endpoint addresses, and `outlier-demo` has no `VirtualService`.

```sh
kubectl -n outlier-demo get deploy
kubectl -n outlier-demo get endpoints httpbin
kubectl -n outlier-demo get virtualservice
```

```text
NAME           READY   UP-TO-DATE   AVAILABLE   AGE
httpbin-bad    1/1     1            1           24s
httpbin-good   1/1     1            1           24s
tester         1/1     1            1           24s
NAME      ENDPOINTS                         AGE
httpbin   10.244.0.8:8080,10.244.0.9:8080   24s
No resources found in outlier-demo namespace.
```

All three Deployments are ready, the Service lists two addresses, and no `VirtualService` exists. Kubernetes may print a warning that `Endpoints` is deprecated. You can ignore it.

---

## Item 5: The Fields Have The Right Values

> **Task item 5:** The `DestinationRule` `httpbin` has `consecutive5xxErrors: 3`, `interval: 5s`, `baseEjectionTime: 30s`, and `maxEjectionPercent` of at least **50**.

The output of items 1 and 2 already shows the values: `3`, `5s`, `30s` and `100`. The value `100` is at least `50`.

---

## Item 6: The Proxy Holds The Settings

> **Task item 6:** The `tester` proxy's cluster configuration for `httpbin` contains the outlier detection settings.

`istiod`, the Istio control plane, sends the rule to every proxy. A cluster is Envoy's name for the endpoints of one destination. Read the cluster of `httpbin` in the `tester` proxy:

```sh
istioctl proxy-config cluster deploy/tester -n outlier-demo \
  --fqdn httpbin.outlier-demo.svc.cluster.local -o json | grep -A6 outlierDetection
```

```text
        "outlierDetection": {
            "consecutive5xx": 3,
            "interval": "5s",
            "baseEjectionTime": "30s",
            "maxEjectionPercent": 100,
            "enforcingConsecutive5xx": 100,
            "enforcingSuccessRate": 0
```

The proxy shows the field names of Envoy. `istiod` translated `consecutive5xxErrors` into `consecutive5xx`, and it added `enforcingConsecutive5xx: 100`, which means that every endpoint that reaches the limit is really ejected. With the default `maxEjectionPercent`, the same output had no `maxEjectionPercent` line.

---

## Item 7: One Endpoint Is Ejected

> **Task item 7:** After the grader sends requests from `tester` (up to 240 of them), one endpoint in the `tester` proxy carries the outlier detection failure flag, and `istioctl proxy-config endpoints` shows it with `OUTLIER CHECK: FAILED`.

The proxy needs three failures in a row from the same endpoint. The load balancer sends some requests to the good pod in between, so it can take more requests than you expect. Send 60 requests, then read the endpoint table and the health flags of the cluster:

```sh
kubectl -n outlier-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 60); do curl -s -o /dev/null -w "%{http_code}\n" http://httpbin:8000/get; done' >/dev/null
istioctl proxy-config endpoints deploy/tester -n outlier-demo \
  --cluster "outbound|8000||httpbin.outlier-demo.svc.cluster.local"
kubectl -n outlier-demo exec deploy/tester -c istio-proxy -- \
  pilot-agent request GET clusters 2>/dev/null | grep 'outbound|8000||httpbin' | grep failed_outlier_check
```

```text
ENDPOINT            STATUS      OUTLIER CHECK     CLUSTER
10.244.0.8:8080     HEALTHY     OK                outbound|8000||httpbin.outlier-demo.svc.cluster.local
10.244.0.9:8080     HEALTHY     FAILED            outbound|8000||httpbin.outlier-demo.svc.cluster.local
outbound|8000||httpbin.outlier-demo.svc.cluster.local::10.244.0.9:8080::health_flags::/failed_outlier_check
```

The endpoint `10.244.0.9:8080` is the bad pod. It shows `OUTLIER CHECK: FAILED`, and it carries the health flag `failed_outlier_check`. Read the two columns separately. `STATUS: HEALTHY` is what Kubernetes reports through `istiod`. `OUTLIER CHECK: FAILED` is the own decision of this proxy. If no endpoint shows `FAILED`, send more requests and check again. The ejection ends after `baseEjectionTime`, so also check soon after the requests.

---

## Item 8: Kubernetes Did Not Change

> **Task item 8:** The `httpbin` Service still lists **both** addresses, and `httpbin-bad` is still ready. The ejection lives only in the proxy, not in the Kubernetes objects.

The output of item 4 shows it: the Service lists both addresses, and `httpbin-bad` shows `1/1` ready. The `UID` values did not change either. Run the two commands from the Start section again, and the output is the same as before.

---

## Item 9: Requests Succeed

> **Task item 9:** At least 32 of 40 new requests from `tester` return `200`.

```sh
kubectl -n outlier-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 40); do curl -s -o /dev/null -w "%{http_code}\n" http://httpbin:8000/get; done' | sort | uniq -c
```

```text
  40 200
```

All 40 requests returned `200`. At the start, only 4 of 20 did. The proxy sends every request to the good pod. Nothing changed in Kubernetes. The change is only inside the proxy of `tester`.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-040/module-03/labs/lab-01
```

The grader reads the `DestinationRule`, the cluster and the endpoints of the `tester` proxy, and sends live requests.

---

## Mistakes That Fail The Grader

- **Leaving `maxEjectionPercent` at its default (items 2 and 7).** One of two endpoints is 50% of the pool, more than the 10% default. This is the most common reason that the task fails.
- **Testing with too few requests (item 7).** The proxy needs three failures in a row from the same endpoint. Use 60 or more requests.
- **Deleting or scaling `httpbin-bad` (item 3).** The grader checks that it still runs. The proxy must be the one that stops using it.
- **Adding a `VirtualService` with retries (item 3).** Retries would hide the failures that outlier detection needs to see, and the grader fails any `VirtualService` in the namespace.
- **Looking at `kubectl get endpoints` for proof (item 8).** It never changes. Use the endpoint list and the health flags of the proxy.
- **Checking at the wrong moment (item 7).** The ejection ends after `baseEjectionTime`. If no endpoint shows `FAILED`, send more requests and check again.
