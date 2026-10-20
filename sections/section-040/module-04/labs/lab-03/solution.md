# Solution Walkthrough

The starting `DestinationRule` switches the locality preference on, so the sidecar proxy of `shuttle` sends every request to `zone-a`. A fixed split needs `distribute` instead. `distribute` sets exact weights for requests that start in a given locality. A locality is the region, zone and subzone that a pod runs in. The walkthrough follows the task, then the rules.

---

## Start: Look At The Starting State

The task says that the `probe` `DestinationRule` has outlier detection and the locality preference, so `probe-zone-b` receives no requests. Look at the `DestinationRule`, at the localities of the pods, and send 20 requests from `shuttle`. The path `/hostname` returns the name of the pod that served the request:

```sh
kubectl -n starfleet get destinationrule
kubectl -n starfleet get destinationrule probe -o jsonpath='{.spec.trafficPolicy}{"\n"}'
kubectl -n starfleet get pods -L istio-locality | awk '{print $1,$2,$3,$NF}'
for i in $(seq 1 20); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-zone-[ab]'
done | sort | uniq -c
```

```text
NAME    HOST    AGE
probe   probe   1s
{"loadBalancer":{"localityLbSetting":{"enabled":true}},"outlierDetection":{"baseEjectionTime":"30s","consecutive5xxErrors":2,"interval":"5s","maxEjectionPercent":100}}
NAME READY STATUS ISTIO-LOCALITY
probe-zone-a-846b7b8d66-txvxc 2/2 Running local.zone-a
probe-zone-b-56b7474bd-9q2v2 2/2 Running local.zone-b
shuttle-7b5db664c-tgrd6 2/2 Running 16s
```

The last line of the pod list has no `istio-locality` label, so `awk` prints the age in its place. All 20 requests went to `probe-zone-a`, and `probe-zone-b` got none:

```text
  20 probe-zone-a
```

The rules of the task say not to change the Deployments, their labels or the Service. Save their identity now:

```sh
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n starfleet get deploy -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.template.metadata.labels}{"\n"}{end}'
kubectl -n starfleet get svc probe -o jsonpath='{.spec.selector} {.spec.ports[0].port}{"\n"}'
```

```text
NAME           REPLICAS   UID
probe-zone-a   1          79d5b7fe-831a-4d79-9766-7b20e4c818a7
probe-zone-b   1          2dab4546-a487-4aa6-8b94-c6e38391f458
shuttle        1          c8cf887e-5cef-4a2a-9590-df74dbe2badc
probe-zone-a {"app":"probe","istio-locality":"local.zone-a","zone":"a"}
probe-zone-b {"app":"probe","istio-locality":"local.zone-b","zone":"b"}
shuttle {"app":"shuttle"}
{"app":"probe"} 8000
```

---

## Task: Split The Traffic 80 To 20

> **Task:** Change the `probe` `DestinationRule` so that requests sent from `local/zone-a`, any subzone, are split:
>
> * **80** to `local/zone-a`, any subzone
> * **20** to `local/zone-b`, any subzone
>
> Then prove it: out of 100 requests from `shuttle`, about 80 reach `probe-zone-a` and about 20 reach `probe-zone-b`.

A `DestinationRule` is the Istio object that holds policies for traffic to one host. Add `distribute` inside `localityLbSetting`. Each entry of `distribute` has a `from`, which is the locality of the client, and a `to`, which maps localities to weights:

- `from: local/zone-a/*` matches the locality of `shuttle`: region `local`, zone `zone-a`, any subzone.
- The two weights add up to exactly 100. Istio rejects any other total.
- In a `DestinationRule`, write localities with slashes, as in `local/zone-a/*`. The dot format `local.zone-a` is only for the `istio-locality` pod label.
- `distribute` does not need `outlierDetection`, so the file below leaves it out. Keeping it would also work.

Save this as `destinationrule-probe.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  trafficPolicy:
    loadBalancer:
      localityLbSetting:
        enabled: true
        distribute:
        - from: local/zone-a/*
          to:
            "local/zone-a/*": 80
            "local/zone-b/*": 20
```

Apply it:

```sh
kubectl apply -f destinationrule-probe.yaml
```

```text
destinationrule.networking.istio.io/probe configured
```

Check the object. Print the locality setting:

```sh
kubectl -n starfleet get destinationrule probe \
  -o jsonpath='{.spec.trafficPolicy.loadBalancer.localityLbSetting}{"\n"}'
```

```text
{"distribute":[{"from":"local/zone-a/*","to":{"local/zone-a/*":80,"local/zone-b/*":20}}],"enabled":true}
```

The object holds one `distribute` entry with the weights 80 and 20. Now prove the split with 100 requests. `istiod`, the Istio control plane, sends the change to the sidecar proxy of `shuttle`. If the first run still shows 100 requests in `zone-a`, wait a few seconds and send them again:

```sh
for i in $(seq 1 100); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-zone-[ab]'
done | sort | uniq -c
```

```text
  80 probe-zone-a
  20 probe-zone-b
```

80 requests reached `probe-zone-a` and 20 reached `probe-zone-b`. The proxy picks a zone by weight for each request, so a few requests of difference from run to run are normal.

---

## Rules: Nothing Else Changed

> **Rule 1:** Keep the name `probe` for the `DestinationRule`, and do not create a second one.
>
> **Rule 2:** Do not change the Deployments, their labels or the `probe` Service.

List the `DestinationRule` objects, and run the Deployment, label and Service commands from the Start section again:

```sh
kubectl -n starfleet get destinationrule
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,UID:.metadata.uid
kubectl -n starfleet get deploy -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.template.metadata.labels}{"\n"}{end}'
kubectl -n starfleet get svc probe -o jsonpath='{.spec.selector} {.spec.ports[0].port}{"\n"}'
```

```text
NAME    HOST    AGE
probe   probe   17s
NAME           REPLICAS   UID
probe-zone-a   1          79d5b7fe-831a-4d79-9766-7b20e4c818a7
probe-zone-b   1          2dab4546-a487-4aa6-8b94-c6e38391f458
shuttle        1          c8cf887e-5cef-4a2a-9590-df74dbe2badc
probe-zone-a {"app":"probe","istio-locality":"local.zone-a","zone":"a"}
probe-zone-b {"app":"probe","istio-locality":"local.zone-b","zone":"b"}
shuttle {"app":"shuttle"}
{"app":"probe"} 8000
```

There is one `DestinationRule`, named `probe`. The Deployments have the same `UID` values and the same labels, and the Service is the same.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-040/module-04/labs/lab-03
```

The grader reads the `DestinationRule` and sends 100 live requests.

---

## Mistakes That Fail The Grader

- **Weights that do not add up to 100.** Istio rejects the object with `total locality weight ... != 100`.
- **Writing the localities with dots.** Dots are only for the `istio-locality` pod label. In a `DestinationRule`, use slashes: `local/zone-a/*`.
- **Adding `failover` as well.** `distribute` and `failover` cannot be combined for one host.
- **A `from` that does not match `shuttle`.** A client whose locality matches no `from` keeps the normal behaviour, so nothing changes.
