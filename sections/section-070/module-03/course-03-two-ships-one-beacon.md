# Two Ships, One Beacon

Astronaut, one freighter is a start, but real services run on more than one machine. Because the `ServiceEntry` finds its machines by label, adding a machine means adding one object, with no change to the `ServiceEntry`. The same link is also the easiest one to break without any warning.

The commands below need three objects in your playground: the `freighter-vm-1` `WorkloadEntry` with the label `app: freighter`, the `freighter` `ServiceEntry` (`MESH_INTERNAL`, `STATIC`, selecting `app: freighter`), and the `freighter` `DestinationRule` that switches the secret handshake off for the stand-in.

## One label, many machines

The `workloadSelector` works like a beacon's call sign: every `WorkloadEntry` with the matching label answers it. A second entry with the same label becomes a second endpoint behind the same name.

<!-- astrona:playground:renew -->

### Add the second freighter

Get the address of the second freighter:

```sh
FREIGHTER_VM_2=$(kubectl get pod -n starfleet -l ship=freighter-vm-2 -o jsonpath='{.items[0].status.podIP}')
echo $FREIGHTER_VM_2
```

```text
10.244.0.10
```

Replace `<FREIGHTER_VM_2>` with that address. Save this as `workloadentry-freighter-vm-2.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: WorkloadEntry
metadata:
  name: freighter-vm-2
  namespace: starfleet
spec:
  address: <FREIGHTER_VM_2>
  labels:
    app: freighter
  serviceAccount: freighter
```

Apply it:

```sh
kubectl apply -f workloadentry-freighter-vm-2.yaml
```

Then check the result:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8080||freighter.starfleet.mesh"
```

You should see:

```text
ENDPOINT             STATUS      OUTLIER CHECK     CLUSTER
10.244.0.10:8080     HEALTHY     OK                outbound|8080||freighter.starfleet.mesh
10.244.0.9:8080      HEALTHY     OK                outbound|8080||freighter.starfleet.mesh
```

Two endpoints behind one name. You did not touch the `ServiceEntry`: its selector found the new entry by its label.

### Watch the beacon share the signals

Send 10 signals to the name and count which freighter answered each one:

```sh
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s http://freighter.starfleet.mesh:8080/hostname | grep -o 'freighter-vm-[0-9]'
done | sort | uniq -c
```

You should see something like:

```text
   2 freighter-vm-1
   8 freighter-vm-2
```

Both freighters take signals. The shuttle's proxy spreads them across the two endpoints, exactly as it would across two pods. Your numbers will be different each time.

## When the selector matches nothing

The link between the `ServiceEntry` and its entries is only a label. If the two sides do not agree, nothing complains: not `kubectl`, not Istio, not `istioctl analyze`. The name stays on the star chart with no ship behind it.

### Break the selector with one letter

Swap two letters in the selector's label. Save this as `serviceentry-freighter-typo.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: freighter
  namespace: starfleet
spec:
  hosts:
  - freighter.starfleet.mesh
  location: MESH_INTERNAL
  resolution: STATIC
  ports:
  - number: 8080
    name: http
    protocol: HTTP
  workloadSelector:
    labels:
      app: frieghter
```

Apply it:

```sh
kubectl apply -f serviceentry-freighter-typo.yaml
```

Then check the endpoints, send a signal, read the flight log and run `istioctl analyze`:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8080||freighter.starfleet.mesh"
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://freighter.starfleet.mesh:8080/hostname
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
istioctl analyze -n starfleet
```

You should see (log line trimmed):

```text
ENDPOINT     STATUS     OUTLIER CHECK     CLUSTER
503
"GET /hostname HTTP/1.1" 503 UH no_healthy_upstream ... "-" outbound|8080||freighter.starfleet.mesh ...
✔ No validation issues found when analyzing namespace: starfleet.
```

The endpoint list is empty. The signal gets `503` with the flag **`UH`** (no healthy upstream): the cluster exists, but no ship stands behind it. The address field in the log is `"-"`, because there was no ship to pick. And `istioctl analyze` finds nothing wrong, because a selector that matches nothing is valid.

Put the right selector back:

```sh
kubectl apply -f serviceentry-freighter.yaml
```

## Two more facts about the selector

The `workloadSelector` also picks **pods** with matching labels in the same namespace, not only `WorkloadEntry` objects. That is useful while you move a service from machines into Kubernetes: old machines and new pods can answer the same name. It is also why the freighter pods in your playground carry a different label (`ship: ...`) from their entries (`app: freighter`).

A `ServiceEntry` takes its addresses either from a `workloadSelector` or from a list of `endpoints`, never both. Istio rejects an object with both: `only one of WorkloadSelector or Endpoints can be set`.

> [!TIP]
> When a name from a `ServiceEntry` answers `503 UH`, list its endpoints with `istioctl proxy-config endpoints` first. An empty list means the selector and the entries' labels do not match.

## Common pitfalls

> [!WARNING]
> - **A selector label that no entry carries.** Zero endpoints, `503 UH`, and `istioctl analyze` stays quiet.
> - **One entry with a different label.** Only some of the machines answer. Count the endpoints, not just the status codes.
> - **Writing a new `ServiceEntry` for the second machine.** A second `WorkloadEntry` with the same labels joins the existing one.
> - **Giving the pods the same label as the entries by accident.** The selector picks the pods too.
> - **Setting `endpoints` and `workloadSelector` together.** Istio rejects the object.

## Your mission: Bring The Lost Freighters Back

You can now put several machines behind one name and spot a selector that matches nothing. Now prove it in a graded mission: a freighter beacon is broken in more than one place, and you have to bring both freighters back, as members of the fleet.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-070-03
```

Then start the mission:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-070/module-03/labs/lab-02
```

Read the task in [`question.md`](./labs/lab-02/question.md) and solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-070/module-03/labs/lab-02
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-014-lab-070-03-02
astrona start ats-014-playground-070-03
```
