# Practice: Fault Injection With Delays And Aborts

An exam-style training mission for this playground, astronaut. Start the playground first, and paste the helper functions from the [overview](overview.md#helper-functions). The solution uses them.

Try the task on your own first, then open the solution. The solution was run and checked on a cluster like this one.

## Task: a drill for one sending ship

> Signals from `bridge` to `cargo` must be delayed by **3 seconds**. Signals from any other ship to `cargo` must stay fast.

<details><summary>Solution</summary>

The drill goes on the flight plan of `cargo`, the ship you pretend is slow. A `sourceLabels` match picks the bridge as the sender, and a plain rule below it keeps every other signal fast. Save this as `virtualservice-cargo-delay-from-bridge.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: cargo
  namespace: starfleet
spec:
  hosts:
  - cargo
  http:
  - match:
    - sourceLabels:
        app: bridge
    fault:
      delay:
        percentage:
          value: 100
        fixedDelay: 3s
    route:
    - destination:
        host: cargo
  - route:
    - destination:
        host: cargo
```

Apply it:

```sh
kubectl apply -f virtualservice-cargo-delay-from-bridge.yaml
```

Then check the result. Send one signal from the shuttle straight to the cargo ship, and two to the bridge, which calls the cargo ship:

```sh
status_and_time http://cargo:9080/details/0
status_and_time http://bridge:9080/productpage
status_and_time http://bridge:9080/productpage
```

You should see something like:

```text
200 0.008977s
200 3.108051s
200 3.030261s
```

The shuttle's own signal to the cargo ship is fast. Every bridge page takes three seconds longer, because the bridge's signal to the cargo ship is held back.

Remove the drill when you are done:

```sh
kubectl delete virtualservice cargo -n starfleet
status_and_time http://bridge:9080/productpage
```

```text
200 0.050802s
```

</details>
