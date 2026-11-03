# Configuring Traffic Shifting

This section is about releasing a new version of a service while the old one keeps serving traffic. Releasing a new version is a traffic problem before it is a deployment problem. Starting the new pods is easy. The hard questions are how many real requests reach them, and how fast you can go back.

Istio gives two answers, and this section covers both, for HTTP requests and for plain TCP connections. Weighted routing sends a set percentage of live requests to the new version. Real users get real responses from it, and one apply undoes it. Mirroring sends the new version a *copy* of each request and throws its response away. The new version sees real load, and no user ever gets its response.

The two features solve the same problem from opposite ends, so choosing between them is a real decision. Weights show you the new version's responses. Mirroring shows you its behaviour under load, but gives you no way to compare its output.

**Curriculum item covered:** Configuring Traffic Shifting

---

## What You Will Master

- Several weighted destinations in one `route` block, with `weight` beside `destination`, written to add up to 100 (on Istio 1.30.5 other totals are accepted and used as a ratio).
- How a weight becomes a per-request draw inside Envoy, and why cluster selection happens before endpoint load balancing.
- Running a canary as a sequence of applies, and rolling back in one — the reason the feature is worth the configuration.
- Why a merge patch on any list-valued field replaces the list rather than editing it.
- Measuring a statistical split honestly: what 10, 100 and 1000 samples can each tell you.
- Why traffic share and replica count are independent — the section's most testable idea.
- `mirror` as a sibling of `route`, a single destination whose response *and latency* are discarded.
- Why a mirror is never part of the weighted split, and that a full mirror doubles internal request volume.
- `mirrorPercentage` for sampling, and that omitting it means 100%, not 0%.
- Why the receiving proxy's access log is the only proof a mirror works, and what happened to the `-shadow` authority suffix older material describes.
- The three-state mirror diagnostic: policy absent, policy present but no endpoints, or working.
- That the mesh discards the mirrored response but not the work the shadow did — and what that means before mirroring anything with side effects.
- Reading `weightedClusters` and `requestMirrorPolicies` out of a live proxy.
- A second Service whose port is named `tcp`, so that a `tcp` route of a `VirtualService` applies, with `match.port` on the Service port.
- Why a TCP weight is drawn once per connection, why one reused connection stays on one pod, and why a TCP split is measured with fresh connections.
- Rolling a TCP service from 100/0 to 90/10, 50/50 and 0/100 with `kubectl patch`, and rolling it back, knowing that a change reaches new connections only.
- Telling a `tcp` route on a port named `http` from a working one: no weighted clusters in the listener, a host in the route table, and answers that ignore the weights.

---

## Modules In This Section

Work through the modules in this order. Each part teaches one idea. A graded lab comes right after the part it practises, and the last page of each module is a summary. The capstone lab at the end uses everything in the section at once.

### Shift Traffic With Weighted Routing

5 parts and 2 labs:

1. Split Traffic With Weighted Destinations
2. Weight Totals, Three-Way Splits And Missing Subsets
   - Lab: Split Traffic Three Ways With Weights Lab
3. Run A Canary Rollout And Roll It Back
4. Change Weights With A Patch And A Header Rule
5. Traffic Share, Replica Count And The Route Table
   - Lab: Run A Canary With A Header Rule Above The Split Lab
6. Summary

### Mirror Live Traffic To A Shadow Service

4 parts and 2 labs:

1. Add A Mirror Destination To An HTTP Route
2. Mirror Requests To A Failing Version
3. Find Mirrored Requests And Sample Them
   - Lab: Route To v1 And Mirror Every Request To v2 Lab
4. Diagnose A Silent Mirror And Plan For Side Effects
   - Lab: Troubleshoot A Mirror That Sends No Copies Lab
5. Summary

### Shift TCP Connections With Weights

3 parts and 2 labs:

1. Write A Weighted tcp Route
2. Per-Connection Weights, Connection Reuse And Counting
   - Lab: Split TCP Connections 80/20 Between Two Subsets Lab
3. Roll A TCP Service Forward And Back
   - Lab: Fix A TCP Split That Never Happens Lab
4. Summary

### Capstone

The section ends with two capstone labs that use everything in it: **Combine A Header Rule, A Weighted Canary And A Mirror Capstone Lab** and **Combine An HTTP Canary, A Mirror And A TCP Split Capstone Lab**.

---

<!-- astrona:playground:environment-explain -->