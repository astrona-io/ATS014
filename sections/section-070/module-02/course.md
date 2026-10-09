# TLS Origination For External Services

Astronaut, a planet from another solar system becomes part of the star chart as soon as you write a `ServiceEntry` for it. If its signals are plain HTTP, the ship's communications officer (the sidecar proxy) can read them, so timeouts, retries and routing rules work for it.

Most real outside services only speak HTTPS. When an application calls `https://api.example.com/`, the crew seals the signal before the communications officer ever sees it. The proxy sees a stream of encrypted bytes and nothing else: no method, no path, no headers, no status code. Its flight log gets one line saying that bytes moved.

**TLS origination** moves the seal. TLS (Transport Layer Security) is the encryption behind HTTPS. With origination, the application sends a plain HTTP signal to its own proxy. The proxy reads it, applies your rules, and then **the proxy** seals it with TLS before it leaves the ship. The signal on the wire is still HTTPS, but now the mesh can see and steer every request.

> TLS origination lets the application speak plain HTTP while the sidecar seals the connection with TLS.

## Learning objectives

After this module you can:

- Explain why the mesh cannot see an application's own HTTPS calls.
- Build the three objects TLS origination needs, and say what each one does.
- Put `tls.mode: SIMPLE` under `portLevelSettings` for the right port, and explain what breaks otherwise.
- Explain what `sni` is and why you set it.
- Prove that origination happened, from the outside service's own view and from the proxy.
- Describe what changes for `MUTUAL` TLS, and where the client certificate has to live.

## What you need first

You should know three Istio objects and what each one does:

- A **`ServiceEntry`** adds a planet from another solar system to the star chart, so the mesh knows its name and ports.
- A **`VirtualService`** is the flight plan: it decides where a signal goes, based on what it carries.
- A **`DestinationRule`** holds the docking instructions: how a proxy connects to a destination, including TLS.

TLS origination is those three objects working together. None of them is new; only the way they combine is.

## Your playground

The playground is a `kind` cluster (a training solar system in the simulator) with **Istio 1.30.5** installed. The planet `starfleet` holds the `shuttle`, a client with `curl` that sends every test signal, and the `probe`, an echo service. Every pod in `starfleet` has its sidecar, and every proxy writes a flight log (access log). No `ServiceEntry`, `VirtualService` or `DestinationRule` exists yet, and the mesh is at its `ALLOW_ANY` default, so ships may signal any outside planet.

The commands call `httpbin.org` on the internet. **Without outbound internet access you will see network errors instead of mesh behaviour.** The graded missions do not need the internet: their TLS service runs inside the cluster.

Launch your playground now, and keep it running next to you while you read the parts:

<!-- astrona:playground -->

## The parts

1. **[Why HTTPS Is Opaque](./course-01-why-https-is-opaque.md)**: what the proxy can and cannot see in an encrypted signal, and what that costs you.
2. **[The Three Objects](./course-02-the-three-objects.md)**: the `ServiceEntry` with two ports, the port redirect, and the `DestinationRule` that seals the signal, built one at a time.
3. **[Two Ways To Break It](./course-03-two-ways-to-break-it.md)**: the seal on every port, and an application that still calls `https://`. Then the mission *Repair The Sealed Channel Lab*.
4. **[Proving It, And Mutual TLS](./course-04-proving-it-and-mutual-tls.md)**: evidence from the destination and from the proxy, a timeout on the outside call, and what `MUTUAL` changes. Then the mission *Seal Signals To A Secure Planet Lab*.
5. **[Wrap-Up](./course-05-wrap-up.md)**: what you learned, your missions, and questions to check yourself.
