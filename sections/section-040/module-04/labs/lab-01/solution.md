# Solution Walkthrough

The answer is one `DestinationRule` with two blocks. The task looks like it is about locality, which means the preference of a client for the endpoints in its own zone. The block that really makes it work is the other one: outlier detection, which notices that the endpoint in the zone of the client is failing. The walkthrough builds the file in two steps. First you write the object with the locality setting only (items 1 and 3), and you see that it does not help. Then you add outlier detection (item 2), and the traffic moves. Items 4 to 10 prove the result.

---

## Start: See Why This Is Broken

The task says that `zone-a` fails while it stays ready, and that the client runs in `zone-a`. A locality is the region and zone that a pod runs in. Check the pods, the localities that the proxy of `tester` knows, and the error rate. The sidecar proxy is the Envoy container that Istio adds to each pod:

```sh
kubectl -n locality-demo get pods -o wide | awk '{print $1,$2,$3,$6}'
kubectl -n locality-demo get destinationrule
istioctl proxy-config endpoints deploy/tester -n locality-demo \
  --cluster "outbound|8000||httpbin.locality-demo.svc.cluster.local" -o json \
  | grep -E '"address"|"zone"|"region"' | grep -v '{'
kubectl -n locality-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code} " http://httpbin:8000/get; done; echo'
```

```text
NAME READY STATUS IP
httpbin-zone-a-6788dbbdd8-fcg8x 2/2 Running 10.244.0.10
httpbin-zone-b-679bd5d96-l92d5 2/2 Running 10.244.0.9
tester-69699fd775-g6t8r 2/2 Running 10.244.0.8
No resources found in locality-demo namespace.
                        "address": "10.244.0.10",
                    "region": "local",
                    "zone": "zone-a"
                        "address": "10.244.0.9",
                    "region": "local",
                    "zone": "zone-b"
200 200 200 200 200 503 200 503 200 503 503 200 200 200 503 503 503 503 200 200 
```

About half of the requests fail. Both endpoints are ready as far as Kubernetes knows, and both have a locality. Nothing in the mesh knows that `zone-a` is broken. That is the gap to close.

Save the identity of the workloads. Item 5 compares against it:

```sh
kubectl -n locality-demo get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n locality-demo get svc httpbin -o jsonpath='{.spec.selector} {.spec.ports[0].port}{"\n"}'
```

```text
NAME             REPLICAS   UID
httpbin-zone-a   1          dabaad00-40d6-4a55-8d9f-e9f341639fd9
httpbin-zone-b   1          92bf8150-4baf-4979-89ab-4ee9df88b273
tester           1          932e4502-4851-4709-8bef-6d7cf57135a7
{"app":"httpbin"} 8000
```

---

## Items 1 And 3: Create The Rule With The Locality Setting

> **Task item 1:** Create a `DestinationRule` named `httpbin` for host `httpbin`.
>
> **Task item 3:** Configure **`loadBalancer.localityLbSetting`** with `enabled: true`.

A `DestinationRule` is the Istio object that holds policies for traffic to one host. With `localityLbSetting` enabled, the proxy of a client prefers the endpoints in its own locality and moves to another locality when the local endpoints are unhealthy. Start with this setting alone, because it is the obvious first idea. Save this as `destinationrule-httpbin.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin
  namespace: locality-demo
spec:
  host: httpbin
  trafficPolicy:
    loadBalancer:
      localityLbSetting:
        enabled: true
```

Apply it:

```sh
kubectl apply -f destinationrule-httpbin.yaml
```

```text
destinationrule.networking.istio.io/httpbin created
```

Check items 1 and 3. Print the host and the traffic policy:

```sh
kubectl -n locality-demo get destinationrule httpbin -o jsonpath='{.spec.host} {.spec.trafficPolicy}{"\n"}'
```

```text
httpbin {"loadBalancer":{"localityLbSetting":{"enabled":true}}}
```

The object exists for the host `httpbin`, and the locality setting is enabled. Now test whether it helps. Send 30 requests, and ask the proxy for the health of the endpoints. `OUTLIER CHECK` is the verdict of this proxy about each endpoint:

```sh
kubectl -n locality-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 30); do curl -s -o /dev/null -w "%{http_code} " http://httpbin:8000/get; done; echo'
istioctl proxy-config endpoints deploy/tester -n locality-demo \
  --cluster "outbound|8000||httpbin.locality-demo.svc.cluster.local"
```

