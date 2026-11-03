# Roll A TCP Service Forward And Back

A new version of a service is released in steps: a small share first, then more, and a fast way back if something breaks. For a `tcp` route, the steps are changes to two numbers, and `kubectl patch` can change them without a new YAML file. This part moves the weights from 100/0 to 90/10, 50/50 and 0/100, rolls them back, and then breaks the setup on purpose to see what a `tcp` route does on a port that Istio treats as HTTP.

The commands below need the Service `probe-tcp`, the `DestinationRule` `probe-tcp` and the `VirtualService` `probe-tcp` applied in your playground.

## Start from 100/0

A release starts with all connections on the stable version `v1`, and no connection on `v2`. Define a small shell function that sets both weights of the first `tcp` route with one JSON patch, and waits for the proxies to receive the change. A JSON patch lists operations on exact paths, so it changes the two numbers and nothing else. A merge patch would replace the whole `tcp` list.

<!-- astrona:playground:renew -->

```sh
set_weights() {
  kubectl patch virtualservice probe-tcp -n starfleet --type json \
    -p "[{\"op\":\"replace\",\"path\":\"/spec/tcp/0/route/0/weight\",\"value\":$1},{\"op\":\"replace\",\"path\":\"/spec/tcp/0/route/1/weight\",\"value\":$2}]"
  sleep 5
}
set_weights 100 0
astrona res run count-connections.sh -- 40
```

Every answer should come from `probe-v1`. The function takes the weight of `v1` first and the weight of `v2` second.

## Roll forward in steps

Move the weight to `v2` in three steps, and count 40 fresh connections after each:

```sh
set_weights 90 10; astrona res run count-connections.sh -- 40
set_weights 50 50; astrona res run count-connections.sh -- 40
set_weights 0 100; astrona res run count-connections.sh -- 40
```

At 90/10, expect a handful of `probe-v2` answers, about 4 of 40, and not exactly that. At 50/50, expect the two versions close to even. At 0/100, every answer should come from `probe-v2`. A weight of 0 is not an error. It only means that no new connection goes to that subset.

One fact decides how a rollout behaves in production: a weight change only affects **new** connections. A connection that was open before the change keeps its pod until it closes. A client with a long-lived connection to `v1` stays on `v1` after you move 100% to `v2`. The counts above use new connections, so they follow the change at once.

## Roll back

The way back is the same patch with the old numbers. One patch undoes the whole rollout for every new connection:

```sh
set_weights 100 0; astrona res run count-connections.sh -- 40
```

Every answer should come from `probe-v1` again. Connections that were open at 0/100 stay on `v2` until they close.

## When the tcp route does nothing

The setup so far works because the port of `probe-tcp` is named `tcp`. A common mistake is a Service port named `http`: the `VirtualService` is correct, the weights are valid, and the split never happens. Break the setup on purpose. This JSON patch renames the Service port to `http`:

```sh
kubectl patch service probe-tcp -n starfleet --type json \
  -p '[{"op":"replace","path":"/spec/ports/0/name","value":"http"}]'
```

Wait a few seconds. The weights are still 100/0, so every connection should go to `v1`. Check three things, in this order. First, the route table, which now should contain a host for `probe-tcp`, because Istio treats the port as HTTP:

```sh
istioctl proxy-config routes deploy/shuttle -n starfleet --name 8000
```

The route table lists `probe-tcp.starfleet.svc.cluster.local:8000` as a virtual host. For a `tcp` port it listed no such host. Second, the listener. Count the lines that mention `weightedClusters`, and then count 40 fresh connections:

```sh
istioctl proxy-config listener deploy/shuttle -n starfleet --port 8000 -o json | grep -c weightedClusters
astrona res run count-connections.sh -- 40
```

The first command should print `0`, because no weighted TCP route is in the proxy any more. The counts should now show both versions, because the Service sends each request to either pod and the weights no longer apply. That is the symptom: a split that does not follow the weights, and a VirtualService that looks correct.

Finally, run the analyzer on the namespace, and read what it says about `probe-tcp`:

```sh
istioctl analyze -n starfleet
```

Do not rely on `istioctl analyze` for this problem. The `VirtualService` and the Service are both valid objects, so the analyzer may report nothing about them. The route table and the listener are the checks that tell you the truth.

The fix is to name the port `tcp` again. After the patch, wait a few seconds and repeat the three checks:

```sh
kubectl patch service probe-tcp -n starfleet --type json \
  -p '[{"op":"replace","path":"/spec/ports/0/name","value":"tcp"}]'
```

The route table no longer lists the `probe-tcp` host, the listener shows weighted clusters again, and all connections go to `v1` while the weights are 100/0.

## A second cause: a subset that selects no pods

A split can also fail when the port is correct. A subset is only a label selector. If the labels of a subset match no pod, the cluster of that subset has no endpoints, and every connection that the weights send to it fails. The route looks fine in the `VirtualService`, and the listener still shows the weighted clusters. Check the endpoints of the cluster, and run the analyzer, which can report a subset that selects no pods with the code `IST0173`:

```sh
istioctl proxy-config endpoints deploy/shuttle -n starfleet --cluster "outbound|8000|v2|probe-tcp.starfleet.svc.cluster.local"
istioctl analyze -n starfleet
```

With the playground as it is now, the endpoints command should list the address of the `probe-v2` pod as `HEALTHY`. A subset with wrong labels would list no endpoints at all, and the fix is in the `DestinationRule` labels.

You now know how to roll a TCP service forward and back with one patch, that a weight change reaches only new connections, and how to tell a `tcp` route on an `http` port from a working one: no weighted clusters in the listener, a host for the Service in the route table, and answers that ignore the weights. You also know the second quiet cause, a subset whose labels match no pod, and the endpoints check that finds it. That completes the TCP side of weighted routing.

## Common pitfalls

> [!WARNING]
> - **Using a merge patch on the `tcp` list.** It replaces the whole list. Patch the two weight paths, or write the full route.
> - **Expecting open connections to move.** A weight change only affects new connections. Long-lived connections stay on their pod.
> - **Judging a step from a few samples.** Count at least 40 fresh connections for a rough check and 100 for a fair one.
> - **Trusting `istioctl analyze` on a port named `http`.** The objects are valid, so the analyzer may be silent. Read the route table and the listener.
> - **Fixing the VirtualService when the Service is wrong.** The route is fine. The port name is the fault.

## Your mission: Fix A TCP Split That Never Happens Lab

You can now roll a TCP service in steps and tell why a `tcp` route does not apply. The mission gives you a cluster where an 80/20 split is configured and never happens, and asks you to find every cause and fix it, until the grader sees the split with many fresh connections.

Pause the playground, start the lab, and send it for grading:

```sh
astrona stop ats-014-playground-020-03
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-020/module-03/labs/lab-02
astrona submit -c sections/section-020/module-03/labs/lab-02
```

When the lab passes, remove it and start the playground again:

```sh
astrona destroy ats-014-lab-020-03-02
astrona start ats-014-playground-020-03
```
