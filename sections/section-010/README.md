# Configuring Routing Within A Service Mesh

Welcome to your first steering mission, astronaut. In this section you learn to decide where every signal in the fleet flies.

A Kubernetes Service is a beacon: one call sign that a whole group of ships (pods) answers to. It shares the signals out between the ships, but it cannot read a signal, and it cannot be told that some signals matter more than others. Istio's answer is a communications officer (a proxy) on every ship, plus two objects that tell that officer what to do with the signals it sees. A `VirtualService` is the flight plan. A `DestinationRule` is the docking instructions.

This section covers both ends of that idea. First, it follows the signal’s journey: how a rule matches, which destination it selects, what else a matched rule can do to it, and how to prove the rule reached the proxy.

Then it looks at the opposite direction. It asks how much of the star chart each ship should carry, and how to reduce the full service registry to only the hosts a workload actually needs to communicate with.

Finally, it covers timing: the order in which these objects should be applied and removed so no signal ever points to something that does not exist yet — “make before break” — along with the defaults Istio uses when you leave the configuration unspecified.

---

## What You Will Master

- The division of labour between `VirtualService` (where a request goes) and `DestinationRule` (what the named destinations mean).
- How `istiod` turns the registry into Envoy clusters, and how to read the `outbound|port|subset|host` cluster name.
- Defining subsets over pod labels, and why a subset whose labels match nothing is legal configuration and a later 503.
- Matching on `headers`, `uri`, `queryParams` and `method`, with the `exact` / `prefix` / `regex` forms and RE2's limits.
- The AND/OR rule: conditions inside one `-` entry are ANDed, separate entries are ORed.
- Top-down first-match evaluation, and why a default route placed first silently kills everything below it.
- Short host names resolving relative to the object's own namespace — and the failures that causes.
- The two failure signatures: wrong-destination-no-error versus bare 503, and which half of the module each points at.
- What a sidecar is programmed with by default, how xDS (the discovery services `istiod` uses to send proxy settings) delivers it, and why the cost scales with the cluster.
- Narrowing with `Sidecar` and `egress[].hosts` in `<namespace>/<host>` form, and why `istio-system/*` is boilerplate.
- `Sidecar` precedence: selective beats namespace default beats root namespace, and each replaces rather than merges.
- Why `Sidecar` is a configuration control rather than a security boundary, and what to combine it with.
- Using `redirect`, `rewrite`, `headers` and `corsPolicy` on a matched rule, and which of them ends the request.
- How a Service port's name or `appProtocol` decides the protocol — and how a port declared as `tcp` silently turns off every HTTP feature.
- What a `tcp` or `tls` rule can match on when there is no request to read, and what per-connection balancing costs you.
- Reading a proxy's live configuration with `istioctl proxy-config routes`, `cluster`, `endpoints` and `listener`.
- The order to apply and remove `ServiceEntry`, `DestinationRule`, `Gateway` and `VirtualService` ("make before break"), and Istio's defaults for timeouts, retries, load balancing and outbound traffic.

---

## Modules In This Section

Work through the modules in this order. Each part teaches one idea. A mission (a graded lab) comes right after the part it practises, and the last page of each module is a wrap-up. The capstone at the end uses everything in the section at once.

### [Route Requests Within The Mesh](module-01/course.md)

9 parts and 5 missions:

1. [Where Signals Go Today](module-01/course-01-where-signals-go-today.md)
2. [Name The Ship Classes](module-01/course-02-name-the-ship-classes.md)
   - Mission: [Fix The Docking Instructions Lab](module-01/labs/lab-03/question.md)
3. [Write A Flight Plan](module-01/course-03-write-a-flight-plan.md)
4. [Match Exactly What You Mean](module-01/course-04-match-exactly-what-you-mean.md)
5. [Put Your Rules In Order](module-01/course-05-put-your-rules-in-order.md)
   - Mission: [Route Requests By Header, URI And Query Parameter Lab](module-01/labs/lab-01/question.md)
6. [Put The Flight Plan On The Right Planet](module-01/course-06-put-the-flight-plan-on-the-right-planet.md)
7. [Read The Flight Log And The Proxy's Orders](module-01/course-07-read-the-flight-log-and-the-proxys-orders.md)
   - Mission: [Find Out Why The Flight Plan Does Nothing Lab](module-01/labs/lab-04/question.md)
8. [Rewriting, Redirecting And Headers](module-01/course-08-rewriting-redirecting-and-headers.md)
   - Mission: [Reshape A Request Lab](module-01/labs/lab-02/question.md)
9. [Routing Non-HTTP Traffic](module-01/course-09-routing-non-http-traffic.md)
   - Mission: [Bring HTTP Routing Back Lab](module-01/labs/lab-05/question.md)
10. [Wrap-Up: Mission Debrief](module-01/course-10-wrap-up.md)

### [Scope Proxy Configuration With The Sidecar Resource](module-02/course.md)

4 parts and 2 missions:

1. [Every Ship Carries The Whole Star Chart](module-02/course-01-every-ship-carries-the-whole-star-chart.md)
2. [Give A Ship A Smaller Star Chart](module-02/course-02-give-a-ship-a-smaller-star-chart.md)
   - Mission: [Scope Proxy Configuration With The Sidecar Resource Lab](module-02/labs/lab-01/question.md)
3. [Which Star Chart A Ship Uses](module-02/course-03-which-star-chart-a-ship-uses.md)
   - Mission: [Fix One Ship's Star Chart Lab](module-02/labs/lab-02/question.md)
4. [A Star Chart Is Not A Shield](module-02/course-04-a-star-chart-is-not-a-shield.md)
5. [Wrap-Up: Mission Debrief](module-02/course-05-wrap-up.md)

### [Apply And Remove Traffic Rules Safely](module-03/course.md)

2 parts and 1 mission:

1. [The Order To Apply And Remove Rules](module-03/course-01-the-order-to-apply-and-remove-rules.md)
   - Mission: [Retire A Ship Class Safely Lab](module-03/labs/lab-01/question.md)
2. [One Object Per Host, And The Defaults](module-03/course-02-one-object-per-host-and-the-defaults.md)
3. [Wrap-Up: Mission Debrief](module-03/course-03-wrap-up.md)

### Capstone

Your final mission for this section: **[Route And Scope A Storefront Capstone Lab](capstone/labs/lab-01/README.md)**.

---

<!-- astrona:playground:environment-explain -->
