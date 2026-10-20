# Solution Walkthrough

You need two objects. The mesh already refuses unknown hosts, so the task is to add one endpoint to the service registry precisely, and then to prove that the new entry brings the features of Istio with it. The service registry is the list of hosts that `istiod`, the Istio control plane, knows about. A `ServiceEntry` adds a host that lives outside the mesh to that list, and a `VirtualService` sets how requests to a host are routed. Items 1 to 6 write the `ServiceEntry`, and item 7 writes the `VirtualService`. Items 8 to 13 prove the result.

---

## Start: Confirm The Starting State

The task says that the mesh refuses unknown hosts, and that two pods in `outside-mesh` stand in for external endpoints. Check the mesh policy, read the two addresses, and call both endpoints from `tester`:

```sh
kubectl -n istio-system get cm istio -o jsonpath='{.data.mesh}' | grep -A2 outboundTrafficPolicy
PARTNER=$(cat /tmp/partner-ip)
FORBIDDEN=$(cat /tmp/forbidden-ip)
echo "partner:   $PARTNER"
echo "forbidden: $FORBIDDEN"
for ip in $PARTNER $FORBIDDEN; do
  printf '%-16s -> ' "$ip"
  kubectl -n egress-demo exec deploy/tester -- \
    curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 "http://$ip:8080/get"
done
```

```text
outboundTrafficPolicy:
  mode: REGISTRY_ONLY
rootNamespace: istio-system
partner:   10.244.0.8
forbidden: 10.244.0.9
10.244.0.8       -> 000
command terminated with exit code 56
10.244.0.9       -> 000
command terminated with exit code 56
```

Both endpoints are refused. The mode `REGISTRY_ONLY` makes the sidecar proxy refuse every destination that is not in the service registry. The sidecar proxy is the Envoy container that Istio adds to a pod. Here `curl` prints `000` with the exit code `56`, because the proxy closed the connection. After the `ServiceEntry` below, a refused request gets a `502` answer instead. The addresses of your run will differ. Check that the two pods run and that no Service exists for them:

```sh
kubectl -n outside-mesh get pods -o wide | awk '{print $1,$2,$3,$6}'
kubectl -n outside-mesh get svc
kubectl -n egress-demo get serviceentry,virtualservice
kubectl -n egress-demo get deploy -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
kubectl -n outside-mesh get pods -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
```

```text
NAME READY STATUS IP
forbidden-api 1/1 Running 10.244.0.9
partner-api 1/1 Running 10.244.0.8
No resources found in outside-mesh namespace.
No resources found in egress-demo namespace.
NAME     UID
tester   f2850312-31fd-43aa-bedf-502d54ceea53
NAME            UID
forbidden-api   70753b35-78a7-4ca9-8a84-7ebf6db39fb9
partner-api     8dd20857-e2aa-424e-92c7-e8688c8453b3
```

Both pods run, so the refusal is a decision of the proxy and not a failure of the pods. There is no Service in `outside-mesh`, so neither endpoint is in the registry. The last two outputs are the state that must not change.

---

## Items 1 To 6: The `ServiceEntry`

> **Task item 1:** Create a `ServiceEntry` named **`partner-api`** in the namespace **`egress-demo`**.
>
> **Task item 2:** Give it the host **`partner.example.com`**.
>
> **Task item 3:** Add the partner pod's address to **`spec.addresses`** as a plain IP address (for example `10.244.0.12`), so the sidecar proxy can match traffic sent to that address.
>
> **Task item 4:** Declare **one port**: number **8080**, name **`http`**, protocol **`HTTP`**. The protocol matters, because step 7 depends on it.
>
> **Task item 5:** Set `location` to **`MESH_EXTERNAL`** and `resolution` to **`STATIC`**, with one `endpoints` entry whose `address` is the partner pod's address.
>
> **Task item 6:** Limit the entry to its own namespace with **`exportTo: ["."]`**. A `ServiceEntry` is exported to every namespace by default, and this one must not be.

The six items describe one object. Each field does one job:

