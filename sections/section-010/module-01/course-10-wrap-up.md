# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and every mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

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

**From [Put Your Rules In Order](./course-05-put-your-rules-in-order.md):**

- The proxy reads the `http` rules from the top and stops at the first rule that fits. There is no "most specific rule wins".
- A rule without `match` is the catch-all. It belongs last. Put it first and every rule below it is dead: `istioctl analyze` warns with `IST0130`.
- With no catch-all, a signal that fits no rule gets `404` with the flag `NR`, and `istioctl analyze` stays quiet.
- Keep one `VirtualService` per host.

**From [Put The Flight Plan On The Right Planet](./course-06-put-the-flight-plan-on-the-right-planet.md):**

- Short host names are filled in from the namespace of the **object** they appear in. A flight plan in the wrong namespace is accepted and does nothing.
- `kubectl get virtualservice -A` shows where an object lives. `istioctl analyze -n <namespace>` only checks the namespace you name; `IST0101 Referenced host not found` is the wrong-planet signature.
- Full names (FQDN) work from any namespace.

**From [Read The Flight Log And The Proxy's Orders](./course-07-read-the-flight-log-and-the-proxys-orders.md):**

- The sender's flight log shows the status code, the response flag, the chosen ship and the cluster for every signal.
- The flag tells the failures apart: `NR` (no route), `NC` (no cluster, a subset no `DestinationRule` defines, `IST0101`) and `UH` (a cluster with no pods, `IST0173`).
- Apply the `DestinationRule` before the `VirtualService` that uses it ("make before break").
- `istioctl proxy-status` lists every connected proxy; `istioctl proxy-config routes` shows the route table the proxy actually holds.

**From [Rewriting, Redirecting And Headers](./course-08-rewriting-redirecting-and-headers.md):**

- `redirect` answers the caller with a `3xx` and ends the request. No pod is reached. `redirect` and `route` cannot be on the same rule.
- `rewrite` changes the path or `Host` before the request is sent on. After a `prefix` match, only the matched prefix is replaced.
- `headers` can add, set or remove request and response headers, either for the whole rule or for one destination. `remove` is a plain list of names.
- `corsPolicy` lets the proxy answer browser preflight checks. CORS is a browser rule, not a security control.

**From [Routing Non-HTTP Traffic](./course-09-routing-non-http-traffic.md):**

- Istio decides a port's protocol from `appProtocol` first, then the port's `name`, and otherwise by protocol sniffing.
- An HTTP port named `tcp` turns off every HTTP feature for that Service, with no error. The service disappears from the route table.
- A `tcp` rule can only match on the connection, such as `port` and `sourceLabels`. Subsets and weights still work.
- A `tls` rule matches on the SNI name with `sniHosts`, because the proxy does not decrypt the traffic.
- TCP load balancing happens per connection, not per request.

## Your missions

You proved each skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Fix The Docking Instructions](./labs/lab-03/README.md) | Name The Ship Classes | find and fix a subset that selects no ship |
| [Route Requests By Header, URI And Query Parameter](./labs/lab-01/README.md) | Put Your Rules In Order | route by header, path and query, with every rule reachable |
| [Find Out Why The Flight Plan Does Nothing](./labs/lab-04/README.md) | Read The Flight Log And The Proxy's Orders | repair a flight plan with more than one hidden fault |
| [Reshape A Request](./labs/lab-02/README.md) | Rewriting, Redirecting And Headers | redirect, rewrite, change headers and answer browser checks |
| [Bring HTTP Routing Back](./labs/lab-05/README.md) | Routing Non-HTTP Traffic | find the port name that switched HTTP routing off |

If you skipped one, go back to it now. Each mission is short, and the exam asks for exactly these skills.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. You apply a <code>DestinationRule</code> with subsets <code>v1</code>, <code>v2</code> and <code>v3</code>. Does traffic change?</summary>

No. The proxy gets new clusters, one per subset, but nothing uses them yet. Traffic only moves when a `VirtualService` route names a subset.
</details>

<details>
<summary>2. A signal carries <code>End-User: Jason</code>. Your rule says <code>end-user</code> with <code>exact: jason</code>. Does it match?</summary>

No. The header **name** matches, because names ignore upper and lower case. The **value** does not: `exact` compares letter for letter, and `Jason` is not `jason`. Use `regex: "(?i)jason"` if the value must ignore case.
</details>

<details>
<summary>3. A <code>match</code> has a <code>headers</code> condition and a <code>uri</code> condition in the same <code>-</code> item. When does the rule fire?</summary>

Only when both are true. Conditions inside one item are combined with AND. Put a `-` in front of `uri` and they become two items, combined with OR.
</details>

<details>
<summary>4. Your catch-all rule is first in the list, and the jason rule is second. What happens to jason?</summary>

jason gets the catch-all destination. The proxy stops at the first rule that fits, and a rule without `match` fits everything. `istioctl analyze` warns with `IST0130`.
</details>

<details>
<summary>5. <code>kubectl</code> accepted your <code>VirtualService</code>, but nothing changes. <code>istioctl analyze -n starfleet</code> is clean. What do you check first?</summary>

Where the object lives: `kubectl get virtualservice -A`. A short host name is filled in from the object's own namespace, so a flight plan on the wrong planet describes a beacon that does not exist. `istioctl analyze -n <that namespace>`, or `-A`, reports it as `IST0101 Referenced host not found`.
</details>

<details>
<summary>6. The sender gets a bare <code>503</code>. The flight log shows <code>NC</code>. Where do you look?</summary>

At the subset name and the `DestinationRule`. `NC` means the route names a subset with no cluster: a typo in `subset:`, or a `DestinationRule` that is missing, in another namespace, or not pushed yet. `UH` would mean the subset exists but selects no pods.
</details>

<details>
<summary>7. Every <code>http</code> rule for one Service stopped working, with no error anywhere. What do you suspect?</summary>

The Service port's protocol. A port named `tcp`, or with `appProtocol: tcp`, turns off every HTTP feature for that Service. The Service disappears from `istioctl proxy-config routes`, and `istioctl analyze` stays clean.
</details>

<details>
<summary>8. Which of <code>redirect</code>, <code>rewrite</code>, <code>headers</code> and <code>corsPolicy</code> ends the signal's journey at the proxy?</summary>

`redirect`. The proxy answers the sender itself, and the signal never reaches a ship. The others change the signal or the answer on its way.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-014-playground-010-01
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-014-lab-010-01-05
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with the `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

> *Two objects steer every signal in the mesh: the `DestinationRule` names the ship classes, and the `VirtualService` decides which signals fly to which class.*
