# Solution

The walkthrough follows the task from top to bottom, and each section ends with a check. Items 5, 6 and 7 are results of the objects from items 1 to 4, so you check them after the objects exist.

## Start

Look at the starting state, and note the two port names:

```bash
kubectl get pods,services -n starfleet
kubectl get service probe probe-tcp -n starfleet -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.ports[0].name}{"\n"}{end}'
kubectl get virtualservice,destinationrule -n starfleet
```

The Service `probe` has a port named `http`, and `probe-tcp` has a port named `tcp`. There is no `VirtualService` and no `DestinationRule`. The port names decide where each route goes: the weighted HTTP rule goes into the `http` section of a `VirtualService`, and the TCP split into the `tcp` section.

## Item 1: the DestinationRules

> **Task item 1:** A `DestinationRule` for the host `probe` and a `DestinationRule` for the host `probe-tcp` each define the subsets `v1` and `v2`, selecting on the pods' `version` label.

Subsets belong to a host, so each host needs its own rule. Save this as `destinationrules.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe
  namespace: starfleet
spec:
  host: probe
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: probe-tcp
  namespace: starfleet
spec:
  host: probe-tcp
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
```

Apply it:

```bash
kubectl apply -f destinationrules.yaml
```

Check that both hosts have subset clusters in the proxy of `shuttle`:

```bash
istioctl proxy-config clusters deploy/shuttle -n starfleet --fqdn probe.starfleet.svc.cluster.local
istioctl proxy-config clusters deploy/shuttle -n starfleet --fqdn probe-tcp.starfleet.svc.cluster.local
```

Each list should show `v1` and `v2` in the subset column.

## Items 2 and 3: the HTTP VirtualService

> **Task item 2:** There is exactly one `VirtualService` for the host `probe`. A request with the header `x-tester: yes` goes to subset `v2` only. Every other request goes to `v1` (weight 80) or `v2` (weight 20).
>
> **Task item 3:** The same rule that holds the 80/20 split mirrors 100% of its requests to the host `probe-shadow`.

The two items share one object. The header rule comes first, because rules are read top to bottom and the first match wins. The default rule has no `match`, holds the weighted route and carries the `mirror`. Save this as `virtualservice-probe.yaml`:

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
  - match:
    - headers:
        x-tester:
          exact: "yes"
    route:
    - destination:
        host: probe
        subset: v2
  - route:
    - destination:
        host: probe
        subset: v1
      weight: 80
    - destination:
        host: probe
        subset: v2
      weight: 20
    mirror:
      host: probe-shadow
    mirrorPercentage:
      value: 100.0
```

Apply it:

```bash
kubectl apply -f virtualservice-probe.yaml
```

Check the header rule first, with five requests that carry the header:

```bash
for i in 1 2 3 4 5; do kubectl exec -n starfleet deploy/shuttle -- curl -s -H 'x-tester: yes' http://probe:8000/hostname; echo; done
```

Every answer should name a `probe-v2` pod. The weighted split and the mirror are checked in item 6.

## Item 4: the TCP VirtualService

> **Task item 4:** There is exactly one `VirtualService` for the host `probe-tcp`. It has a `tcp` route that matches port `8000` and sends 70 to subset `v1` and 30 to subset `v2`.

Because the port of `probe-tcp` is named `tcp`, the route goes into the `tcp` section. The `match` uses the Service port `8000`. Save this as `virtualservice-probe-tcp.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe-tcp
  namespace: starfleet
spec:
  hosts:
  - probe-tcp
  tcp:
  - match:
    - port: 8000
    route:
    - destination:
        host: probe-tcp
        subset: v1
        port:
          number: 8000
      weight: 70
    - destination:
        host: probe-tcp
        subset: v2
        port:
          number: 8000
      weight: 30
