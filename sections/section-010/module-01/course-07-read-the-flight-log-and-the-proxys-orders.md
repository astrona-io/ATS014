# Read The Flight Log And The Proxy's Orders

Astronaut, when a flight plan is on the right planet and still does not behave, two more checks find the problem. The **flight log** tells you what happened to each signal, in a short code. The **proxy's own orders** tell you whether your flight plan arrived at all. This part trains both, and ends with the full checklist to run when a rule does nothing.

The commands below need the `scout` `DestinationRule` with the subsets `v1`, `v2` and `v3` applied in your playground, and the `count_versions` helper pasted into your terminal.

<!-- astrona:playground:renew -->

## Start from a working flight plan

These checks are easiest to see against a flight plan that works. Send every scout signal to v1, using full names. Save this as `virtualservice-scout-fqdn.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: scout
  namespace: starfleet
spec:
  hosts:
  - scout.starfleet.svc.cluster.local
  http:
  - route:
    - destination:
        host: scout.starfleet.svc.cluster.local
        subset: v1
```

Apply it:

```sh
kubectl apply -f virtualservice-scout-fqdn.yaml
```

Then send 10 signals:

```sh
count_versions $SCOUT/0
```

You should see:

```text
  10 scout-v1
```

## Read the flight log

Every communications officer keeps a flight log: one line for every signal it handles. That line says what happened to the signal, and when something went wrong, it says *what* went wrong in a short code called the **response flag**. Reading it is the fastest way to tell the common failures apart.

### Read one flight log line

This is a real line from the shuttle's flight log, for one signal that worked:

```text
[2026-10-08T16:47:14.958Z] "GET /reviews/0 HTTP/1.1" 200 - via_upstream - "-" 0 436 393 392 "-" "curl/8.11.1" "778e16ae-638a-4271-affd-266cde10aa9a" "scout:9080" "10.244.0.11:9080" outbound|9080||scout.starfleet.svc.cluster.local 10.244.0.9:56974 10.96.155.93:9080 10.244.0.9:42666 - default
```

It is long, but only a few parts matter for routing:

```text
"GET /reviews/0 HTTP/1.1"     the signal: method and path
200                           the status code the sender got back
-                             the response flag. "-" means nothing went wrong
"scout:9080"                  the beacon the sender asked for
"10.244.0.11:9080"            the ship the proxy chose (a pod address)
outbound|9080||scout...       the cluster it chose from (no subset here)
```

To read the flight log yourself, ask the **sender's** proxy for its last line:

```sh
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

When something goes wrong, the status code changes, and the `-` after it becomes a flag such as `NR`, `NC` or `UH`.

### The failure signatures

Most broken routing shows one of a few symptoms, and each points at a different part of your setup:

| Symptom | Flag | Means | Look at |
| --- | --- | --- | --- |
| **The wrong version answers, no error** | none | a rule fitted that you did not expect | rule order; AND or OR; a catch-all above your rules |
| **`404`** | `NR` | no rule fitted, and there is no catch-all | add a catch-all as the last rule |
| **`503`** | `NC` | the route names a subset that has no cluster | subset name spelled wrong; `DestinationRule` missing, in another namespace, or not pushed yet |
| **`503`** | `UH` | the cluster exists but has no pods | subset labels match no pod; pods not running or not ready |

`NC` and `UH` look the same to the sender: a bare `503`, with nothing useful in the response or in the app's own logs. Only the flag tells you which row you are in, so always read it before you change anything.

### A typo in the subset name (`503 NC`)

Ask for a ship class that does not exist. Save this as `virtualservice-scout-typo.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: scout
  namespace: starfleet
spec:
  hosts:
  - scout
  http:
  - route:
    - destination:
        host: scout
        subset: v4
```

Apply it:

```sh
kubectl apply -f virtualservice-scout-typo.yaml
```

Then send one signal, read the shuttle's flight log, and run `istioctl analyze`:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" $SCOUT/0
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
istioctl analyze -n starfleet
```

You should see (log line trimmed):

```text
503
"GET /reviews/0 HTTP/1.1" 503 NC cluster_not_found ...
Error [IST0101] (VirtualService starfleet/scout) Referenced host+subset in destinationrule not found: "scout+v4"
```

Mission control builds one cluster per subset in the `DestinationRule`. There is no `v4` subset, so there is no `v4` cluster. The route points at nothing, and the signal never leaves the shuttle. The flag says `NC`, "no cluster".

If the log line is an older one, the flight log has not been written yet. Run the `kubectl logs` line again.

