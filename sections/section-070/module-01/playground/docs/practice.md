# Practice: Egress With ServiceEntry And REGISTRY_ONLY

An exam-style mission for this playground, astronaut. Start the playground first and paste the `call_external` helper from [`overview.md`](overview.md). The solution uses it.

Try it on your own first, then open the solution. The solution was run and checked on a cluster like this one.

> Ships in `starfleet` may reach only one outside host: **www.google.com** over HTTPS. Every other outside host must stay blocked, and the chart entry must not open `www.google.com` for any other namespace.

<details><summary>Solution</summary>

Lock the planet first. Save this as `sidecar-registry-only.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  name: default
  namespace: starfleet
spec:
  outboundTrafficPolicy:
    mode: REGISTRY_ONLY
  egress:
  - hosts:
    - "./*"
    - "istio-system/*"
```

Apply it:

```sh
kubectl apply -f sidecar-registry-only.yaml
```

Then put the one allowed host on the star chart, private to `starfleet`. Save this as `serviceentry-google.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: google
  namespace: starfleet
spec:
  hosts:
  - www.google.com
  exportTo:
  - "."
  ports:
  - number: 443
    name: https
    protocol: HTTPS
  location: MESH_EXTERNAL
  resolution: DNS
```

Apply it:

```sh
kubectl apply -f serviceentry-google.yaml
```

Then check the result:

```sh
call_external https://www.google.com
call_external https://httpbin.org/get
```

You should see:

```text
200 0.122030s
  exit=0
000 0.014055s
command terminated with exit code 35
  exit=35
```

</details>
