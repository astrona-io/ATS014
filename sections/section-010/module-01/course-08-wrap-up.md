# Wrap-Up: Mission Debrief

Well flown, astronaut. Before you take this module's two graded missions, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about the two objects that steer signals inside the mesh: the `DestinationRule` (the docking instructions) and the `VirtualService` (the flight plan).

**From [Where Signals Go Today](./course-01-where-signals-go-today.md):**

- A Service selects its ships with one label, here `app=scout`. Every scout version carries it, so all three answer the beacon. The `version` label is ignored.
- Without routing rules, `count_versions` gives a random mix of v1, v2 and v3.
- The routing choice is made by the communications officer of the ship that **sends** the signal. The shuttle's flight log shows the chosen address and the `outbound|9080||scout...` cluster; the receiver only logs `inbound`.
- To debug a wrong answer, look at the caller's proxy, not the ship that answered.

**From [Name The Ship Classes](./course-02-name-the-ship-classes.md):**

- A `DestinationRule` gives names to groups of pods. Each subset selects pods by their **pod labels**, such as `version: v1`. The subset name itself is your choice.
- `spec.host` is the Service the rule is about. `metadata.name` is only the object's name, and nothing routes by it.
- Each subset becomes its own Envoy cluster, such as `outbound|9080|v2|scout.starfleet.svc.cluster.local`. The cluster without a subset stays.
- Applying a `DestinationRule` alone moves no traffic. Subsets are names, not behaviour.
- A subset whose labels match no pod is not an error. It becomes an empty cluster, and signals sent there fail with `503 UH`. `istioctl analyze` reports it as `IST0173`.

**From [Write A Flight Plan](./course-03-write-a-flight-plan.md):**

- `spec.hosts` is the name on the incoming request. `destination.host` is where the proxy sends it on to.
- The rules go to the **caller's** proxy. The matching happens in the pod that sends the request.
- A rule has an optional `match` (which signals) and a required `route` (where they go). A rule without `match` matches everything.
- A match can look at `headers`, `uri`, `queryParams`, `method` and `sourceLabels`. `uri` does not include the query string after `?`.
- Header names ignore upper and lower case. Header values do not.

**From [Match Exactly What You Mean](./course-04-match-exactly-what-you-mean.md):**

- `exact` matches letter for letter, `prefix` matches the start of the text, and `regex` (RE2) must fit the **whole** value.
- `prefix` does not care about `/`: `prefix: "/reviews"` also matches `/reviewsXYZ`.
- Quote every header and query value. Unquoted `true` is a yes/no value in YAML, and Istio rejects the object.
- Conditions inside one `-` item are combined with AND. Separate `-` items are combined with OR.
- The compiled route in `istioctl proxy-config routes` shows how the proxy really reads your match.

**From [Evaluation Order, Name Resolution And Proof](./course-05-evaluation-order-and-proof.md):**

- The proxy reads the `http` rules from the top and stops at the first rule that fits. There is no "most specific rule wins".
- A rule without `match` is the catch-all. It belongs last. Put it first and every rule below it is dead: `istioctl analyze` warns with `IST0130`.
- With no catch-all, a request that matches no rule gets `404` with the flag `NR`, and `istioctl analyze` stays quiet.
- Short host names are filled in from the namespace of the **object** they appear in. Use the full name (FQDN) when the object and the service live in different namespaces.
- A route to a subset that no `DestinationRule` defines gives `503 NC`. `istioctl analyze` reports it as `IST0101`.
- `istioctl proxy-config routes` shows the route table the proxy actually holds.

**From [Rewriting, Redirecting And Headers](./course-06-rewriting-redirecting-and-headers.md):**

- `redirect` answers the caller with a `3xx` and ends the request. No pod is reached. `redirect` and `route` cannot be on the same rule.
- `rewrite` changes the path or `Host` before the request is sent on. After a `prefix` match, only the matched prefix is replaced.
- `headers` can add, set or remove request and response headers, either for the whole rule or for one destination. `remove` is a plain list of names.
- `corsPolicy` lets the proxy answer browser preflight checks. CORS is a browser rule, not a security control.

