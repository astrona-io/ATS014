# Solution Walkthrough

The walkthrough follows the task from top to bottom, and each section ends with a check. Four features act on one host. The `Service` asks for nearby endpoints. The `DestinationRule` holds the connection settings and outlier detection. The `VirtualService` holds the route timeout and the retries. The live test in the last section needs all of them together.

---

## Start: Look At The Starting State

The task says that no `VirtualService`, `DestinationRule` or `trafficDistribution` exists, and that the nearest endpoint is a pod that fails but stays ready. Check the objects and the pods, then send ten requests and print the status code of each:

```sh
kubectl -n starfleet get destinationrule,virtualservice
kubectl get service probe -n starfleet -o jsonpath='{.spec.trafficDistribution}{"\n"}'
kubectl -n starfleet get pods -L istio-locality
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} " http://probe:8000/hostname
done; echo
```

`kubectl` finds no `DestinationRule` or `VirtualService`, the field is empty, and the pod list shows the failing pod in `local.zone-a` and the healthy pod in `local.zone-b`. The status codes are a mix of `200` and `503`: the requests are spread over both pods, and the failing pod answers `503` every time. The healthy answers come from `probe-zone-b`.

---

## Task Item 1: Prefer Close Endpoints On The Service

> **Task item 1:** Make the `probe` Service prefer endpoints that are close to the client, with the Kubernetes `Service` field for it. Keep its selector and port as they are.

Save this as `service-probe.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: probe
  namespace: starfleet
  labels:
    app: probe
spec:
  selector:
    app: probe
  trafficDistribution: PreferClose
  ports:
  - name: http
    port: 8000
    targetPort: 8080
```

Apply it:

```sh
kubectl apply -f service-probe.yaml
```

Check it:

```sh
kubectl get service probe -n starfleet -o jsonpath='{.spec.trafficDistribution}{"\n"}'
```

The command prints `PreferClose`. From now on the proxy of `shuttle` prefers the pod in its own zone, which is the failing pod. That is why the next two items matter.

---

## Task Item 2: Connection Settings And Outlier Detection

> **Task item 2:** Create a `DestinationRule` named `probe` in the namespace `starfleet` for the host `probe` with the connect timeout `2s`, the HTTP idle timeout `60s`, the maximum connection duration `5m`, TCP keepalive (time `30s`, interval `10s`, `3` probes) and outlier detection (`2` consecutive `5xx` errors, interval `5s`, base ejection time `30s`, up to `100` percent ejected).

Save this as `destinationrule-probe.yaml`. The connection settings go in `connectionPool` (`connectTimeout`, `maxConnectionDuration` and `tcpKeepalive` under `tcp`, `idleTimeout` under `http`), and outlier detection is its own block:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  trafficPolicy:
    connectionPool:
      tcp:
        connectTimeout: 2s
        maxConnectionDuration: 5m
        tcpKeepalive:
          time: 30s
          interval: 10s
          probes: 3
      http:
        idleTimeout: 60s
    outlierDetection:
      consecutive5xxErrors: 2
      interval: 5s
      baseEjectionTime: 30s
      maxEjectionPercent: 100
```

Apply it:

```sh
kubectl apply -f destinationrule-probe.yaml
```

Read the connection settings from the proxy of `shuttle`:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet \
  --fqdn probe.starfleet.svc.cluster.local --port 8000 -o json \
  | grep -E '"connectTimeout"|"idleTimeout"|"maxConnectionDuration"|"keepalive'
```

The proxy shows `connectTimeout` `2s`, `idleTimeout` `60s`, `maxConnectionDuration` `300s`, which is `5m`, and the keepalive values `3` probes, `30` for the time and `10` for the interval. If a line is missing, wait a few seconds and run the command again.

---

## Task Item 3: Route Timeout And Retries

> **Task item 3:** Create a `VirtualService` named `probe` in the namespace `starfleet` for the host `probe` that routes every request to the `probe` host with a route timeout of `3s`, and retries with `2` attempts, a per-try timeout of `1s` and `5xx` as the retry condition.

The timeout must cover all tries: three tries of one second each fit in three seconds. Save this as `virtualservice-probe.yaml`:

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
  - route:
    - destination:
        host: probe
    timeout: 3s
    retries:
      attempts: 2
      perTryTimeout: 1s
      retryOn: 5xx
```

Apply it:

```sh
kubectl apply -f virtualservice-probe.yaml
```

Check it:

```sh
kubectl -n starfleet get virtualservice probe -o jsonpath='{.spec.http[0].timeout} {.spec.http[0].retries}{"\n"}'
```

The command prints the timeout `3s` and the retry settings you wrote.

---

## Task Item 4: Prove The Behaviour

> **Task item 4:** After the failing pod has been ejected, 20 requests to `http://probe:8000/hostname` all return status code `200` and are all answered by `probe-zone-b`, and a request to `http://probe:8000/delay/5` returns `504` after about three seconds.

The failing pod is still the nearest endpoint, so the first requests reach it. The route retries the `503`, and each error counts towards outlier detection. After two errors in a row the proxy ejects the pod, and the requests move to `probe-zone-b`. Send a few requests to trigger the ejection:

```sh
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} " http://probe:8000/hostname
done; echo
```

Look at the endpoint list of the proxy. The failing pod now shows `FAILED` in the `OUTLIER CHECK` column, while its `STATUS` column still says `HEALTHY`, because Kubernetes still considers it ready:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|8000||probe.starfleet.svc.cluster.local"
```

Next, the slow request. `-w` prints the status code and the total time:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}\n" http://probe:8000/delay/5
```

The status code is `504` and the time is about three seconds: the proxy gave up at the route timeout, while the probe was still waiting. Finally count the pods that answer 20 requests. The ejection lasts at least 30 seconds, so run this soon after the steps above:

```sh
for i in $(seq 1 20); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-zone-[ab]'
done | sort | uniq -c
```

The count shows one line: 20 answers from `probe-zone-b`. The preference for the nearby pod gave way, because outlier detection removed that pod from the endpoints the proxy may use.

---

## Submit

```sh
astrona submit -c sections/section-040/capstone/labs/lab-02
```

## Mistakes That Fail The Grader

- **Item 1: `trafficDistribution` in the `DestinationRule`.** The field belongs to the `Service` under `spec`.
- **Item 2: `idleTimeout` under `tcp`.** It belongs under `http`.
- **Item 2: `maxEjectionPercent` at its default.** With the default of 10 percent, one of two endpoints is never ejected, and requests keep failing.
- **Item 2: `localityLbSetting` in the `DestinationRule`.** The preference must come from the `Service`.
- **Item 3: a route `timeout` shorter than the retry budget.** Three tries of one second need at least three seconds. The grader expects `3s`, `2` attempts and `1s` per try.
- **Item 3: leaving `5xx` out of `retryOn`.** The failing pod's `503` is then never retried, and the first requests fail.
- **Item 4: scaling or deleting the failing pod.** That removes the endpoint instead of letting the proxy eject it. The grader checks that all three Deployments still run.
- **Item 4: testing too late.** The ejection lasts at least `baseEjectionTime`. If the pod comes back and fails again, the proxy ejects it again after two errors.
