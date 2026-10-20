# Solution Walkthrough

The `DestinationRule` was correct all along. The pod template of `probe-zone-b` has lost its `istio-locality` label, so the pod takes the locality of the node, `local/zone-a`. The sidecar proxy of `shuttle` then sees two probes in its own zone and splits its requests between them. The walkthrough follows the three parts of the task and then the rules. A locality is the region and zone that a pod runs in. The sidecar proxy is the Envoy container that Istio adds to each pod.

---

## Start: See The Mix

The task says that the `shuttle` should send every request to the probe in its own zone, but its requests go to both probes. Look at the Deployments, the `DestinationRule`, and the node. Then send 20 requests from `shuttle`. The path `/hostname` returns the name of the pod that served the request:

```sh
kubectl -n starfleet get deploy
kubectl -n starfleet get destinationrule probe -o jsonpath='{.spec.trafficPolicy}{"\n"}'
kubectl get node -L topology.kubernetes.io/region,topology.kubernetes.io/zone | awk '{print $1,$NF,$(NF-1)}'
for i in $(seq 1 20); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-zone-[ab]'
done | sort | uniq -c
```

```text
NAME           READY   UP-TO-DATE   AVAILABLE   AGE
probe-zone-a   1/1     1            1           22s
probe-zone-b   1/1     1            1           22s
shuttle        1/1     1            1           22s
{"loadBalancer":{"localityLbSetting":{"enabled":true}},"outlierDetection":{"baseEjectionTime":"30s","consecutive5xxErrors":2,"interval":"5s","maxEjectionPercent":100}}
NAME ZONE REGION
astro-ats-014-lab-040-04-02-control-plane zone-a local
  12 probe-zone-a
   8 probe-zone-b
```

The `DestinationRule` has the locality setting and outlier detection, so the preference is on. The node has the region `local` and the zone `zone-a`. Yet both probes answer. The `awk` command in the node line prints three columns: the node name, the zone and the region.

---

## Task 1: Find The Locality Of Each Probe Endpoint

> **Task part 1:** Find out, from the endpoint list of the `shuttle` proxy, which locality each probe endpoint has.

An endpoint is the address of one pod. Ask the proxy of `shuttle` for the endpoints of the `probe` cluster, and list the pods with their `istio-locality` label. A cluster is a named destination in Envoy:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|8000||probe.starfleet.svc.cluster.local" -o json \
  | grep -E '"zone"|"address"'
kubectl -n starfleet get pods -l app=probe -L istio-locality,topology.kubernetes.io/zone
```

```text
                "address": {
                        "address": "10.244.0.7",
                    "zone": "zone-a"
                "address": {
                        "address": "10.244.0.9",
                    "zone": "zone-a"
NAME                            READY   STATUS    RESTARTS   AGE   ISTIO-LOCALITY   ZONE
probe-zone-a-846b7b8d66-68wwk   2/2     Running   0          24s   local.zone-a     zone-a
probe-zone-b-857f449bf8-kt922   2/2     Running   0          9s                     zone-a
```

Both endpoints are in `zone-a`. The pod `probe-zone-a` has the label `istio-locality=local.zone-a`. The pod `probe-zone-b` has no `istio-locality` label, so it inherits the zone of the node, `zone-a`. That is the fault.

Save the state that the rules must keep:

```sh
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n starfleet get destinationrule probe -o jsonpath='generation={.metadata.generation}{"\n"}'
kubectl -n starfleet get deploy shuttle probe-zone-a -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.template.metadata.labels}{"\n"}{end}'
kubectl -n starfleet get svc probe -o jsonpath='{.spec.selector} {.spec.ports[0].port}{"\n"}'
kubectl get node -o jsonpath='{.items[0].metadata.labels}' | tr ',' '\n' | grep topology
```

```text
NAME           UID
probe-zone-a   f6db671e-42ff-4b79-928f-1422c14c4baa
probe-zone-b   b8b119a3-635a-469c-a3ff-62aa35644907
shuttle        7f7c5cc3-1817-482b-b587-4c68bca96cf9
generation=1
shuttle {"app":"shuttle"}
probe-zone-a {"app":"probe","istio-locality":"local.zone-a","zone":"a"}
{"app":"probe"} 8000
"topology.kubernetes.io/region":"local"
"topology.kubernetes.io/zone":"zone-a"}
```

---

## Task 2: Give The Pod The Locality It Is Meant To Have

> **Task part 2:** Give the probe that runs in the wrong locality the locality it is meant to run in.

The cluster has a single node, so the fix belongs on the probe pod itself. Put the `istio-locality` label back on the **pod template** of `probe-zone-b`. The value uses a dot, because a label value cannot contain a slash:

```sh
kubectl -n starfleet patch deployment probe-zone-b --type merge \
  -p '{"spec":{"template":{"metadata":{"labels":{"istio-locality":"local.zone-b"}}}}}'
