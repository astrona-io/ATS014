# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and every mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about putting the TLS lock on at the departure gate: your ships send plain `http://`, and the gate seals the signal, and shows a client certificate when a partner asks for one.

**From [The Five-Step Chain](./course-01-the-five-step-chain.md):**

- Five objects, one job each: the `ServiceEntry` (ports `80` and `443`), the `Gateway` on port `80`, the `DestinationRule` with the empty subset of the gate's Service, the two-stage `VirtualService`, and the TLS `DestinationRule` for the outside host.
- The gate listens on port `80` and sends on port `443`. The two numbers are two directions.
- With four objects, the route works but nothing seals the signal: `httpbin.org` answers `400 The plain HTTP request was sent to HTTPS port`.

**From [Originate TLS At The Gate](./course-02-originate-tls-at-the-gate.md):**

- The TLS settings go in a `DestinationRule` for the **outside host**, under `portLevelSettings` for port `443`, with `tls.mode: SIMPLE` and `sni`.
- The gate follows it, because the gate is the proxy that calls that host. Its flight log shows a readable request, sent on to port `443`.
- Stage 2 on port `80` skips the lock. Against a server that also speaks plain HTTP, the call still returns `200`, unsealed.

**From [Where The `DestinationRule` Attaches](./course-03-where-the-destinationrule-attaches.md):**

- Count the `transportSocket` in each proxy's cluster for the host: the proxy with TLS equipment is the one that seals.
- A `DestinationRule` is visible to the whole mesh by default, so every sidecar gets the TLS settings too. `exportTo: [istio-egress]` keeps them on the gate: `gate: 1`, `shuttle: 0`.
- TLS settings on the gate's own Service go to the sidecar, which then tries TLS with the gate: `503 URX,UF` with `WRONG_VERSION_NUMBER`.
- Repair order: the gate's log, its upstream port, its `transportSocket`, then the `https://` the outside host reports.

**From [A Partner That Checks IDs](./course-04-a-partner-that-checks-ids.md):**

- A TLS handshake can check an ID in both directions: the server's certificate, and a client certificate when the server asks for it.
- `SIMPLE` checks the server against the public authorities. A privately signed partner fails with `CERTIFICATE_VERIFY_FAILED`.
- `insecureSkipVerify: true` is a test step, never the fix. Without a client certificate, the partner answers `400 No required SSL certificate was sent`.

**From [Hand The Gate Its Keys](./course-05-hand-the-gate-its-keys.md):**

- `tls.mode: MUTUAL` with `credentialName` names a `Secret` with `tls.crt`, `tls.key` and `ca.crt`. Mission control sends it to the proxy over SDS.
- The `Secret` is read from the namespace of the proxy that uses it: the gate's. In the wrong namespace you get `503 URX,UF` with `Secret_is_not_supplied_by_SDS`.
- `istioctl proxy-config secret` shows the keys as `WARMING`, and the `istiod` log says `secret istio-egress/partner-client-cert not found`.
- At the gate, the keys live in one place, and no calling ship holds them. The price is an extra hop, more objects, and a gate every signal depends on.

## Your missions

You proved each skill in a graded mission, right after the part that taught it:

| Mission | After the part | What you proved |
| --- | --- | --- |
| [Lock The Signal At The Departure Gate](./labs/lab-01/README.md) | Where The `DestinationRule` Attaches | build the five objects and prove the gate, not the sidecar, seals the signal |
| [Open The Partner's Locked Door](./labs/lab-02/README.md) | Hand The Gate Its Keys | find why a mutual TLS handshake at the gate fails, and fix every cause |

If you skipped one, go back to it now. Each mission is short, and the exam asks for exactly these skills.

## Check yourself

Try to answer each question before you open the answer.

<details>
<summary>1. The <code>Gateway</code> opens port 80, but stage 2 routes to port 443. Is that a mistake?</summary>

No. The gate listens on port `80`, where the plain signal from the sidecar arrives, and sends on port `443`, where the outside host expects TLS. The two numbers are two directions.
</details>

<details>
<summary>2. Which host does the TLS <code>DestinationRule</code> name, and why?</summary>

The outside host, for example `httpbin.org`. A `DestinationRule` is followed by the proxy that calls the host it names. The gate calls the outside host, so the gate puts the lock on.
</details>

<details>
<summary>3. You put the TLS settings on the gate's own Service instead. What happens?</summary>

The shuttle's sidecar calls the gate's Service, so the sidecar follows the rule and starts a TLS handshake with the gate's port `80`. The gate does not expect it there: `503 URX,UF` with `WRONG_VERSION_NUMBER`.
</details>

<details>
<summary>4. Stage 2 routes to port 80 of <code>httpbin.org</code>, and the call returns 200. Is everything fine?</summary>

No. The TLS settings only cover port `443`, so the signal leaves unsealed. `httpbin.org` also answers plain HTTP, so nothing fails. The `url` field shows `http://`, and the gate's flight log shows upstream port `80`.
</details>

<details>
<summary>5. Both the gate and the shuttle show a <code>transportSocket</code> for the outside host. What is missing?</summary>

`exportTo`. Without it, the `DestinationRule` goes to every proxy in the mesh. Add `exportTo: [istio-egress]`, the gate's namespace, and only the gate keeps the TLS settings.
</details>

<details>
<summary>6. The gate's flight log shows <code>CERTIFICATE_VERIFY_FAILED</code>. What does it mean?</summary>

The gate could not check the server's ID: the authority that signed it is not in the gate's trusted list. For a partner with a private authority, give the gate that authority, as `ca.crt` in the `credentialName` `Secret`.
</details>

<details>
<summary>7. With <code>MUTUAL</code> and <code>credentialName</code>, the gate logs <code>Secret_is_not_supplied_by_SDS</code>. Where do you look first?</summary>

At the namespace of the `Secret`. It must be in the gate's namespace, `istio-egress` here. `istioctl proxy-config secret` on the gate shows the keys as `WARMING`, and the `istiod` log names the namespace it looked in.
</details>

<details>
<summary>8. Name one reason to seal at the gate and one reason not to.</summary>

For: the client certificate lives in one `Secret` on the gate's planet, and no calling ship holds it. Against: an extra hop, five objects instead of three, and one gate that every outgoing signal depends on.
</details>

## Clean up the playground

Your playground is a whole Kubernetes cluster running on your machine. When you are done with this module, remove it, and any mission that is still running.

First, see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-014-playground-080-02
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-014-lab-080-02-02
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with the `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

> *Your ships send plain signals. The departure gate puts the lock on, and holds the keys, so no ship has to.*