```text
200 503 200 503 503 503 200 200 200 200 200 503 503 200 200 200 503 503 503 200 503 503 503 503 503 503 200 200 503 503 
ENDPOINT             STATUS      OUTLIER CHECK     CLUSTER
10.244.0.10:8080     HEALTHY     OK                outbound|8000||httpbin.locality-demo.svc.cluster.local
10.244.0.9:8080      HEALTHY     OK                outbound|8000||httpbin.locality-demo.svc.cluster.local
```

Many requests still fail, and both endpoints show `OUTLIER CHECK: OK`. Locality load balancing has no health checker of its own. The `zone-a` endpoint returns `503` while it stays ready, so by every measure of Istio it is healthy. There is nothing to fail over from. Something must mark the endpoint as unhealthy. That is outlier detection.

---

## Item 2: Add Outlier Detection

> **Task item 2:** Configure **`outlierDetection`** so that the proxy can mark the failing endpoint unhealthy:
>
> * `consecutive5xxErrors` **2**
> * `interval` **`5s`**
> * `baseEjectionTime` **`30s`**
> * `maxEjectionPercent` at a value that can really eject one of two endpoints

Outlier detection means that the proxy removes an endpoint from its pool for a while after it returns too many errors. Choose `maxEjectionPercent` with care. It is the largest share of endpoints that the proxy may eject at the same time. The default is 10%, and 10% of two endpoints is less than one. With the default, the proxy would count the failures and eject nothing. Use `100`. Edit `destinationrule-httpbin.yaml`. Both blocks sit under the same `trafficPolicy`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin
  namespace: locality-demo
spec:
  host: httpbin
  trafficPolicy:
    outlierDetection:
      consecutive5xxErrors: 2
      interval: 5s
      baseEjectionTime: 30s
      maxEjectionPercent: 100
    loadBalancer:
      localityLbSetting:
        enabled: true
```

Apply it:

```sh
kubectl apply -f destinationrule-httpbin.yaml
```

```text
destinationrule.networking.istio.io/httpbin configured
```

Check item 2. Print the traffic policy, and read the settings that the proxy of `tester` holds. `istiod`, the Istio control plane, sends them to the proxy:

```sh
kubectl -n locality-demo get destinationrule httpbin -o jsonpath='{.spec.trafficPolicy}{"\n"}'
istioctl proxy-config cluster deploy/tester -n locality-demo \
  --fqdn httpbin.locality-demo.svc.cluster.local -o json | grep -A6 outlierDetection
```

```text
{"loadBalancer":{"localityLbSetting":{"enabled":true}},"outlierDetection":{"baseEjectionTime":"30s","consecutive5xxErrors":2,"interval":"5s","maxEjectionPercent":100}}
        "outlierDetection": {
            "consecutive5xx": 2,
            "interval": "5s",
            "baseEjectionTime": "30s",
            "maxEjectionPercent": 100,
            "enforcingConsecutive5xx": 100,
            "enforcingSuccessRate": 0
```

The object and the proxy hold the four values. The proxy shows the field names of Envoy: `consecutive5xx` is `consecutive5xxErrors`. Outlier detection is passive, so the proxy learns only from real requests. It needs two failures in a row. Drive traffic with 60 requests:

```sh
kubectl -n locality-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 60); do curl -s -o /dev/null -w "%{http_code} " http://httpbin:8000/get; done; echo'
```

```text
503 503 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 
```

Two requests fail, then the proxy ejects the endpoint, and every later request succeeds. The change is sudden because the locality preference sends the first requests straight to the broken endpoint in the zone of the client. So the two failures that an ejection needs arrive at once.

---

## Item 4: Nothing Removed The Endpoint By Hand

> **Task item 4:** Do **not** scale, delete or fix `httpbin-zone-a`, and do not change the Service selector. The traffic must leave the locality because the proxy judged the endpoint unhealthy, not because you removed it.

You only created one `DestinationRule`. Items 5 and 9 show that the pod and the Service are untouched, and that the proxy made the decision.

---

## Item 5: Both Endpoints Still Exist

> **Task item 5:** Both endpoints still exist, and both Deployments still run 1 replica.

Run the Deployment and Service commands from the Start section again, and list the endpoints of the Service:

```sh
kubectl -n locality-demo get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n locality-demo get endpoints httpbin
kubectl -n locality-demo get svc httpbin -o jsonpath='{.spec.selector}{"\n"}'
```

```text
NAME             REPLICAS   UID
httpbin-zone-a   1          dabaad00-40d6-4a55-8d9f-e9f341639fd9
httpbin-zone-b   1          92bf8150-4baf-4979-89ab-4ee9df88b273
tester           1          932e4502-4851-4709-8bef-6d7cf57135a7
NAME      ENDPOINTS                          AGE
httpbin   10.244.0.10:8080,10.244.0.9:8080   27s
{"app":"httpbin"}
```

Both Deployments run one replica with the same `UID` values, and the Service lists both pod addresses. Kubernetes may print a warning that `Endpoints` is deprecated. You can ignore it.

---

## Items 6 And 7: The Rule Holds Both Blocks, And The Percentage Is High Enough

> **Task item 6:** The `DestinationRule` contains both `outlierDetection` and `localityLbSetting`. A locality setting **without** outlier detection is the mistake this task is about: nothing ever marks an endpoint unhealthy, so nothing ever fails over.
>
> **Task item 7:** `maxEjectionPercent` is high enough to eject one of two endpoints.

The output of item 2 shows both: the policy holds `outlierDetection` and `localityLbSetting`, and `maxEjectionPercent` is `100`.

---

## Item 8: Both Endpoints Have A Locality

> **Task item 8:** Both endpoints show a non-empty locality in the proxy's endpoint list.

```sh
istioctl proxy-config endpoints deploy/tester -n locality-demo \
  --cluster "outbound|8000||httpbin.locality-demo.svc.cluster.local" -o json \
  | grep -E '"address"|"zone"|"region"' | grep -v '{'