- `addresses` lets the sidecar proxy match traffic that is sent to that IP address to this entry. Without it, a request to the raw address matches nothing.
- `protocol: HTTP` gives the proxy HTTP features for this port. With `TCP` you would get a working connection, but no timeout, no retries and no routing.
- `location: MESH_EXTERNAL` says that this is the service of somebody else, with no mesh identity and no mTLS (mutual TLS).
- `resolution: STATIC` together with `endpoints` fits an address that is known and fixed. `DNS` would make the proxy look up `partner.example.com`, which resolves nowhere.
- `exportTo: ["."]` limits the entry to its own namespace. The default is every namespace.

Read the address of the partner, and replace `<PARTNER>` in the YAML with it. To see it, run `echo $PARTNER`. Save this as `serviceentry-partner-api.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: partner-api
  namespace: egress-demo
spec:
  hosts:
    - partner.example.com
  addresses:
    - <PARTNER>
  ports:
    - number: 8080
      name: http
      protocol: HTTP
  location: MESH_EXTERNAL
  resolution: STATIC
  endpoints:
    - address: <PARTNER>
  exportTo:
    - "."
```

Apply it:

```sh
kubectl apply -f serviceentry-partner-api.yaml
```

```text
serviceentry.networking.istio.io/partner-api created
```

Check items 1 to 6. Print the spec of the object. Here the partner address is `10.244.0.8`:

```sh
kubectl -n egress-demo get serviceentry partner-api -o jsonpath='{.spec}{"\n"}'
```

```text
{"addresses":["10.244.0.8"],"endpoints":[{"address":"10.244.0.8"}],"exportTo":["."],"hosts":["partner.example.com"],"location":"MESH_EXTERNAL","ports":[{"name":"http","number":8080,"protocol":"HTTP"}],"resolution":"STATIC"}
```

The object has the host, the address in `addresses`, one `HTTP` port, `location` and `resolution`, one endpoint, and `exportTo`.

---

## Items 9, 10 And 13: Only The Partner Is Open

> **Task item 9:** `GET http://<partner-ip>:8080/get` from `tester` returns **200**.
>
> **Task item 10:** `GET http://<forbidden-ip>:8080/get` from `tester` does **not** return 200: allowing one endpoint must not open the other.
>
> **Task item 13:** `partner.example.com` appears in the cluster list of the `tester` pod's sidecar proxy.

`istiod` sends the new entry to the proxy. Wait a few seconds. Look for the host in the cluster list of the proxy. A cluster is a named destination in Envoy. Then call both endpoints again:

```sh
istioctl proxy-config cluster deploy/tester -n egress-demo | grep -E "SERVICE|partner"
for ip in $(cat /tmp/partner-ip) $(cat /tmp/forbidden-ip); do
  printf '%-16s -> ' "$ip"
  kubectl -n egress-demo exec deploy/tester -- \
    curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 "http://$ip:8080/get"
done
```

```text
SERVICE FQDN                                                   PORT      SUBSET     DIRECTION     TYPE             DESTINATION RULE
partner.example.com                                            8080      -          outbound      EDS              
10.244.0.8       -> 200
10.244.0.9       -> 502
```

The proxy has one cluster for the host. The partner endpoint answers with `200`, and the forbidden endpoint is still refused. The `502` comes from the proxy: port `8080` is an `HTTP` port in the registry now, and an address that is not in the registry gets an HTTP error answer. That difference is the point of `REGISTRY_ONLY` together with a `ServiceEntry`: outbound traffic is a list of hosts that you keep, not something that you inherit.

---

## Item 7: The `VirtualService` With A Timeout

> **Task item 7:** Create a `VirtualService` named **`partner-api`** in `egress-demo` for the host **`partner.example.com`**, with a **`timeout` of `2s`** and a route to that host.

A host in the registry is an ordinary host, so every `VirtualService` feature applies to it. The `VirtualService` names the host of the `ServiceEntry`, not the IP address. Save this as `virtualservice-partner-api.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: partner-api
  namespace: egress-demo
spec:
  hosts:
    - partner.example.com
  http:
    - timeout: 2s
      route:
        - destination:
            host: partner.example.com
```

Apply it:

```sh
kubectl apply -f virtualservice-partner-api.yaml
```

```text
virtualservice.networking.istio.io/partner-api created
```

Check item 7:

```sh
kubectl -n egress-demo get virtualservice partner-api -o jsonpath='{.spec}{"\n"}'
```

