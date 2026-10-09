# Choose Who Flies Through The Gate

Astronaut, so far every ship that signals `httpbin.org` flies through the departure gate. Sometimes only some ships should. This part narrows hop 1 to the ships with one label, shows what that does and does not stop, and ends with an honest account of what the gate costs.

## `sourceLabels` picks the sender

Hop 1 is an ordinary rule in every sidecar, so it can match on ordinary things. One of them is **`sourceLabels`**: the labels of the pod that **sends** the signal. A rule with `sourceLabels: {egress-allowed: "true"}` only fits signals from ships that carry that label. Every other ship skips the rule, and with no other rule for `httpbin.org`, it flies direct.

In your playground, the shuttle has no such label yet:

```sh
kubectl get pods -n starfleet -L egress-allowed
```

```text
NAME                      READY   STATUS    RESTARTS   AGE   EGRESS-ALLOWED
shuttle-7b5db664c-mbjjw   2/2     Running   0          5s
```

The `EGRESS-ALLOWED` column is empty.

<!-- astrona:playground:renew -->

### Only labelled ships use the gate

The four objects from the last parts must be applied. Change hop 1 so it also matches on `sourceLabels`, and keep `gateways: [mesh]` in its `match`. Save this as `virtualservice-httpbin-org-allowed-only.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: httpbin-org-via-egress
  namespace: starfleet
spec:
  hosts:
  - httpbin.org
  gateways:
  - mesh
  - egress-gateway
  tls:
  - match:
    - gateways:
      - mesh
      port: 443
      sniHosts:
      - httpbin.org
      sourceLabels:
        egress-allowed: "true"
    route:
    - destination:
        host: istio-egress.istio-egress.svc.cluster.local
        subset: httpbin-org
        port:
          number: 443
  - match:
    - gateways:
      - egress-gateway
      port: 443
      sniHosts:
      - httpbin.org
    route:
    - destination:
        host: httpbin.org
        port:
          number: 443
```

Apply it:

```sh
kubectl apply -f virtualservice-httpbin-org-allowed-only.yaml
```

Then send a signal from the shuttle, which has no label, and read its flight log and its listener:

```sh
call_external
log_shuttle
istioctl proxy-config listener deploy/shuttle -n starfleet --port 443 | head -3
```

You should see (log line trimmed):

```text
200 0.485071s
  exit=0
"- - -" 0 - - - "-" 901 4875 596 - "-" "-" "-" "-" "98.89.203.252:443" outbound|443||httpbin.org ... httpbin.org -
ADDRESSES   PORT MATCH            DESTINATION
0.0.0.0     443  ALL              PassthroughCluster
0.0.0.0     443  SNI: httpbin.org Cluster: outbound|443||httpbin.org
```

The shuttle flies direct, and its listener for `httpbin.org` now points at the real host, not the gate. Mission control only hands hop 1 to sidecars whose pod carries the label.

### Give the shuttle the label

The label belongs on the pod, so set it in the Deployment's pod template. This is one change, so a short `kubectl patch` is enough. Kubernetes replaces the pod:

```sh
kubectl patch deployment shuttle -n starfleet --type merge \
  -p '{"spec":{"template":{"metadata":{"labels":{"egress-allowed":"true"}}}}}'
kubectl rollout status deployment/shuttle -n starfleet
```

```text
deployment.apps/shuttle patched
...
deployment "shuttle" successfully rolled out
```

Then send a signal again and read both flight logs:

```sh
call_external
log_shuttle
log_gate
```

You should see (log lines trimmed):

```text
200 0.513669s
  exit=0
"- - -" 0 - - - "-" 901 4875 631 - "-" "-" "-" "-" "10.244.0.6:443" outbound|443|httpbin-org|istio-egress.istio-egress.svc.cluster.local ... httpbin.org -
"- - -" 0 - - - "-" 901 4875 629 - "-" "-" "-" "-" "3.225.83.162:443" outbound|443||httpbin.org ... httpbin.org -
```

Now hop 1 goes to the gate's pod, and the gate makes the call to the internet. Same shuttle, same command; only the label changed.

Put the shuttle and the flight plan back the way they were:

```sh
kubectl patch deployment shuttle -n starfleet --type json \
  -p '[{"op":"remove","path":"/spec/template/metadata/labels/egress-allowed"}]'
kubectl apply -f virtualservice-httpbin-org-via-egress.yaml
```