```

```text
                        "address": "10.244.0.10",
                    "region": "local",
                    "zone": "zone-a"
                        "address": "10.244.0.9",
                    "region": "local",
                    "zone": "zone-b"
```

Both endpoints have the region `local`, and the zones `zone-a` and `zone-b`. An endpoint with an empty locality would make every setting here a no-op, with no error.

---

## Item 9: The `zone-a` Endpoint Is Ejected

> **Task item 9:** After the grader sends traffic, the `zone-a` endpoint shows `OUTLIER CHECK: FAILED`, or the ejection counters have increased.

```sh
istioctl proxy-config endpoints deploy/tester -n locality-demo \
  --cluster "outbound|8000||httpbin.locality-demo.svc.cluster.local"
```

```text
ENDPOINT             STATUS      OUTLIER CHECK     CLUSTER
10.244.0.10:8080     HEALTHY     FAILED            outbound|8000||httpbin.locality-demo.svc.cluster.local
10.244.0.9:8080      HEALTHY     OK                outbound|8000||httpbin.locality-demo.svc.cluster.local
```

`10.244.0.10` is the `zone-a` pod. The `STATUS` column comes from the readiness of Kubernetes, and it still says `HEALTHY`. The `OUTLIER CHECK` column says `FAILED`: this proxy ejected the endpoint. The ejection ends after `baseEjectionTime`. If every row says `OK`, send more requests and check again.

---

## Item 10: Requests Succeed From `zone-b`

> **Task item 10:** Almost all requests measured afterwards succeed, because they now go to `zone-b`.

Send 40 requests. Then count the endpoints in the access log of the `tester` proxy. Wait a moment before you read the log, because the proxy writes the line a moment after the request:

```sh
kubectl -n locality-demo exec deploy/tester -- sh -c \
  'for i in $(seq 1 40); do curl -s -o /dev/null -w "%{http_code}\n" http://httpbin:8000/get; done' | sort | uniq -c
sleep 3
kubectl -n locality-demo logs deploy/tester -c istio-proxy --tail=40 \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8080' | sort | uniq -c
```

```text
  40 200
  40 10.244.0.9:8080
```

All 40 requests succeeded, and the `zone-b` pod `10.244.0.9` served all of them. The traffic left the locality of the client because the proxy judged the endpoint there as unhealthy. That is the failover path, and nobody removed the endpoint.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-040/module-04/labs/lab-01
```

The grader reads the object, the endpoints of the proxy, and live requests.

---

## Mistakes That Fail The Grader

- **`localityLbSetting` without `outlierDetection` (items 1, 3 and 6).** This is the main mistake. Locality load balancing has no health checker of its own, and nothing ever fails over.
- **Leaving `maxEjectionPercent` at 10% (items 2 and 7).** With two endpoints, the proxy may eject none of them, so nothing happens.
- **Using `failover` (item 3).** It works between regions, and there is one region here. With `outlierDetection` in place, the locality preference already moves requests between zones.
- **Scaling `httpbin-zone-a` to zero (items 4 and 5).** That is endpoint removal, and it works without outlier detection. It proves nothing, and the grader checks the replica count.
- **Not checking the localities first (item 8).** An endpoint with an empty locality makes every setting here a no-op, with no error.
- **Testing with too few requests (item 9).** Passive detection needs the failures to happen first.