The same `NC` appears for a short time if you apply a `VirtualService` *before* the `DestinationRule` it uses. The safe order is called "make before break": apply the `DestinationRule` first, wait a moment, then apply the `VirtualService` that uses it.

Put the working flight plan back:

```sh
kubectl apply -f virtualservice-scout-fqdn.yaml
```

## Check the orders the proxy holds

Istio accepting an object and the communications officer acting on it are two different facts. When they disagree, the object looks perfect and the behaviour is wrong. Two commands close the gap: `istioctl proxy-status` shows whether each proxy is connected to mission control, and `istioctl proxy-config` shows the orders one proxy holds.

### Is every proxy connected?

List every proxy that mission control is talking to:

```sh
istioctl proxy-status
```

You should see one row per proxy (trimmed to two rows):

```text
NAME                                     CLUSTER        ISTIOD                     VERSION     SUBSCRIBED TYPES
scout-v1-85bf65868-c4lcg.starfleet       Kubernetes     istiod-995fd9df6-tfqth     1.30.5      4 (CDS,LDS,EDS,RDS)
shuttle-7b5db664c-bn9dl.starfleet        Kubernetes     istiod-995fd9df6-tfqth     1.30.5      4 (CDS,LDS,EDS,RDS)
```

Every ship with a communications officer should be in this list, connected to an `istiod` and running the same version. `SUBSCRIBED TYPES` shows the four kinds of orders it receives from mission control: LDS (Listener Discovery Service), RDS (Route Discovery Service), CDS (Cluster Discovery Service) and EDS (Endpoint Discovery Service). A ship that is missing from the list gets no orders at all.

### See where the route points

With the full-name flight plan applied, print the cluster the shuttle's route uses, and the clusters it holds:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 9080 -o json | grep '"cluster".*scout'
istioctl proxy-config clusters deploy/shuttle -n starfleet | grep scout
```

You should see something like:

```text
"cluster": "outbound|9080|v1|scout.starfleet.svc.cluster.local"
scout.starfleet.svc.cluster.local   9080   -    outbound   EDS   scout.starfleet
scout.starfleet.svc.cluster.local   9080   v1   outbound   EDS   scout.starfleet
scout.starfleet.svc.cluster.local   9080   v2   outbound   EDS   scout.starfleet
scout.starfleet.svc.cluster.local   9080   v3   outbound   EDS   scout.starfleet
```

The **route** picks a cluster, and the **cluster** holds the pods: the same split as `VirtualService` and `DestinationRule`. Here the route uses the v1 cluster, so the flight plan has arrived. If a `VirtualService` exists in `kubectl` but its cluster never shows up here, the break is between mission control and this proxy, not in your YAML.

## Your debugging checklist

When a flight plan does nothing, run these in order. The first one that shows a problem is your answer.

| Step | Command | It tells you |
| --- | --- | --- |
| 1 | `kubectl get virtualservice,destinationrule -A` | whether the objects exist, and on which planet |
| 2 | `istioctl analyze -A` | whether the objects agree with each other and point at real Services |
| 3 | `kubectl logs ... -c istio-proxy` on the **sender** | the response flag: `NR`, `NC`, `UH` or none |
| 4 | `istioctl proxy-status` | whether the sender's proxy is connected to mission control |
| 5 | `istioctl proxy-config routes` on the **sender** | whether your rules arrived, and which cluster they point at |

## Common pitfalls

> [!WARNING]
> - **Reading only the status code.** `NC` and `UH` are both a bare `503`. Read the flag.
> - **Reading the receiver's flight log.** The routing choice is made by the sender. Read the sender's log first.
> - **A subset no `DestinationRule` defines.** `503 NC`, and `analyze` reports `IST0101`.
> - **Trusting a clean `analyze`.** It checks objects against each other. It does not prove your rules are in a sensible order, or that signals take the path you expect.

> *When a rule does nothing, check the planet, then the flight log, then the orders the proxy holds. The first check that shows a problem is your answer.*

## Your mission: Find Out Why The Flight Plan Does Nothing

You can now find a flight plan on the wrong planet, read a flight log line, and check the orders a proxy holds. Now prove it in a graded mission: a flight plan that does nothing is waiting for you, with more than one thing wrong in it.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-010-01
```

Then start the mission:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-01/labs/lab-04
```

Read the task in [`question.md`](./labs/lab-04/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-010/module-01/labs/lab-04
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-014-lab-010-01-04
astrona start ats-014-playground-010-01
```