```

Apply it:

```bash
kubectl apply -f virtualservice-probe-tcp.yaml
```

Check the weights in the object:

```bash
kubectl get virtualservice probe-tcp -n starfleet -o jsonpath='{.spec.tcp[0].match[0].port} {.spec.tcp[0].route[*].weight}'
```

It should print `8000 70 30`. A mirror cannot be added to a `tcp` route, which is why the shadow only follows the web traffic.

## Item 5: the proxy holds both

> **Task item 5:** The proxy of `shuttle` holds the mirror policy for `outbound|8000||probe-shadow.starfleet.svc.cluster.local` in its route table, and weighted clusters for the two `probe-tcp` subsets in its listener for port `8000`.

Wait a few seconds for `istiod` to push the configuration, then read both:

```bash
istioctl proxy-config routes deploy/shuttle -n starfleet -o json | grep -A2 requestMirrorPolicies
istioctl proxy-config listener deploy/shuttle -n starfleet --port 8000 -o json | grep -A12 weightedClusters
```

The first command should show a mirror policy that names the cluster of `probe-shadow`. The second should show a `weightedClusters` block with the `v1` and `v2` clusters of `probe-tcp`.

## Item 6: HTTP behaves per request

> **Task item 6:** HTTP behaves per request. The grader sends 20 requests with `x-tester: yes`, and all must be answered by `probe-v2`. It sends 150 requests without the header: between 15 and 45 must come from `probe-v2`, all the others from `probe-v1`, and none from `probe-shadow`. At least 135 copies must reach `probe-shadow`. It also sends 60 requests over one connection to `probe`, and both versions must answer.

Take a time stamp, send 150 requests from separate `curl` processes, and count the answers and the copies that the shadow received:

```bash
START_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
astrona res run count-connections.sh -- 150 probe:8000
sleep 4
kubectl logs -n starfleet deploy/probe-shadow -c probe --since-time=$START_TIME | grep -c 'GET /hostname'
```

You should see about 120 answers from `probe-v1` and about 30 from `probe-v2`, none from the shadow, and a copy count close to 150. Then send 60 requests over one connection:

```bash
astrona res run count-reused.sh -- 60 probe:8000
```

Both versions should appear, because an `http` route picks for every request, even on one connection.

## Item 7: TCP behaves per connection

> **Task item 7:** TCP behaves per connection. The grader sends 15 requests over one connection to `probe-tcp`, five times, and each run must be answered by a single pod. It opens 150 fresh connections to `probe-tcp`: between 25 and 65 must come from `probe-v2`, and the others from `probe-v1`.

Send 15 requests over one connection, and then open 150 fresh connections:

```bash
astrona res run count-reused.sh -- 15
astrona res run count-connections.sh -- 150
```

The first run should show one pod name for all 15 answers. The second should show about 105 answers from `probe-v1` and about 45 from `probe-v2`, and the numbers change from run to run.

## Item 8: leave the workloads alone

> **Task item 8:** Leave the Deployments, the pod labels and the Services unchanged, and do not add or remove workloads.

You only added Istio objects. Check that the four Deployments are still there:

```bash
kubectl get deployments -n starfleet
```

## Submit

When all items are done, send the lab for grading:

```bash
astrona submit -c sections/section-020/capstone/labs/lab-02
```

## Mistakes That Fail The Grader

- **Putting the header rule below the default rule (items 2, 6).** The default rule has no `match`, so it takes every request first and the testers get the 80/20 split.
- **Putting the mirror in the route (items 3, 6).** A mirror is a sibling of `route`, with no weight. As a route destination it would take part in the split and return responses to clients.
- **Mirroring to a subset of `probe` (items 3, 5).** The shadow is a separate host, `probe-shadow`.
- **Writing the TCP split in `http` (items 4, 5, 7).** The port is named `tcp`, so only the `tcp` section applies.
- **Matching port `8080` (item 4).** `match.port` is the Service port `8000`.
- **Wrong weights (items 2, 4).** The grader reads 80/20 for HTTP and 70/30 for TCP from the objects.
- **Judging a split from a few samples (items 6, 7).** Count at least 100 requests or fresh connections.
- **Counting TCP requests over one connection (item 7).** One connection makes one pick.
- **One `DestinationRule` for both hosts (item 1).** Subsets belong to a host, so each host needs its own.
- **Changing the workloads or Services (item 8).**
