# Apply And Remove Traffic Rules Safely

<!-- astrona:playground -->
> [!NOTE]
> 🧪 **Hands-on playground for this module** — a clean, throwaway machine to explore on. No task, no grading. Folder: `playground/`
>
> ```sh
> astrona run --git ssh://git@github.com/astrona-io/ATS014.git -c sections/section-010/module-03/playground
> astrona destroy ats-014-playground-010-03
> ```

Astronaut, writing a correct rule is half the job. The other half is changing a live mesh without breaking it on the way. Istio's objects point at each other. A `VirtualService` points at subsets in a `DestinationRule`, and at a `Gateway`. A route can point at an outside host from a `ServiceEntry`. If a pointer arrives before the thing it points at, signals fail, even though every object is correct.

This module is about that order. Think of `istiod` as mission control radioing new orders to the whole fleet. The orders do not reach every ship at the same moment. For a short time, some ships fly the new flight plan and some still fly the old one. The safe order makes sure no ship is ever told to send a signal to a ship class that does not exist yet.

## How this module is organised

1. **[The Order To Apply And Remove Rules](./course-01-the-order-to-apply-and-remove-rules.md)**: where each rule runs, why the order matters ("make before break"), the `503 NC` you get when it is wrong, and the reverse order for removing things.
2. **[One Object Per Host, And The Defaults](./course-02-one-object-per-host-and-the-defaults.md)**: why `kubectl apply` replaces an object, why two objects for one host cause trouble, what Istio does when you have written nothing at all, and a quick reference to the response flags you will meet in later sections.

This module has no graded lab of its own. The order it teaches is used in every graded lab and capstone that follows.

## Learning objectives

After this module you can:

- Name the order to create `ServiceEntry`, `DestinationRule`, `Gateway` and `VirtualService`, and the reverse order to remove them.
- Explain "make before break", and reproduce the `503 NC` that the wrong order causes.
- Check that every proxy has the new configuration with `istioctl proxy-status` before you test.
- Explain why two files with the same `metadata.name` describe one object, and why to avoid two objects for one host.
- State Istio's defaults for HTTP timeout, retries, load balancing, unknown outside hosts and circuit breaking.

## Before you start

You need [Route Requests Within The Mesh](../module-01/course.md), at least parts 1 to 3: subsets, the `VirtualService` route, and the `503 NC` / `503 UH` signatures. The other objects named here (`Gateway`, `ServiceEntry`, `Sidecar`) are taught in later sections. You only need to know that they exist and what they point at.

The playground is a training solar system with **Istio 1.30.5** installed with Helm and mesh-wide access logs. Everything lives on one planet, the namespace **`starfleet`**: the fleet (the Istio docs' Bookinfo sample, renamed with space names), with the three ship classes of the scout (`scout` v1, v2, v3), your test client `shuttle`, and the echo `probe`. It starts with **no** `DestinationRule` and **no** `VirtualService`. Its [`examples/`](./playground/examples/) folder holds the two files the parts use.

One name did not change: the path inside each signal. The ships run the official Bookinfo images, which answer on fixed paths, so a signal to the scout is `http://scout:9080/reviews/0`.

## Where this fits

Module 01 taught what the objects say. Module 02 taught how much each proxy is told. This module is about *when* each piece reaches the proxies, and what happens in between. Every later section adds objects to the chain (traffic shifting, gateways, service entries), and each one follows the order you learn here.
