# Solution

The walkthrough follows the task from top to bottom, and each section ends with a check. Item 3 is about what you must not change, so it is checked after the fixes. Items 4 and 5 are results of items 1 and 2.

## Start

Look at the starting state, and find the first symptom. The route table of the proxy of `shuttle` for port `8000` lists a host for `probe-tcp`, which a TCP port would not have, and the listener has no weighted clusters:

```bash
kubectl get service probe-tcp -n starfleet -o jsonpath='{.spec.ports[0].name}'
istioctl proxy-config routes deploy/shuttle -n starfleet --name 8000
istioctl proxy-config listener deploy/shuttle -n starfleet --port 8000 -o json | grep -c weightedClusters
astrona res run count-connections.sh -- 40
```

The Service port is named `http`. The route table lists `probe-tcp.starfleet.svc.cluster.local:8000`, the `grep -c` command prints `0`, and the count of 40 connections follows the Service, not the 80/20 weights. Istio treats the port as HTTP, so the `tcp` route is ignored. Run `istioctl analyze -n starfleet` too, and read what it reports. Both objects are valid, so it may not name this problem.

## Item 1: name the port tcp

> **Task item 1:** The port of the Service `probe-tcp` is named `tcp`, with the port number `8000` and the container port `8080` unchanged.

Change only the name of the port, with a JSON patch:

```bash
kubectl patch service probe-tcp -n starfleet --type json \
  -p '[{"op":"replace","path":"/spec/ports/0/name","value":"tcp"}]'
```

Wait a few seconds, then check that the proxy has changed its mind:

```bash
kubectl get service probe-tcp -n starfleet -o jsonpath='{.spec.ports[0].name}'
istioctl proxy-config listener deploy/shuttle -n starfleet --port 8000 -o json | grep -c weightedClusters
```

The name prints `tcp`, and the count of `weightedClusters` lines is no longer `0`. This is only half of the fix. The second cause shows up in the next item.

## Item 2: fix the subset labels

> **Task item 2:** The `DestinationRule` `probe-tcp` defines the subsets `v1` and `v2`, each selecting on the pods' `version` label, so that each subset selects its own pods.

Look at the endpoints of the `v2` cluster. Its subset selects `version: canary`, which no pod carries:

```bash
kubectl get destinationrule probe-tcp -n starfleet -o jsonpath='{.spec.subsets[*].labels}'
istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8000|v2|probe-tcp.starfleet.svc.cluster.local"
istioctl analyze -n starfleet
```

The endpoints command lists no endpoint for the `v2` cluster, and `istioctl analyze` can report the subset as selecting no pods with the code `IST0173`. Save this as `destinationrule-probe-tcp.yaml`:

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

Then check that the `v2` cluster has an endpoint:

```bash
istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8000|v2|probe-tcp.starfleet.svc.cluster.local"
```

It should now list the address of the `probe-v2` pod as `HEALTHY`.

## Item 3: keep the VirtualService

> **Task item 3:** There is still exactly one `VirtualService` for `probe-tcp`, and its `tcp` route still matches port `8000` and weighs 80 for `v1` and 20 for `v2`.

The `VirtualService` was correct, so do nothing. Check that it is untouched:

```bash
kubectl get virtualservice probe-tcp -n starfleet -o jsonpath='{.spec.tcp[0].match[0].port} {.spec.tcp[0].route[*].weight}'
```

It should print `8000 80 20`.

## Item 4: the proxy holds the split

> **Task item 4:** The proxy of `shuttle` holds the weighted clusters in its listener for port `8000`, and the cluster `outbound|8000|v2|probe-tcp.starfleet.svc.cluster.local` has at least one healthy endpoint.

Both checks follow from items 1 and 2. The listener check is the one from item 1, and the endpoints check is the one from item 2:

```bash
istioctl proxy-config listener deploy/shuttle -n starfleet --port 8000 -o json | grep -A12 weightedClusters
```

You should see a `weightedClusters` block with the `v1` and `v2` clusters and their weights.

## Item 5: fresh connections split 80/20

> **Task item 5:** The split is real. The grader opens 150 fresh connections. Every connection must get an answer, and between 15 and 45 answers must come from `probe-v2`.

Open 150 fresh connections with the helper:

```bash
astrona res run count-connections.sh -- 150
```

You should see about 120 answers from `probe-v1` and about 30 from `probe-v2`, and the two numbers should add up to 150. Counts change from run to run.

## Item 6: leave the workloads alone

> **Task item 6:** Leave the Deployments, the pod labels, the Service `probe` and the `VirtualService` unchanged, and do not add or remove workloads.

The fix touched only the port name of `probe-tcp` and the labels of one subset. Check that the Service `probe` still has its `http` port:

```bash
kubectl get service probe -n starfleet -o jsonpath='{.spec.ports[0].name}'
```

## Submit

When all items are done, send the lab for grading:

```bash
astrona submit -c sections/section-020/module-03/labs/lab-02
```

## Mistakes That Fail The Grader

- **Only fixing the port (items 2, 4, 5).** Connections picked for `v2` still have no endpoint, so fewer than 150 connections get an answer.
- **Only fixing the subset labels (items 1, 4, 5).** The port is still named `http`, so the proxy ignores the `tcp` route.
- **Changing the weights or rewriting the VirtualService (item 3).** The route was correct. Keep 80 and 20, and the match on port `8000`.
- **Renaming the port of the Service `probe` (item 6).** Only `probe-tcp` is part of the problem.
- **Changing the port number or the container port of `probe-tcp` (item 1).** Only the name changes.
- **Relabelling the pods to match the subset (items 2, 6).** The `DestinationRule` is wrong, not the pods.
