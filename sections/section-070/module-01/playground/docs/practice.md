# Practice – Egress: ServiceEntry And REGISTRY_ONLY

An exam-style mission for this playground, astronaut. Start the playground first and paste the `call_external` helper from [`overview.md`](overview.md) — the solution uses it.

Try it on your own first, then open the solution. The solution was run and checked on a cluster like this one.

> Pods in `bookinfo` may only reach the outside host **www.google.com** (HTTPS). Everything else external must stay blocked.

<details><summary>Solution</summary>

Lock the namespace down first. This is the same `Sidecar` as Part 1 of the module:

```bash
cat > sidecar-registry-only.yaml <<'YAML'
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  name: default
  namespace: bookinfo
spec:
  outboundTrafficPolicy:
    mode: REGISTRY_ONLY
  egress:
  - hosts:
    - "./*"
    - "istio-system/*"
YAML
kubectl apply -f sidecar-registry-only.yaml
```

Then put the one allowed host on the star chart:

```bash
cat > serviceentry-google.yaml <<'YAML'
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata: {name: google, namespace: bookinfo}
spec:
  hosts: [www.google.com]
  ports: [{number: 443, name: https, protocol: HTTPS}]
  location: MESH_EXTERNAL
  resolution: DNS
YAML
kubectl apply -f serviceentry-google.yaml
call_external https://www.google.com         # 200
call_external https://httpbin.org/get        # 000  exit=35
```

</details>
