# Where The `DestinationRule` Attaches

The signal now leaves sealed. In this part you prove which proxy put the lock on, astronaut, by reading the orders of both proxies. On the way you find that every sidecar got the TLS settings too, and you keep them on the gate alone.

The commands below need the five objects of the chain applied in your playground: the `ServiceEntry` `httpbin-org`, the `Gateway` `departure-gate`, the `DestinationRule` objects `departure-gate` and `httpbin-org-tls`, and the `VirtualService` `httpbin-org-via-gate` with stage 2 on port `443`.

## Two facts, two proofs

The answer to the shuttle looks the same whether the gate carried the signal or not, and whether the gate sealed it or not. So there are two separate facts to prove, each with its own evidence:

| Fact | Evidence |
| --- | --- |
| The gate was in the path | a new line in **the gate's** flight log, with upstream port `443` |
| The gate put the lock on | the gate's **cluster** for `httpbin.org` has TLS settings |

A **cluster** is the proxy's name for one destination and how to connect to it. When a cluster uses TLS, its configuration holds a **`transportSocket`**: the TLS equipment for that connection. You can count it in each proxy.

<!-- astrona:playground:renew -->

### Count the TLS equipment in both proxies

Ask both proxies about their cluster for `httpbin.org`, and count the `transportSocket` entries:

```sh
echo -n "gate: "
istioctl proxy-config cluster deploy/istio-egress -n istio-egress --fqdn httpbin.org -o json | grep -c transportSocket
echo -n "shuttle: "
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn httpbin.org -o json | grep -c transportSocket
```

You should see:

```text
gate: 1
shuttle: 1
```

The gate has the TLS equipment, as expected. But the shuttle has it too. Ask the shuttle which `DestinationRule` built its clusters:

```sh
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn httpbin.org
```

```text
SERVICE FQDN     PORT     SUBSET     DIRECTION     TYPE           DESTINATION RULE
httpbin.org      80       -          outbound      STRICT_DNS     httpbin-org-tls.starfleet
httpbin.org      443      -          outbound      STRICT_DNS     httpbin-org-tls.starfleet
```

The shuttle's clusters were built from `httpbin-org-tls` as well. Nothing breaks: stage 1 sends the shuttle's signals to the gate, so the shuttle never uses this cluster. But the TLS settings sit in every sidecar, and your proof is gone.

## Keep the lock on the gate

A `DestinationRule` is visible to the **whole mesh** by default. Mission control hands it to every proxy that might call the host: the gate, and every sidecar. The field **`exportTo`** limits that. It lists the namespaces whose proxies may use the rule. The gate runs in the namespace `istio-egress`, so that is the only one to list.

### Scope the rule to the gate's namespace

Save this as `destinationrule-httpbin-org-tls.yaml`, replacing the earlier version:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: httpbin-org-tls
  namespace: starfleet
spec:
  host: httpbin.org
  exportTo:
  - istio-egress
  trafficPolicy:
    portLevelSettings:
    - port:
        number: 443
      tls:
        mode: SIMPLE
        sni: httpbin.org
```

Apply it:

```sh
kubectl apply -f destinationrule-httpbin-org-tls.yaml
```

Then count again, and send a signal to check the chain still works:

```sh
echo -n "gate: "
istioctl proxy-config cluster deploy/istio-egress -n istio-egress --fqdn httpbin.org -o json | grep -c transportSocket
echo -n "shuttle: "
istioctl proxy-config cluster deploy/shuttle -n starfleet --fqdn httpbin.org -o json | grep -c transportSocket
call_httpbin
```

You should see:

```text
gate: 1
shuttle: 0
  "url": "https://httpbin.org/get"
200
```

One and zero. The TLS equipment is on the gate and nowhere else, and the signal still arrives over `https://`. That pair of numbers is the shortest proof that the gate puts the lock on.

## What the sidecar really does

The shuttle's sidecar has a much simpler job. Its route for port `80` sends the signal to the gate, and nothing more.

### Read the shuttle's route

List the clusters that the shuttle's route table for port `80` can send to:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 80 -o json | grep '"cluster"'
```

You should see:

```text
                            "cluster": "outbound|80|httpbin-org|istio-egress.istio-egress.svc.cluster.local",
                            "cluster": "outbound|80||istio-egress.istio-egress.svc.cluster.local",
                            "cluster": "PassthroughCluster",
