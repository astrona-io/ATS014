# Set A Load Balancer Per Port

A Service can expose several ports, and the traffic on each port can behave very differently. One port may serve a fast API, while another serves large file downloads. A single load balancer for the whole host does not fit both. This part shows how to give one port its own policy, which port number to use, and how to choose the right load balancer from the words of a task.

A `DestinationRule` is the Istio object that holds policies for traffic to one host. Its `trafficPolicy` can sit at three levels: the whole host, one subset (a named group of pods chosen by labels), and one port. The **sidecar proxy** (the Envoy proxy that Istio adds to each pod) of the sending pod uses the most specific level that exists: port beats subset, and subset beats host.

## Port-level settings

The port level lives in the `portLevelSettings` field of a `trafficPolicy`. It takes a list. Each entry names a port with `port.number` and carries its own policy fields, such as `loadBalancer`.

The port number is the **Service** port, the port that clients call. It is not the container port behind it. The `probe` Service listens on port `8000` and sends traffic to container port `8080`, so a port-level policy for `probe` names `8000`.

<!-- astrona:playground:renew -->

### A policy for one port

Give the host `RANDOM`, but give port `8000` the `LEAST_REQUEST` algorithm, which sends each request to the less busy of two randomly picked pods. Save this as `destinationrule-probe-port.yaml`:

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
      simple: RANDOM
    portLevelSettings:
    - port:
        number: 8000
      loadBalancer:
        simple: LEAST_REQUEST
```

Apply it:

```sh
kubectl apply -f destinationrule-probe-port.yaml
```

Envoy stores the endpoints of one destination as a **cluster**, named after the port and host, and it stores the algorithm as the cluster field `lbPolicy`. Read the policy for the probe's port from the `shuttle` pod's proxy:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn probe.starfleet.svc.cluster.local -o json \
  | grep -E '"name": "outbound|"lbPolicy"'
```

```text
        "name": "outbound|8000||probe.starfleet.svc.cluster.local",
        "lbPolicy": "LEAST_REQUEST",
```

The cluster for port `8000` uses `LEAST_REQUEST`, although the host level says `RANDOM`. The port-level setting is the most specific, so it wins.

### Clean up

Remove the `VirtualService` and the `DestinationRule` for `probe`, so the probe is back to Istio's default load balancer:

```sh
kubectl delete virtualservice probe -n starfleet
kubectl delete destinationrule probe -n starfleet
```

If you have no `VirtualService` named `probe`, the first command prints a `NotFound` error, and you can ignore it.

## Choosing the right form

With the port level in place, you know every place a load balancer can live. The last skill is to pick the right one. Exam questions often describe a need instead of naming a field:

| The task says | Use |
| --- | --- |
| "spread evenly", "balance load" | `simple: ROUND_ROBIN` |
| "requests have very different costs", "avoid overloading a busy pod" | `simple: LEAST_REQUEST` |
| "the same user must reach the same instance", "sticky sessions" | `consistentHash` on a header or cookie |
| "session state is held in memory" | `consistentHash`, and say that it is best effort, not a guarantee |
| "do not load balance", "connect to the original address" | `simple: PASSTHROUGH` |
| "clients are browsers with no identifying header" | `consistentHash.httpCookie` with a `ttl`, so the proxy creates the cookie |
| "one port of the Service behaves differently" | `portLevelSettings` with the Service port number |

You now know how to set a policy for one port, that it names the Service port, and that it beats both the subset and the host level. You can also map the words of a task to the right `loadBalancer` form.

## Common pitfalls

> [!WARNING]
> - **Naming the container port in `portLevelSettings`.** It takes the Service port. For `probe`, that is `8000`, not `8080`.
> - **Expecting the host-level `loadBalancer` to win.** A port-level policy beats both the subset and the host level for that port.
> - **Checking only the YAML.** The cluster dump shows the policy each port really got.

## Your mission: Issue A Sticky Cookie On One Port Lab

You can now put a load balancer on one port and pick the right form for a task. The mission asks you to keep browsers, which send no identifying header, each on one pod: the proxy must create a session cookie, and the policy must sit at port level.

The lab runs on its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-030-01
```

Then start the lab. The task is on the next page:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-030/module-01/labs/lab-02
```

Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-030/module-01/labs/lab-02
```

When you are finished, remove the lab and start your playground again:

```sh
astrona destroy ats-014-lab-030-02
astrona start ats-014-playground-030-01
```
