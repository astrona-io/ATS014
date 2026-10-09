# Debug Routing With The Access Log And proxy-config

Sometimes a `VirtualService` sits in the right namespace and still does not behave. Two more checks find the problem. The **access log** of the client's proxy tells you what happened to each request, in a short code. The **proxy's live configuration** tells you whether your rules arrived at all. This part trains both checks and ends with the full checklist to run when a rule does nothing.

A **`VirtualService`** is the Istio object that sets where requests to a host go. A **`DestinationRule`** defines subsets for a host, which are named groups of pods picked by pod labels. The **sidecar proxy** (Envoy) is the proxy container Istio adds to each pod; all traffic in and out of the pod passes through it.

The commands below need the `scout` `DestinationRule` with the subsets `v1`, `v2` and `v3` applied in your playground. They also use the `count_versions` helper, which sends 10 requests from the `shuttle` pod to `scout` and counts which version answered. `$SCOUT` holds `http://scout:9080/reviews`.

## Start from a working VirtualService

These checks are easiest to see against a `VirtualService` that works. This one sends every request to `scout` to v1, using full names.

<!-- astrona:playground:renew -->

Save this as `virtualservice-scout-fqdn.yaml`:

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

Then check the result. Send 10 requests:

```sh
count_versions $SCOUT/0
```

You should see:

```text
  10 scout-v1
```

## Read the access log

Every sidecar proxy writes an access log: one line for every request it handles, in the log of its `istio-proxy` container. That line says what happened to the request. When something went wrong, it says *what* went wrong in a short code called the **response flag**. Reading it is the fastest way to tell the common failures apart.

### Read one access log line

This is a real line from the access log of the `shuttle` proxy, for one request that worked:

```text
[2026-10-08T16:47:14.958Z] "GET /reviews/0 HTTP/1.1" 200 - via_upstream - "-" 0 436 393 392 "-" "curl/8.11.1" "778e16ae-638a-4271-affd-266cde10aa9a" "scout:9080" "10.244.0.11:9080" outbound|9080||scout.starfleet.svc.cluster.local 10.244.0.9:56974 10.96.155.93:9080 10.244.0.9:42666 - default
```

It is long, but only a few fields matter for routing:

```text
"GET /reviews/0 HTTP/1.1"     the request: method and path
200                           the status code the client got back
-                             the response flag. "-" means nothing went wrong
"scout:9080"                  the host the client asked for
"10.244.0.11:9080"            the endpoint the proxy chose (a pod address)
outbound|9080||scout...       the cluster it chose from (no subset here)
```

A **cluster** is Envoy's name for a destination with its list of endpoints (pod addresses). To read the access log yourself, ask the **client's** proxy for its last line:

