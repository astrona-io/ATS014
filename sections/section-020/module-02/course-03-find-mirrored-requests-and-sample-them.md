# Find Mirrored Requests And Sample Them

A mirror is invisible to the client. That is on purpose, but it leaves a practical question: how do you know the mirror works at all? This part shows where the proof is: in the access log of the pod that receives the copies. Then it lowers the copied share with `mirrorPercentage`, for services where twice the load is too much.

The commands below need a `DestinationRule` named `probe` in the `starfleet` namespace with the subsets `v1` and `v2`, and a `VirtualService` named `probe` that routes every request to `v1` and mirrors 100% to `v2`. They also need the `mark_start`, `count_received` and `send_requests` shell helpers in your terminal.

## Telling a copy from a normal request

A copy is the same request, byte for byte. Older Istio releases made one change to it: they added `-shadow` to the host name in the `Host` header (the authority), so `probe` became `probe-shadow`. A shadow application could read that and act differently, for example skip a database write.

**Istio 1.30, the version this course uses, no longer does that.** A copy arrives with the original host name. By its headers alone, it looks exactly like a normal request. Older material, and some exam questions, still describe the suffix, so recognise it, but never build a check on it.

The routing is what still identifies a copy. The `VirtualService` sends 100% of client requests to v1, so nothing that v2 receives can come from the route. **Every request v2 receives is a copy.** That is what you check, and it does not depend on any header.

## Where the proof is

The receiving pod has two logs, and both work as proof. The **application log** of `probe` has one line per request it handles; `count_received` reads it. The **access log** of the sidecar proxy has one line per request that passes through the proxy. To read it, name the `istio-proxy` container of the shadow's Deployment, not of `shuttle`.

<!-- astrona:playground:renew -->

Send a few requests, then read the last two lines of the access log of v2, and the last line of the access log of `shuttle`:

```sh
send_requests 5
kubectl logs -n starfleet deploy/probe-v2 -c istio-proxy --tail=2
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=1
```

You should see (the first line is the output of `send_requests`):

```text
   5 probe-v1
[2026-10-08T20:32:54.635Z] "GET /hostname HTTP/1.1" 200 - via_upstream - "-" 0 45 0 0 "10.244.0.6" "curl/8.11.1" "2baad0f9-88f4-4cc3-90be-f78b92ea72d8" "probe:8000" "10.244.0.8:8080" inbound|8080|| 127.0.0.6:45293 10.244.0.8:8080 10.244.0.6:0 outbound_.8000_.v2_.probe.starfleet.svc.cluster.local default
[2026-10-08T20:32:54.695Z] "GET /hostname HTTP/1.1" 200 - via_upstream - "-" 0 45 0 0 "10.244.0.6" "curl/8.11.1" "a19acd54-cfbb-4d6a-a3f5-80ba54c8b36a" "probe:8000" "10.244.0.8:8080" inbound|8080|| 127.0.0.6:45293 10.244.0.8:8080 10.244.0.6:0 outbound_.8000_.v2_.probe.starfleet.svc.cluster.local default
[2026-10-08T20:32:54.695Z] "GET /hostname HTTP/1.1" 200 - via_upstream - "-" 0 46 1 0 "-" "curl/8.11.1" "a19acd54-cfbb-4d6a-a3f5-80ba54c8b36a" "probe:8000" "10.244.0.7:8080" outbound|8000|v1|probe.starfleet.svc.cluster.local 10.244.0.6:55596 10.96.35.237:8000 10.244.0.6:32936 - -
```

Your times, request IDs and addresses will be different. Three fields in these lines prove that the mirror works:

```text
outbound_.8000_.v2_.probe...   on v2's line: the request came in through the v2 subset, which the route never uses
"probe:8000"                    the host name is unchanged: no -shadow suffix on Istio 1.30
"a19acd54-..."                  the same request ID on v2's line and on the shuttle's line
```

The request ID is the clearest proof. The line from `shuttle` shows that request `a19acd54-…` went to the cluster `outbound|8000|v1|…`, the v1 subset. The line from v2 shows the **same request ID** arriving at v2. One request left `shuttle` and two pods received it: the original went to v1 and the copy went to v2.

