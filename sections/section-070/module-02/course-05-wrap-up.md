# Wrap-Up: Mission Debrief

Well flown, astronaut. You have finished every part and every mission in this module. Before you move on, look back at what you learned, check yourself, and land the playground cleanly.

## What you learned

This module was about letting the communications officer (the sidecar proxy) seal signals to an outside planet, so the application can speak plain HTTP and the mesh can read every request.

**From [Why HTTPS Is Opaque](./course-01-why-https-is-opaque.md):**

- When the application seals its own signal, the proxy sees only the destination address, the SNI name, byte counts and whether the connection worked.
- The flight log shows `"- - -"` and status `0` for such a signal.
- Plain HTTP to a planet that is not on the star chart is also passed through as raw bytes. The proxy only reads HTTP on a port it knows carries HTTP.
- Only connection-level policy, like a TCP connection pool, works on a sealed stream.

**From [The Three Objects](./course-02-the-three-objects.md):**

- The `ServiceEntry` charts the outside host with **two** ports: `80` as `HTTP` and `443` as `HTTPS`.
- The `VirtualService` matches port `80` and routes to the same host on port `443`. Without a `DestinationRule`, that sends plain HTTP to the TLS port, and the server answers `400`.
- The `DestinationRule` puts `tls.mode: SIMPLE` and `sni` under `portLevelSettings` for port `443`. Then the open signal leaves sealed, and httpbin.org reports `"url": "https://httpbin.org/get"`.

**From [Two Ways To Break It](./course-03-two-ways-to-break-it.md):**

- A top-level `tls` in `trafficPolicy` seals every port, including port `80`. It hides behind the redirect, and any signal that stays on port `80` fails with `503 UF` and `WRONG_VERSION_NUMBER`.
- `istioctl proxy-config cluster ... --port 80` shows whether the open port carries a TLS transport socket.
- An application that still calls `https://` gets sealed twice, and `curl` fails with exit code `35`.

**From [Proving It, And Mutual TLS](./course-04-proving-it-and-mutual-tls.md):**

- Prove origination from both ends: the destination's view of the scheme, and `envoy.transport_sockets.tls` with the `sni` name on the port `443` cluster.
- Without `sni`, Istio sets `autoSni` and takes the name from the `Host` header.
- `IST0129` warns that no `caCertificates` are set. The proxy then uses its default trust store.
- Request-level features work again: a `timeout: 2s` turns a slow outside call into `504 UT`.
- `MUTUAL` adds a client certificate, by file path in the proxy container or by `credentialName` in the workload's own namespace. An egress gateway keeps that certificate in one place.

## Your missions

| Mission | What you proved | After part |
| --- | --- | --- |
| [Repair The Sealed Channel Lab](./labs/lab-02/question.md) | Fix a port redirect and a seal on the wrong port, so an open signal reaches a TLS-only vault | Two Ways To Break It |
| [Seal Signals To A Secure Planet Lab](./labs/lab-01/question.md) | Build the three objects from scratch for a TLS-only planet outside the mesh | Proving It, And Mutual TLS |

## Check yourself

Answer these without looking back. If one is hard, reread the part it comes from.

1. An application calls `https://api.example.com`. Which four things can its sidecar still see?
2. Why does a plain `http://` call to an outside host show `"- - -"` in the flight log before you write a `ServiceEntry`?
3. Which two ports does the `ServiceEntry` need for origination, and with which protocols?
4. You have the `ServiceEntry` and the `VirtualService`, but no `DestinationRule`. What does the outside server answer, and why?
5. Where must the `tls` block go in the `DestinationRule`, and what does a top-level `tls` break?
6. Which command shows whether the proxy seals connections to port `80` of a host, and what do you look for?
7. The application keeps calling `https://` after you switch origination on. What happens?
8. Name two places a `MUTUAL` client certificate can come from, and which namespace `credentialName` reads on a sidecar.

## Clean up the playground

Land everything before you leave. First see what is still running:

```sh
astrona list
```

Remove the playground. The command takes its **name**, not its folder path:

```sh
astrona destroy ats-014-playground-070-02
```

If `astrona list` also showed a mission, remove it the same way, for example:

```sh
astrona destroy ats-014-lab-070-02-02
```

Then check that everything is gone:

```sh
astrona list
```

```text
No astrona labs running.
```

You can start the playground again at any time with the `astrona run` command from the module's landing page. It always starts clean, so nothing you broke carries over.

> *The application speaks plain HTTP to its own proxy, and the proxy adds the seal on the one port that leaves the ship.*
