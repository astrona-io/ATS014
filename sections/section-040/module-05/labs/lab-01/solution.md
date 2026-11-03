# Solution Walkthrough

The walkthrough follows the task from top to bottom, and each section ends with a check. All four settings go into one `DestinationRule` for the host `probe`. They sit in its `connectionPool` block: the connect timeout, the maximum connection duration and TCP keepalive under `tcp`, and the idle timeout under `http`.

---

## Start: Look At The Starting State

The task says that no `DestinationRule` and no `VirtualService` exists. Check that, and read the connect timeout the proxy of `shuttle` holds today:

```sh
kubectl -n starfleet get destinationrule,virtualservice
istioctl proxy-config cluster deploy/shuttle -n starfleet \
  --fqdn probe.starfleet.svc.cluster.local --port 8000 -o json \
  | grep -E '"connectTimeout"|"idleTimeout"|"maxConnectionDuration"|"keepalive'
```

`kubectl` reports that no resources were found. The proxy shows the mesh default connect timeout, `10s`, and the default idle timeout. It shows no maximum connection duration and no keepalive lines.

---

## Task Item 1: Create The DestinationRule

> **Task item 1:** Create one `DestinationRule` named `probe` in the namespace `starfleet` for the host `probe`, with the connect timeout `2s`, the HTTP idle timeout `90s`, the maximum connection duration `10m`, and TCP keepalive with time `60s`, interval `10s` and `4` probes.

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
    connectionPool:
      tcp:
        connectTimeout: 2s
        maxConnectionDuration: 10m
        tcpKeepalive:
          time: 60s
          interval: 10s
          probes: 4
      http:
        idleTimeout: 90s
```

Apply it:

```sh
kubectl apply -f destinationrule-probe.yaml
```

Check that Kubernetes stored the values you wrote:

```sh
kubectl -n starfleet get destinationrule probe -o jsonpath='{.spec.trafficPolicy.connectionPool}{"\n"}'
```

The command prints the `http` and `tcp` blocks as JSON, with the same values as the file.

---

## Task Item 2: Read The Values From The Proxy

> **Task item 2:** Show from the proxy of `shuttle` that its cluster for `probe.starfleet.svc.cluster.local` on port `8000` holds all of these values.

`istiod` needs a few seconds to send the new cluster to the proxy. Then read it back:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet \
  --fqdn probe.starfleet.svc.cluster.local --port 8000 -o json \
  | grep -E '"connectTimeout"|"idleTimeout"|"maxConnectionDuration"|"keepalive'
```

The proxy writes the values in its own form:

- `connectTimeout` is `2s`.
- `idleTimeout` is `90s`.
- `maxConnectionDuration` is `600s`, which is `10m`.
- `keepaliveProbes` is `4`, `keepaliveTime` is `60` and `keepaliveInterval` is `10`.

If a line is missing, wait a few seconds and run the command again. If it stays missing, check that the field is in the right block.

---

## Task Item 3: Prove That Requests Still Work

> **Task item 3:** Show that 10 requests from `shuttle` to `http://probe:8000/hostname` all return status code `200`.

Send ten requests and print the status code of each:

```sh
for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} " http://probe:8000/hostname
done; echo
```

Every code is `200`. The connection settings change how connections open, idle and close, not where requests go.

---

## Submit

```sh
astrona submit -c sections/section-040/module-05/labs/lab-01
```

## Mistakes That Fail The Grader

- **Item 1: `idleTimeout` under `tcp`.** It belongs under `http`. Istio rejects the object or the proxy shows no idle timeout of `90s`.
- **Item 1: a second `DestinationRule` or a `VirtualService`.** The grader expects exactly one `DestinationRule` and no `VirtualService`.
- **Item 1: `outlierDetection` or subsets in the object.** The task is only about the connection pool.
- **Item 1: wrong values.** `10m` becomes `600s` in the proxy, so `maxConnectionDuration: 10s` fails item 2.
- **Item 2: reading too early.** The proxy needs a few seconds to receive the cluster. The grader waits up to a minute.
- **Item 3: changing Deployments or the Service.** The grader checks that three Deployments run and that the Service selector is unchanged.