```sh
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

When something goes wrong, the status code changes, and the `-` after it becomes a flag such as `NR`, `NC` or `UH`.

### The failure signatures

Most broken routing shows one of a few symptoms. Each symptom points at a different part of your setup:

| Symptom | Flag | Means | Look at |
| --- | --- | --- | --- |
| **The wrong version answers, no error** | none | a rule matched that you did not expect | rule order; AND or OR; a catch-all above your rules |
| **`404`** | `NR` | no rule matched, and there is no catch-all | add a catch-all as the last rule |
| **`503`** | `NC` | the route names a subset that has no cluster | subset name spelled wrong; `DestinationRule` missing, in another namespace, or not pushed yet |
| **`503`** | `UH` | the cluster exists but has no pods | subset labels match no pod; pods not running or not ready |

`NC` and `UH` look the same to the client: a bare `503`, with nothing useful in the response or in the application's own logs. Only the flag tells you which row you are in, so always read it before you change anything.

### A mistyped subset name gives 503 NC

Now ask for a subset that does not exist.

Save this as `virtualservice-scout-typo.yaml`:

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

Then check the result. Send one request, read the access log of the `shuttle` proxy, and run `istioctl analyze`, the command that runs Istio's own checks over the objects in a namespace:

```sh
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" $SCOUT/0
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
istioctl analyze -n starfleet
```

You should see this (the log line is shortened):

```text
503
"GET /reviews/0 HTTP/1.1" 503 NC cluster_not_found ...
Error [IST0101] (VirtualService starfleet/scout) Referenced host+subset in destinationrule not found: "scout+v4"
```

`istiod`, Istio's control plane, builds one cluster per subset in the `DestinationRule`. There is no `v4` subset, so there is no `v4` cluster. The route points at nothing, and the request never leaves the `shuttle` pod. The flag says `NC`, "no cluster".

If the log line is an older one, the proxy has not written the new line yet. Run the `kubectl logs` line again.

The same `NC` appears for a short time if you apply a `VirtualService` *before* the `DestinationRule` it uses. The safe order is called "make before break": apply the `DestinationRule` first, wait a moment, then apply the `VirtualService` that uses it.

Put the working `VirtualService` back:

```sh
kubectl apply -f virtualservice-scout-fqdn.yaml
```

## Check the configuration the proxy holds

Kubernetes accepting an object and the proxy acting on it are two different facts. When they differ, the object looks perfect and the behaviour is wrong. Two commands close the gap. `istioctl proxy-status` shows whether each proxy is connected to `istiod`, and `istioctl proxy-config` shows the configuration one proxy holds.

### Is every proxy connected?

List every proxy that `istiod` sends configuration to:

```sh
istioctl proxy-status
```

You should see one row per proxy (shortened to two rows):

```text
NAME                                     CLUSTER        ISTIOD                     VERSION     SUBSCRIBED TYPES
scout-v1-85bf65868-c4lcg.starfleet       Kubernetes     istiod-995fd9df6-tfqth     1.30.5      4 (CDS,LDS,EDS,RDS)
shuttle-7b5db664c-bn9dl.starfleet        Kubernetes     istiod-995fd9df6-tfqth     1.30.5      4 (CDS,LDS,EDS,RDS)
```

Every pod with a sidecar proxy should be in this list, connected to an `istiod` and running the same version. `SUBSCRIBED TYPES` shows the four kinds of xDS configuration it receives from `istiod`. xDS is the protocol `istiod` uses to push configuration to proxies while they run. The four types are LDS (Listener Discovery Service), RDS (Route Discovery Service), CDS (Cluster Discovery Service) and EDS (Endpoint Discovery Service). A pod that is missing from the list gets no configuration at all.

### See where the route points

With the full-name `VirtualService` applied, print the cluster that the `shuttle` route uses, and the clusters the proxy holds:

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

The **route** picks a cluster, and the **cluster** holds the pods. This is the same split as between `VirtualService` and `DestinationRule`. Here the route uses the v1 cluster, so the `VirtualService` has reached the proxy. If a `VirtualService` exists in `kubectl` but its cluster never shows up here, the problem is between `istiod` and this proxy, not in your YAML.

## Your debugging checklist

When a `VirtualService` does nothing, run these checks in order. The first one that shows a problem is your answer.

| Step | Command | It tells you |
| --- | --- | --- |
| 1 | `kubectl get virtualservice,destinationrule -A` | whether the objects exist, and in which namespace |
| 2 | `istioctl analyze -A` | whether the objects agree with each other and point at real Services |
| 3 | `kubectl logs ... -c istio-proxy` on the **client** | the response flag: `NR`, `NC`, `UH` or none |
| 4 | `istioctl proxy-status` | whether the client's proxy is connected to `istiod` |
| 5 | `istioctl proxy-config routes` on the **client** | whether your rules arrived, and which cluster they point at |

## What you know now

The access log of the client's proxy gives one line per request, and its response flag names the failure. `NR` means no route, `NC` means the route names a cluster that does not exist, and `UH` means the cluster has no endpoints. `istioctl proxy-status` shows whether a proxy is connected, and `istioctl proxy-config routes` and `clusters` show whether your rules reached it. The open question is what else a matched rule can do besides choosing a destination.

## Common pitfalls

> [!WARNING]
> - **Reading only the status code.** `NC` and `UH` are both a bare `503`. Read the flag.
> - **Reading the server's access log.** The client's proxy makes the routing choice. Read the client's log first.
> - **A subset no `DestinationRule` defines.** `503 NC`, and `analyze` reports `IST0101`.
> - **Trusting a clean `analyze`.** It checks objects against each other. It does not prove your rules are in a sensible order, or that requests take the path you expect.

## Your mission: Fix A VirtualService That Does Not Apply

You can now find a `VirtualService` in the wrong namespace, read an access log line, and check the configuration a proxy holds. The graded lab gives you a `VirtualService` that does nothing, with more than one fault in it, and asks you to repair it.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-010-01
```

Then start the lab:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-01/labs/lab-04
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-010/module-01/labs/lab-04
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-014-lab-010-01-04
astrona start ats-014-playground-010-01
```