If the access log of v2 stays empty while `shuttle` gets normal responses, the mirror is not sending.

## Counting instead of reading

Reading lines is fine for a quick look. For anything more, count them instead. The route sends nothing to v2, so every request that v2 receives is a copy, and counting received requests counts copies.

One detail matters: logs keep everything from earlier runs. A raw count includes every copy from every earlier test. That is why the helpers work in two steps: `mark_start` saves the time, and `count_received` counts only the log lines written after that time.

## Sampling with `mirrorPercentage`

A full mirror doubles the number of requests inside the cluster. For a busy service, or a shadow you do not yet trust with real load, copy only a share. The value under `mirrorPercentage` is the share of **matched** requests that get a copy, as a decimal number in percent.

If you leave `mirrorPercentage` out, every matched request is copied. **The default is 100%, not 0%.** That is easy to get wrong in the exam.

The proxy decides for each request on its own, at random, with the chance you set. So send many requests before you judge the share. Set the share to 20%: save this as `virtualservice-probe.yaml`, replacing the old file:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe
  namespace: starfleet
spec:
  hosts:
  - probe
  http:
  - route:
    - destination:
        host: probe
        subset: v1
    mirror:
      host: probe
      subset: v2
    mirrorPercentage:
      value: 20.0
```

Apply it:

```sh
kubectl apply -f virtualservice-probe.yaml
```

Then send 30 requests, and after that 100:

```sh
mark_start; send_requests 30; count_received
mark_start; send_requests 100; count_received
```

You should see something like:

```text
  30 probe-v1
probe-v1 received: 30
probe-v2 received: 4
 100 probe-v1
probe-v1 received: 100
probe-v2 received: 20
```

At 30 requests, 4 copies is a little under 20%: a small sample moves around. At 100 requests the count lands on 20. Your numbers will be a little different on every run.

## Sampling is not filtering

`mirrorPercentage` and a `match` block both limit what gets copied, but in different ways. A task may ask for either one.

`mirrorPercentage` picks a **random share** of requests. It gives the shadow a fair sample of real traffic, which is what you want for load and crash tests. A `match` block picks a **specific kind** of request. A mirror on a rule that matches the header `x-internal: true` copies only internal traffic. That is predictable, but it is not a fair sample of anything.

You can combine them. Take a rule that matches internal requests with `mirrorPercentage` at 100, followed by a catch-all rule with `mirrorPercentage` at 10. Together they copy every internal request and a tenth of everything else. Each `http` rule has its own mirror settings, and there is no mirror setting for the whole mesh.

You now know how to prove that copies arrive: in the access log of the receiving pod, through the mirror subset, with the same request ID as the original. You also know how to copy only a share of the requests. What is still open is what those copies do inside the shadow, and how to check the client's proxy when the shadow stays quiet.

## Common pitfalls

> [!WARNING]
> - **Looking for a `-shadow` host name suffix.** Istio 1.30 does not add one. The routing, not a header, identifies a copy.
> - **Counting a log without a start time.** Logs keep earlier runs. Use `mark_start`, or you count every test you have ever run.
> - **Assuming that a missing `mirrorPercentage` means no mirroring.** The default is 100%.
> - **Looking for the proof on the client.** The client sees nothing. The logs of the receiving pod are the only place a copy shows up.
> - **Judging a percentage from a few requests.** Count at least 100.

## Your mission: Route To v1 And Mirror Every Request To v2 Lab

You can now add a mirror, prove from the receiving side that copies arrive, and control the copied share. The lab asks you to route every request to a stable version and mirror every request to a release candidate, so that no client ever gets a response from the release candidate. The lab uses its own small app (`notification-service` and a `tester` client in the `mirror-demo` namespace), not the `probe` and `shuttle` from this module.

The lab runs in its own cluster, so first pause your playground. Nothing in it is lost:

```sh
astrona stop ats-014-playground-020-02
```

Then start the lab:

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-020/module-02/labs/lab-01
```

The task is on the next page. Solve it on your own first. When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-020/module-02/labs/lab-01
```

When the lab is done, remove it and start your playground again:

```sh
astrona destroy ats-014-lab-020-02
astrona start ats-014-playground-020-02
```
