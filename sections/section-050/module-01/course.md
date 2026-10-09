# Fault Injection With Delays And Aborts

Astronaut, a timeout you have never seen fire is a guess. A retry policy you have never watched retry is a guess too. You could wait for a real outage to find out, which is a poor plan. Or you could build failure switches into every ship, which means flying test code on real missions.

Fault injection gives you a third way: the **simulation drill**. Mission control fakes an engine failure on purpose, so the crew can practise the response while nothing is really at stake. In the mesh, the drill is a few lines in a flight plan. The communications officer beside a ship holds a signal back for two seconds, or answers it with an error without ever sending it on. The ships themselves are not changed at all, and they cannot tell a drill from the real thing. That is exactly what makes the result worth trusting.

## Learning objectives

After this module you can:

- Add a `fault.delay` and a `fault.abort` to a flight plan, and say exactly what the sender sees for each.
- Name the flight plan a drill belongs on, and the communications officer that carries it out.
- Explain why an aborted signal leaves no trace at the receiving ship, and recognise drills by the `DI` and `FI` flags in the sender's flight log.
- Run a drill on a share of the signals with `percentage`, on your own signals with a `match`, and on one sending ship with `sourceLabels`.
- Use a delay to make a timeout fire on demand, and explain why a drill rule ignores its own `timeout` and `retries`.
- Find a forgotten drill in the proxy's orders.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects, know what is waiting in your playground, and have two small helpers ready in your terminal.

### What you should already know

- **How the mesh works.** A proxy (the communications officer) sits beside every pod, and `istiod` (mission control) sends it orders. You can read those orders with `istioctl proxy-config`.
- **Flight plans.** How to write a `VirtualService` with routing rules and a `match`. A drill is one extra field on a rule you already know how to write.
- **Timeouts and retries.** What a route `timeout` and a `retries` block do. A drill is most useful when it has a safety setting to test.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** installed with Helm, and flight logs (access logs) switched on for every ship. Everything you need is on one planet, the namespace **`starfleet`**:

| Ship | Its role in the fleet |
| --- | --- |
| `bridge`, `cargo` | The flagship and the supply ship of the Starfleet. The bridge calls the cargo ship and the scout |
| `scout` v1, v2, v3 | Three ship classes of one scout. Only v2 and v3 ask `navcom` for a star rating, so a drill on navcom shows up through them |
| `navcom` | The navigation computer that the v2 and v3 scouts ask |
| `probe` v1, v2 | An echo probe you can send signals to directly |
| `shuttle` | Your test client. You send every test signal from here |

The docking instructions for the scout (subsets v1, v2, v3) and for navcom (subset v1) are already applied. There is **no** flight plan (`VirtualService`) yet, so there is no drill either. Writing them is your mission in this module.

The scout passes the `end-user` label of a signal on to navcom. That is what lets a drill on navcom hit one user's signals only, even through the scout.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

### Two helpers to paste first

Paste these into each new terminal before you start:

```sh
status_and_time() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" "$@"; }
count_navcom_status() { for i in $(seq 1 10); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code}\n" http://navcom:9080/ratings/0
done | sort | uniq -c; }
```

`status_and_time` sends one signal from the shuttle and prints the status code and the time it took. Add `-H "end-user: jason"` before the address to send it as jason. `count_navcom_status` sends 10 signals from the shuttle straight to navcom and counts the status codes, so you can see a drill that hits only a share of the signals.

### Extra practice

The playground also comes with an exam-style practice task with a checked solution. You find it in the playground folder, under `docs/practice.md`.

## Why this matters

Every safety setting in the mesh is a promise about what happens when a ship fails. A drill is how you check that promise while nothing is at stake. It is also the cheapest way to learn what your own ships do when a ship they depend on is down, which is usually less graceful than anyone expects. And because the drill lives in a flight plan, you decide exactly whose signals it touches, so one drill never takes out the whole fleet.