```text
{"hosts":["partner.example.com"],"http":[{"route":[{"destination":{"host":"partner.example.com"}}],"timeout":"2s"}]}
```

---

## Item 11: The Timeout Fires After Two Seconds

> **Task item 11:** `GET http://<partner-ip>:8080/delay/5` returns **504** after about **2 seconds**. This proves the `VirtualService` timeout applies to the host, and it only works because the port is declared `HTTP`.

Send a request to the path that waits five seconds. Wait a few seconds after the apply first, so that the proxy has the new configuration. Then read the access log of the proxy:

```sh
sleep 3
kubectl -n egress-demo exec deploy/tester -- \
  curl -s -o /dev/null -w '%{http_code} in %{time_total}s\n' --max-time 20 "http://$(cat /tmp/partner-ip):8080/delay/5"
sleep 3
kubectl -n egress-demo logs deploy/tester -c istio-proxy --tail=3 | grep UT | head -1 | cut -c1-120
```

```text
504 in 2.003816s
[2026-10-20T22:02:24.496Z] "GET /delay/5 HTTP/1.1" 504 UT response_timeout - "-" 0 24 2000 - "-" "curl/8.23.0" "3e80259b
```

The request to the endpoint that waits five seconds ended after two seconds, with the flag `UT` ("upstream timeout") in the access log of the proxy. The log line is shortened to 120 characters. This step fails if the protocol of the port is `TCP`. The proxy would not know where one request ends, so the timeout would limit nothing, and you would wait the full five seconds.

---

## Item 8: The Mesh Is Still `REGISTRY_ONLY`

> **Task item 8:** The mesh is still `REGISTRY_ONLY`. Do not change it to make the task pass.

```sh
kubectl -n istio-system get cm istio -o jsonpath='{.data.mesh}' | grep -A2 outboundTrafficPolicy
```

```text
outboundTrafficPolicy:
  mode: REGISTRY_ONLY
rootNamespace: istio-system
```

The mode is unchanged. With `ALLOW_ANY`, both endpoints would work, and the task would be a different one: one precise permission, not an open mesh.

---

## Item 12: The Fields Of The `ServiceEntry`

> **Task item 12:** The `ServiceEntry` has `location: MESH_EXTERNAL`, `resolution: STATIC` and `exportTo: ["."]`.

```sh
kubectl -n egress-demo get serviceentry partner-api \
  -o jsonpath='location={.spec.location} resolution={.spec.resolution} exportTo={.spec.exportTo}{"\n"}'
```

```text
location=MESH_EXTERNAL resolution=STATIC exportTo=["."]
```

---

## What Must Not Change: No Service In `outside-mesh`

> **Task rule:** Do not create a Service in `outside-mesh`.

```sh
kubectl -n outside-mesh get svc
kubectl -n outside-mesh get pods -o custom-columns=NAME:.metadata.name,UID:.metadata.uid
```

```text
No resources found in outside-mesh namespace.
NAME            UID
forbidden-api   70753b35-78a7-4ca9-8a84-7ebf6db39fb9
partner-api     8dd20857-e2aa-424e-92c7-e8688c8453b3
```

There is still no Service, and the two pods have the same `UID` values as before. A Service would put the endpoint in the registry another way.

---

## Submit

Send the lab for grading:

```sh
astrona submit -c sections/section-070/module-01/labs/lab-01
```

The grader calls both endpoints from `tester` and reads the objects.

---

## Mistakes That Fail The Grader

- **Leaving out `spec.addresses` (item 3).** The host is in the registry, but the sidecar proxy cannot match traffic that is sent to the raw IP address.
- **`protocol: TCP` (items 4 and 11).** A working connection with no HTTP features. The timeout silently does nothing.
- **`resolution: DNS` (item 5).** `partner.example.com` resolves nowhere. `STATIC` with `endpoints` fits a known address.
- **Leaving out `exportTo` (item 6).** The entry is exported to every namespace by default.
- **Listing both addresses (item 10).** Adding the forbidden endpoint too opens it.
- **Changing the mesh to `ALLOW_ANY` (item 8).** Both endpoints then work. The task is one precise permission, not an open mesh.
- **Creating a Service in `outside-mesh`.** That would put the endpoint in the registry another way.
- **Pointing the `VirtualService` at the IP address (item 7).** It must name the host of the `ServiceEntry`.