## `tls` rules and `http` rules disagree here

On Istio 1.30.5, how you combine `sourceLabels` with `gateways: [mesh]` depends on the kind of rule. These results were checked on a cluster like your playground:

| Hop 1 rule | With `gateways: [mesh]` | Without `gateways` in the `match` |
| --- | --- | --- |
| `tls` (HTTPS passed through) | works: only labelled ships use the gate | **breaks**: the gate also takes hop 1, sends the signal to itself, and the shuttle gets `000` with `NC` in the gate's log |
| `http` (plain HTTP) | **breaks**: `sourceLabels` is ignored, and every ship uses the gate | works: only labelled ships use the gate |

So for a `tls` hop 1, keep `gateways: [mesh]` next to `sourceLabels`, as you did above. For an `http` hop 1, match on the port and `sourceLabels` only. Whichever you write, prove it the same way: send a signal from a ship **without** the label, and check that its flight log ends at the internet, not at the gate.

## Narrowed is not blocked

Be precise about what `sourceLabels` gave you. It narrows **the route, not the permission**. The shuttle without the label was not stopped: it flew direct and got `200`, with no line in the gate's flight log. On an `ALLOW_ANY` mesh, every ship can still reach the internet without the gate.

Turning the gate into a real control takes three layers together:

| Layer | What does it | What it gives you |
| --- | --- | --- |
| The route | this `VirtualService` (optionally with `sourceLabels`) | which ships fly through the gate |
| The permission | `REGISTRY_ONLY` | nothing off the star chart leaves at all |
| The enforcement | an `AuthorizationPolicy` on the gate, plus a Kubernetes `NetworkPolicy` | which ships the gate serves, and no direct path out of the cluster |

With only the first, you have a convention. With all three, you have egress control.

## What the gate gives, and what it costs

The exam can ask for the reasoning, not just the YAML. Know both sides.

**You gain:**

- **One flight log** for every signal that leaves, with the sender's address, instead of a line in whichever sidecar sent it.
- **One source address** partners can allow, instead of the address of every node.
- **One place** to put policy, monitoring and rate limits on outgoing traffic.
- **A home for client certificates**: the gate can start the TLS connection itself, so only the gate holds the keys.

**You pay:**

- **An extra hop** on every outgoing signal, and its latency.
- **A component on the critical path.** Every signal that leaves depends on the gate. It needs capacity, monitoring and enough replicas, or it becomes your Death Star: huge and important, with one weak spot that takes down every signal leaving the solar system.
- **More configuration per outside host**: four objects instead of one.

For a cluster with a handful of outside hosts and no audit or compliance need, letting each sidecar fly direct is simpler and fine. The gate earns its place when you need the single flight log, the fixed source address, or one home for the certificates.

## Common pitfalls

> [!WARNING]
> - **Reading `sourceLabels` as a permission.** It narrows the route. A ship without the label flies direct and still gets `200`.
> - **Copying the `sourceLabels` match between `tls` and `http` rules.** On Istio 1.30.5 they behave differently with `gateways: [mesh]`. Test with a ship that should **not** use the gate.
> - **Labelling the Deployment instead of the pod.** `sourceLabels` reads the pod's labels. Set them in `spec.template.metadata.labels`.
> - **Believing the gate is enforced.** Without `REGISTRY_ONLY`, an `AuthorizationPolicy` and a `NetworkPolicy`, any ship can still leave directly.
> - **A single gate replica.** Every outgoing signal depends on it. Run more than one.

> *`sourceLabels` decides who flies through the gate, not who may leave. An unlabelled ship still flies direct.*

## Your mission: Send One Ship Through The Departure Gate

You can now build the two-stage route, prove the hop from the gate's flight log, and narrow the route to the ships with one label. Now prove it in a graded mission: route a partner endpoint through the gate for one client only, over plain HTTP, and show that another client still flies direct.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-080-01
```

Then start the mission:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/module-01/labs/lab-01
```

Read the task in [`question.md`](./labs/lab-01/question.md) and solve it on your own first. The mission runs on an older install, so the names differ from your playground: the gate is `istio-egressgateway` in `istio-system`, with the label `istio: egressgateway`, and the clients live in the namespace `egwgw-demo`. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-080/module-01/labs/lab-01
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-014-lab-080-01
astrona start ats-014-playground-080-01
```