**From [Routing Non-HTTP Traffic](./course-07-routing-non-http-traffic.md):**

- Istio decides a port's protocol from `appProtocol` first, then the port's `name`, and otherwise by protocol sniffing.
- An HTTP port named `tcp` turns off every HTTP feature for that Service, with no error. The service disappears from the route table.
- A `tcp` rule can only match on the connection, such as `port` and `sourceLabels`. Subsets and weights still work.
- A `tls` rule matches on the SNI name with `sniHosts`, because the proxy does not decrypt the traffic.
- TCP load balancing happens per connection, not per request.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. You apply a <code>DestinationRule</code> with subsets <code>v1</code>, <code>v2</code> and <code>v3</code>. Does traffic change?</summary>

No. The proxy gets new clusters, one per subset, but nothing uses them yet. Traffic only moves when a `VirtualService` route names a subset.
</details>

<details>
<summary>2. A <code>match</code> has a <code>headers</code> condition and a <code>uri</code> condition in the same <code>-</code> item. When does the rule fire?</summary>

Only when both are true. Conditions inside one item are combined with AND. Put a `-` in front of `uri` and they become two items, combined with OR.
</details>

<details>
<summary>3. Your catch-all rule is first in the list, and the jason rule is second. What happens to jason?</summary>

Jason gets the catch-all destination. The proxy stops at the first rule that fits, and a rule without `match` fits everything. `istioctl analyze` warns with `IST0130`.
</details>

<details>
<summary>4. The caller gets a bare <code>503</code>. The access log shows <code>NC</code>. Where do you look?</summary>

At the subset name and the `DestinationRule`. `NC` means the route names a subset with no cluster: a typo in `subset:`, or a `DestinationRule` that is missing, in another namespace, or not pushed yet. `UH` would mean the subset exists but selects no pods.
</details>

<details>
<summary>5. Which of <code>redirect</code>, <code>rewrite</code>, <code>headers</code> and <code>corsPolicy</code> ends the request at the proxy?</summary>

`redirect`. The proxy answers the caller itself, and the request never reaches a pod. The others change the request or the response on its way.
</details>

## Clean up the playground

The playground is a whole Kubernetes cluster running on your machine. Each graded lab builds its own, separate cluster. Remove the playground first, so the two do not compete for memory and you cannot send a command to the wrong solar system by accident.

**Step 1.** Destroy the playground. The command takes the playground's **name**, not its folder path:

```sh
astrona destroy ats-014-playground-010-01
```

**Step 2.** Check that it is gone:

```sh
astrona list
```

`ats-014-playground-010-01` should no longer be in the list.

> [!TIP]
> You can start the playground again at any time with the same `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

## Your next missions

This module has two graded labs. Take them in order, and run only one at a time.

**Mission 1: [Route Requests By Header, URI And Query Parameter](./labs/lab-01/README.md).** Split one Service into subsets, and route single requests by header, URI prefix and query parameter. Read the task in [`question.md`](./labs/lab-01/question.md).

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-01/labs/lab-01
```

When you think you are done, send it for grading:

```sh
astrona submit -c sections/section-010/module-01/labs/lab-01
```

**Mission 2: [Reshape A Request](./labs/lab-02/README.md).** Use a redirect, a rewrite, header changes and a CORS policy on matched rules. Read the task in [`question.md`](./labs/lab-02/question.md). Destroy the first lab before you start this one (`astrona destroy ats-014-lab-010-01`).

```sh
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/module-01/labs/lab-02
```

```sh
astrona submit -c sections/section-010/module-01/labs/lab-02
```

Try each one on your own first. Keep [Evaluation Order, Name Resolution And Proof](./course-05-evaluation-order-and-proof.md) open next to you: most failed submissions come down to rule order or a host name.
