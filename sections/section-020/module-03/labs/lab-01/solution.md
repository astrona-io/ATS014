# Solution

The walkthrough follows the task from top to bottom, and each section ends with a check. Items 3, 4 and 5 are results of items 1 and 2, so they are checked after the objects exist.

## Start

Look at the starting state. The Service `probe-tcp` exists, its port is named `tcp`, and nothing else for it exists:

```bash
kubectl get service probe-tcp -n starfleet -o jsonpath='{.spec.ports[0].name}'
kubectl get virtualservice,destinationrule -n starfleet
```

The first command prints `tcp`. The second command finds no `VirtualService` and no `DestinationRule`. Because the port name is `tcp`, Istio treats the traffic as plain TCP, so the weighted route goes into the `tcp` section of a `VirtualService`, not into `http`.

## Item 1: the DestinationRule

> **Task item 1:** A `DestinationRule` for the host `probe-tcp` defines the subsets `v1` and `v2`, each selecting on the pods' `version` label.

Save this as `destinationrule-probe-tcp.yaml`:

```yaml
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
kubectl apply -f destinationrule-probe-tcp.yaml
```

Check that the proxy of `shuttle` now has a cluster for each subset:

```bash
istioctl proxy-config clusters deploy/shuttle -n starfleet --fqdn probe-tcp.starfleet.svc.cluster.local
```

The list should show `v1` and `v2` in the subset column.

## Item 2: the tcp route

> **Task item 2:** There is exactly one `VirtualService` for the host `probe-tcp`. It has a `tcp` route that matches port `8000` and sends 80 to subset `v1` and 20 to subset `v2`.

Save this as `virtualservice-probe-tcp.yaml`:

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
      weight: 80
    - destination:
        host: probe-tcp
        subset: v2
        port:
          number: 8000
      weight: 20
```

Apply it:

```bash
kubectl apply -f virtualservice-probe-tcp.yaml
```

Check the weights in the object:

```bash
kubectl get virtualservice probe-tcp -n starfleet -o jsonpath='{.spec.tcp[0].match[0].port} {.spec.tcp[0].route[*].weight}'
```

It should print `8000 80 20`. The `match` uses port `8000`, the Service port. The container port `8080` would never match.

## Item 3: the proxy holds the split

> **Task item 3:** The proxy of `shuttle` holds the split: the listener for port `8000` has weighted clusters for `outbound|8000|v1|probe-tcp.starfleet.svc.cluster.local` and `outbound|8000|v2|probe-tcp.starfleet.svc.cluster.local`.

`istiod` needs a moment to push the route. Read the listener as JSON:

```bash
istioctl proxy-config listener deploy/shuttle -n starfleet --port 8000 -o json | grep -A12 weightedClusters
```

You should see a `weightedClusters` block with the two cluster names and their weights. If it is empty, wait a few seconds and run the command again.

## Item 4: a reused connection stays on one pod

> **Task item 4:** One reused connection stays on one pod. The grader sends 15 requests over one connection, five times, and every one of those five runs must be answered by a single pod.

This follows from the route. The proxy picks a subset once, when the connection opens. Send 15 requests over one connection with the helper, and repeat it:

```bash
astrona res run count-reused.sh -- 15
astrona res run count-reused.sh -- 15
```

Each run should show 15 answers from one pod name. If one run shows two pod names, the Service port is probably not treated as TCP.

## Item 5: fresh connections split 80/20

> **Task item 5:** The split is real. The grader opens 150 fresh connections and counts the answers. Between 15 and 45 of them must come from `probe-v2`, and all the others from `probe-v1`.

Open 150 fresh connections with the helper:

```bash
astrona res run count-connections.sh -- 150
```

You should see about 120 answers from `probe-v1` and about 30 from `probe-v2`. The count changes from run to run. The grader accepts 15 to 45 for `probe-v2`.

## Item 6: leave the workloads alone

> **Task item 6:** Leave the Deployments, the pod labels and the Services unchanged, and do not add or remove workloads.

You changed none of them: the solution only adds a `DestinationRule` and a `VirtualService`. Check that the three Deployments are still there:

```bash
kubectl get deployments -n starfleet
```

## Submit

When all items are done, send the lab for grading:

```bash
astrona submit -c sections/section-020/module-03/labs/lab-01
```

## Mistakes That Fail The Grader

- **Writing the route in `http` instead of `tcp` (items 2, 3, 5).** The port is named `tcp`, so an `http` route never applies.
- **Matching port `8080` (item 2).** `match.port` is the Service port, `8000`.
- **Weights that are not 80 and 20 (item 2).** The grader reads the weights from the object.
- **Wrong labels in a subset (items 1, 5).** A subset that selects no pod gives its connections no endpoint, and the count of answers is below 150.
- **A second `VirtualService` for the same host (item 2).** There must be exactly one.
- **Judging the split from a few connections (item 5).** Count at least 100 fresh connections.
- **Changing the Service or the pods (item 6).** Do not rename the port or relabel the pods.
