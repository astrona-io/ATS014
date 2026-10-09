# Shift Traffic With Weighted Routing

Astronaut, your mission in this module is a safe launch: put a new ship class into service without risking the whole fleet. Routing by a header sends one particular signal to one particular version. Releasing a new version is a different problem. You do not want one astronaut on the new version. You want **a share of all signals** there, with the share under your control, so that if the new version misbehaves you can turn it back down before most astronauts notice.

That is **weighted routing**, and it is how every canary release works in Istio. A canary sends a small share of signals to the new ship class before the whole fleet switches over. The object is the `VirtualService` you already know, the flight plan. The change is one field, `weight`:

> Weights split signals across the subsets of one beacon. Write them so they add up to 100.

The field is small. What makes it worth three parts is everything around it. The split is random for every signal, so it is easy to measure wrong. A patch that changes it replaces a whole list instead of editing it. And the question that comes up most is about weights and replica counts, which have nothing to do with each other.

## Learning objectives

After this module you can:

- Write a `VirtualService` route with several weighted destinations, and place `weight` on the correct field.
- Write weights that add up to 100, predict the split when they do not, and say when `weight` may be left out.
- Explain how the proxy applies a weight (once per signal, on its own) and what that means for how many signals you count.
- Run a canary rollout as a series of weight changes, and roll it back in one apply.
- Combine a header match with a weighted split, and predict which signals the weights apply to.
- Explain why a merge patch on `spec.http` must restate the whole route list.
- Explain why traffic share and replica count are independent, and predict the split when they disagree.
- Read `weightedClusters` from `istioctl proxy-config routes` and match each entry to your YAML.

## Before you start

Every mission starts with a pre-flight check, astronaut. Make sure you have the knowledge this module expects, know what is waiting in your playground, and have one small helper ready in your terminal.

### What you should already know

- **How the mesh works.** A proxy (the communications officer) sits beside every pod, and `istiod` (mission control) sends it orders. You can read those orders with `istioctl proxy-config`.
- **The two routing objects.** A `DestinationRule` (the docking instructions) defines subsets: the ship classes of one beacon. A `VirtualService` (the flight plan) sends signals to them. Weighted routing adds nothing new to that pair. It only puts numbers on the destinations.

### What is in your playground

Your playground is a small training solar system: one `kind` cluster with **Istio 1.30.5** installed with Helm. Everything is on one planet, the namespace **`starfleet`**, where the Starfleet lives: the Istio docs' Bookinfo sample with space names.

| Ship | Its role in the fleet |
| --- | --- |
| `bridge` | The **flagship**: the page astronauts see. It asks the other ships for the parts of the page |
| `cargo` | The **supply ship**: it answers with facts about an item |
| `scout` v1, v2, v3 | Three **ship classes** of the same scout. v1 reports no stars, v2 black stars, v3 red stars. This is the beacon you split in this module |
| `navcom` | The **navigation computer**: the v2 and v3 scouts ask it for the star rating |
| `shuttle` | **Your shuttle**: you send every test signal from here |
| `probe` v1, v2 | An **echo probe** on port `8000`, free for your own tests |

The **`scout` `DestinationRule`** is already applied, with the subsets `v1`, `v2` and `v3`. There is **no** `VirtualService` yet, so for now the Kubernetes Service spreads signals over all three versions.

One thing keeps its old name: the web paths built into the ships. A signal to the scout goes to `http://scout:9080/reviews/0`. Each answer names the ship that sent it (`"podname": "scout-v3-..."`), and that is how you count a split.

You can also watch the flagship from your browser at `http://127.0.0.1:9080/productpage`. Refresh it during a split and watch the stars change from one signal to the next.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

### One helper to paste first

Paste this into each new terminal. It sends a number of signals to the scout (20 if you give no number) and counts which version answered. Extra `curl` options go after the number:

```sh
count_versions() { n=${1:-20}; [ $# -gt 0 ] && shift; for i in $(seq 1 $n); do
  kubectl exec -n starfleet deploy/shuttle -- curl -s "$@" http://scout:9080/reviews/0 | grep -o 'scout-v[0-9]'
done | sort | uniq -c; }
```

Use it like this: `count_versions` for 20 signals, `count_versions 100` for 100, or `count_versions 10 -H "end-user: jason"` for 10 signals as jason.

## Why this matters

Weighted routing is the safest way to change a running fleet. You choose the share of signals a new version gets, and you can take every signal away from it again in seconds, without restarting a single ship. The same `http` rule later carries more fields, such as a copy of each signal, time limits and retries, so the shape you learn here comes back again and again.
