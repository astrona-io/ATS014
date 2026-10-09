# Timeouts And Retries

Astronaut, picture a convoy of spaceships passing signals down a line. If one ship stops answering, the ship that called it waits with its radio channel open. That ship's own callers wait too. One stuck ship can stall a whole chain, and nothing crashes anywhere. More ships do not fix this. A deadline does.

A **timeout** is that deadline: the mission's abort window. If no answer has come back by then, the signal is given up, and the sender gets an error instead of waiting forever.

**Retries** are the same idea from the other side. Many failures only last a moment: a ship restarts, or a connection drops. A retry is re-sending a signal that got lost in space. Istio's communications officers can do it for you, without the app knowing.

The two settings share one clock, and that is the detail exams like to test most:

> The route `timeout` is the abort window for the **whole** signal, **including** all retries. A timeout shorter than (`attempts` + 1) × `perTryTimeout` quietly cuts the retries short.

## Learning objectives

After this module you can:

- Set a route `timeout`, say which proxy measures it, and name the status the sender receives.
- Test a timeout by putting a delay on the ship being called and the timeout on the caller, and explain why the two cannot share one rule.
- Explain why a timeout protects the sender but does not stop the receiver's work.
- Configure `retries` with `attempts`, `perTryTimeout` and `retryOn`, and choose between `5xx`, `gateway-error` and an exact status code.
- Read `attempts` correctly as the number of retries *after* the first try.
- State Istio's default retry policy and how to switch retries off for real.
- Calculate the abort window a retry policy needs, and recognise cut-off retries from a `504` with `UT` and used-up retries from `URX`.
- Prove how many tries really happened from the receiver's flight log.
- Keep retries away from signals that are not safe to send twice.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects, know what is waiting in your playground, and have two small helpers ready in your terminal.

### What you should already know

- **How the mesh works.** A proxy (the communications officer) sits beside every pod, and `istiod` (mission control) sends it orders. You can read those orders with `istioctl proxy-config`.
- **Flight plans.** How to write a `VirtualService` with routing rules. Both settings in this module are extra fields on a rule you already know how to write.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** installed with Helm, and flight logs (access logs) switched on for every ship. Everything you need is on one planet, the namespace **`starfleet`**:

| Ship | Its role in the fleet |
| --- | --- |
| `bridge`, `cargo` | The flagship and the supply ship of the Starfleet |
| `scout` v1, v2, v3 | Three ship classes of one scout. Only v2 and v3 call `navcom`, which matters when you test a timeout across two ships |
| `navcom` | The navigation computer that the v2 and v3 scouts ask |
| `probe` v1, v2 | An echo probe that fails on demand. `/delay/<seconds>` waits before it answers, and `/status/<code>` answers with exactly that status. `/status/200,503` picks one of the two at random |
| `shuttle` | Your test client. You send every test signal from here |

The scout's docking instructions (subsets v1, v2, v3) and a flight plan that sends `end-user: jason` to scout v2 are already applied. There is **no** timeout and **no** retry rule yet. Writing them is your mission in this module.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

### Two helpers to paste first

Paste these into each new terminal before you start:

```sh
status_and_time() { kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" "$@"; }
count_received() { sleep 4; kubectl logs -n starfleet -l app=probe -c istio-proxy --since=${2:-8s} | grep -c "$1"; }
```

`status_and_time` sends one signal from the shuttle and prints the status code and the time it took. `count_received` counts how many signals the probe ships really received, from their flight logs. That is the only place where you can see retries, because the sender always gets just one answer.

### Extra practice

The playground also comes with two exam-style practice tasks with checked solutions. You find them in the playground folder, under `docs/practice.md`.

## Why this matters

Timeouts and retries decide how the rest of the mesh behaves under trouble. A missing timeout lets one stuck ship stall every caller. A careless retry policy turns a short hiccup into a retry storm that hits an overloaded ship harder. Get these two settings right, and every other failure feature has a stable base to build on.