```

The first line is stage 1: port `80`, the gate's Service, the subset `httpbin-org`. To the shuttle's communications officer, this is an ordinary signal to a service inside the solar system. It has no idea TLS is involved anywhere.

## The lock on the wrong host

Now the most common mistake: putting the TLS settings on the gate's own Service instead of on `httpbin.org`. That `DestinationRule` is about calls **to the gate**, so the proxy that follows it is the shuttle's sidecar.

### Put the TLS settings on the gate's Service

Save this as `destinationrule-departure-gate-wrong-tls.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: departure-gate
  namespace: starfleet
spec:
  host: istio-egress.istio-egress.svc.cluster.local
  subsets:
  - name: httpbin-org
  trafficPolicy:
    portLevelSettings:
    - port:
        number: 80
      tls:
        mode: SIMPLE
        sni: httpbin.org
```

Apply it:

```sh
kubectl apply -f destinationrule-departure-gate-wrong-tls.yaml
```

Then send a signal and read the shuttle's flight log:

```sh
call_httpbin
log_shuttle
```

You should see (log line trimmed):

```text
503
"GET /get HTTP/1.1" 503 URX,UF upstream_reset_before_response_started{remote_connection_failure|TLS_error:|268435703:SSL_routines:OPENSSL_internal:WRONG_VERSION_NUMBER:TLS_error_end} ... "httpbin.org" "10.244.0.6:80" outbound|80|httpbin-org|istio-egress.istio-egress.svc.cluster.local ...
```

The shuttle's sidecar followed the rule and tried a TLS handshake with the gate's port `80`. The gate does not expect that there, so the handshake fails: `UF` means the connection to the next hop failed, and `WRONG_VERSION_NUMBER` is the TLS error. The TLS settings went to the proxy that calls the host the rule names, which is exactly the rule you met above, now working against you.

Put the right docking instructions back:

```sh
kubectl apply -f destinationrule-departure-gate.yaml
```

## A short repair order

When the chain does not work, check these in order. Each step points at one object:

1. **Does the gate's flight log show the signal at all?** No: the problem is stage 1 or the `Gateway`. Check that `mesh` is in the top-level `gateways`, and that the `Gateway` lists the outside host.
2. **Does the gate's line show upstream port `443`?** No, port `80`: stage 2 routes to the wrong port.
3. **Does the gate's cluster for the outside host have a `transportSocket`?** No: the TLS `DestinationRule` is missing, names the wrong host, or is exported away from `istio-egress`.
4. **Does the outside host report `https://`?** That is the end-to-end proof.

## Common pitfalls

> [!WARNING]
> - **The TLS `DestinationRule` on the gate's own Service.** The sidecar follows it and tries TLS with the gate: `503 URX,UF` with `WRONG_VERSION_NUMBER`. The rule names the outside host.
> - **No `exportTo`.** Every sidecar also gets the TLS settings for the host. Nothing breaks, but the TLS equipment is no longer on the gate alone, and your proof is gone.
> - **`exportTo` without the gate's namespace.** Then the gate itself does not get the rule. It sends the signal to port `443` unsealed, and `httpbin.org` answers `400 The plain HTTP request was sent to HTTPS port`.
> - **Looking for TLS in the sidecar.** With the chain in place, the sidecar only sends plain HTTP to the gate. The gate's cluster holds the lock.

> *A `transportSocket` on the gate and none on the sidecar: that one comparison proves the gate puts the lock on.*

## Your mission: Lock The Signal At The Departure Gate

You can now build the five objects, put the lock on at the gate, and prove it from both proxies. Now prove it in a graded mission: a partner server that only speaks TLS, a ship that only sends plain `http://`, and a departure gate in between that has to seal every signal.

The mission runs in its own training solar system, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-080-02
```

Then start the mission:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-080/module-02/labs/lab-01
```

Read the task in [`question.md`](./labs/lab-01/question.md) and solve it on your own first. The mission uses its own small app and the `demo` install of Istio, so the names differ from your playground: the gate is `istio-egressgateway` in `istio-system`, with the pod label `istio: egressgateway`. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-080/module-02/labs/lab-01
```

When the mission is done, remove it and wake your playground up again:

```sh
astrona destroy ats-014-lab-080-02
astrona start ats-014-playground-080-02
```