kubectl -n starfleet rollout status deployment probe-zone-b
```

```text
deployment.apps/probe-zone-b patched
Waiting for deployment "probe-zone-b" rollout to finish: 0 out of 1 new replicas have been updated...
Waiting for deployment "probe-zone-b" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "probe-zone-b" rollout to finish: 1 old replicas are pending termination...
deployment "probe-zone-b" successfully rolled out
```

A change to the pod template makes Kubernetes start a new pod, and Istio reads the locality when the pod starts. Check the pods and the endpoints again:

```sh
kubectl -n starfleet get pods -l app=probe -L istio-locality
istioctl proxy-config endpoints deploy/shuttle -n starfleet \
  --cluster "outbound|8000||probe.starfleet.svc.cluster.local" -o json \
  | grep -E '"zone"|"address"'
```

```text
NAME                            READY   STATUS    RESTARTS   AGE   ISTIO-LOCALITY
probe-zone-a-846b7b8d66-68wwk   2/2     Running   0          35s   local.zone-a
probe-zone-b-56b7474bd-jdrsm    2/2     Running   0          10s   local.zone-b
                "address": {
                        "address": "10.244.0.7",
                    "zone": "zone-a"
                "address": {
                        "address": "10.244.0.10",
                    "zone": "zone-b"
```

Now there is one probe in each zone. If the endpoint list still shows two probes in `zone-a`, wait a few seconds for `istiod`, the Istio control plane, to send the change to the proxy, and run the command again.

---

## Task 3: Prove That Every Request Stays In The Zone Of `shuttle`

> **Task part 3:** Prove that 20 requests from `shuttle` all reach `probe-zone-a`.

```sh
for i in $(seq 1 20); do
  kubectl -n starfleet exec deploy/shuttle -- curl -s http://probe:8000/hostname | grep -o 'probe-zone-[ab]'
done | sort | uniq -c
```

```text
  20 probe-zone-a
```

All 20 requests reached `probe-zone-a`. At the start, 8 of 20 went to `probe-zone-b`. The pod `probe-zone-b` is now a fallback, used only when `zone-a` has no healthy probe left.

---

## Rules: Nothing Else Changed

> **Task rules:** Do not change the node's labels, the `shuttle` Deployment, the `probe-zone-a` Deployment, the `probe` Service or the `probe` `DestinationRule`. Do not add or remove Deployments.

Run the five commands from task 1 again:

```sh
kubectl -n starfleet get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n starfleet get destinationrule probe -o jsonpath='generation={.metadata.generation}{"\n"}'
kubectl -n starfleet get deploy shuttle probe-zone-a -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.template.metadata.labels}{"\n"}{end}'
kubectl -n starfleet get svc probe -o jsonpath='{.spec.selector} {.spec.ports[0].port}{"\n"}'
kubectl get node -o jsonpath='{.items[0].metadata.labels}' | tr ',' '\n' | grep topology
```

```text
NAME           UID
probe-zone-a   f6db671e-42ff-4b79-928f-1422c14c4baa
probe-zone-b   b8b119a3-635a-469c-a3ff-62aa35644907
shuttle        7f7c5cc3-1817-482b-b587-4c68bca96cf9
generation=1
shuttle {"app":"shuttle"}
probe-zone-a {"app":"probe","istio-locality":"local.zone-a","zone":"a"}
{"app":"probe"} 8000
"topology.kubernetes.io/region":"local"
"topology.kubernetes.io/zone":"zone-a"}
```

The output is the same as before. The same three Deployments exist with the same `UID` values, the `DestinationRule` still has `generation=1`, and the node labels, the other pod templates and the Service did not change. The only change is the label on the pod template of `probe-zone-b`.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-040/module-04/labs/lab-02
```

The grader checks the locality of the pod, the endpoints of the `shuttle` proxy, and live requests.

---

## Mistakes That Fail The Grader

- **Putting the label on the `metadata` of the Deployment itself (task 2).** Only labels on the pod template reach the pods.
- **Writing `local/zone-b` (task 2).** Kubernetes rejects a slash in a label value. Use `local.zone-b`.
- **Relabelling the node (task 2 and rules).** The node runs `shuttle` and both probes, so a new node label moves every pod together.
- **Adding `distribute` to the `DestinationRule` (rules).** Fixed weights hide the problem instead of fixing the locality of the pod, and the `DestinationRule` must stay unchanged.
