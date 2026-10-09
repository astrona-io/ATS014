# Set An Abort Window

Astronaut, a timeout is your signal's abort window: if no answer has come back by then, the signal is given up. In Istio it is one field on a flight plan. This part shows that there is no abort window until you set one, how to set it, and how to read the flight log to see that it fired.

The commands below need the two helpers from the module's landing page pasted into your terminal: `status_and_time` and `count_received`.

## No abort window by default

Istio sets **no** HTTP timeout unless you write one. A signal to a ship that takes 3 seconds to answer simply takes 3 seconds. A signal to a ship that never answers keeps waiting.

<!-- astrona:playground:renew -->

### Wait as long as it takes

Send one signal to the probe's `/delay/3` path, which waits 3 seconds before it answers:

```sh
status_and_time http://probe:8000/delay/3
```

You should see:

```text
200 3.023506s
```

Nothing stopped the slow signal. In a real system, those 3 seconds are 3 seconds of an open connection and a busy slot in every ship between the user and this one. If the ship hangs for good, so does everyone waiting on it.

## The `timeout` field

`timeout` sits on a rule of a `VirtualService`, next to `route`. Its value is a duration such as `500ms`, `0.5s`, `2s` or `1m`. Three facts decide how it behaves:

- **The sender's communications officer measures it.** The timeout lives in the sidecar proxy of the ship that **sends** the signal, not on the receiver. So it protects the sender even when the receiver never answers at all.
- **The sender gets a `504`.** When the time runs out, the sender's own sidecar cancels the signal and answers `504 Gateway Timeout` by itself. The receiver never answered.
- **It belongs to one rule.** One `VirtualService` can give different paths different abort windows: a long one for a slow report page, a short one for everything else.

### Give up after 1 second

Give every signal to the probe a 1-second abort window. Save this as `virtualservice-probe-timeout.yaml`:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: probe
  namespace: starfleet
spec:
  hosts:
  - probe
  http:
  - route:
    - destination:
        host: probe
    timeout: 1s
```

Apply it:

```sh
kubectl apply -f virtualservice-probe-timeout.yaml
```

Then send a slow signal and a fast one:

```sh
status_and_time http://probe:8000/delay/3
status_and_time http://probe:8000/delay/0
```

You should see:

```text
504 1.005886s
200 0.006127s
```

The slow signal is cut off after 1 second. The fast one is not affected. The time shown is the abort window, not the delay: that is how you tell a fired timeout from a slow success.

## Read the abort in the flight log

The status code tells you *that* a signal failed. The flight log tells you *who* failed it. Every sidecar writes one line per signal, with a short code called the **response flag** for anything that went wrong.

The flag for a fired abort window is **`UT`**, short for "upstream timeout". "Upstream" is the word Envoy, the program inside the sidecar, uses for the ship being called.

### Find the `UT` flag

Read the shuttle's flight log line for the slow signal:

```sh
kubectl logs -n starfleet deploy/shuttle -c istio-proxy --tail=3 | grep 'delay/3'
```

You should see a line like this one (trimmed):

```text
[2026-10-08T20:51:53.596Z] "GET /delay/3 HTTP/1.1" 504 UT response_timeout ... 1001 ... "probe:8000" ...
```

`504 UT` means the shuttle's own communications officer made the `504`, because the abort window ran out. `1001` is how long the signal took in milliseconds. A `504` **without** `UT` came from somewhere further away, which is worth knowing before you debug the wrong ship.

> [!TIP]
> Before you debug a `504`, read the flag. `UT` means "my own abort window fired": look at the timeout on the sender's flight plan, not at the receiver.

These flags come up again and again when signals fail. Keep this short list nearby:

| Flag | Meaning |
| --- | --- |
| `UT` | upstream timeout: an abort window fired |
| `DI` | delay injected: a simulation drill added a delay |
| `URX` | upstream retry limit exceeded: the re-sends are used up |
| `UO` | upstream overflow: too many signals waiting, so the hatch closed |
| `UH` | no healthy upstream: there is no ship to send to |
| `UF` | upstream connection failure: the connection could not be made |

## Common pitfalls

> [!WARNING]
> - **Assuming there is a default.** There is no route timeout unless you write one.
> - **Reading a `504` as coming from the receiver.** A timeout `504` is made by the sender's own sidecar. The `UT` flag tells them apart.
> - **Confusing it with a connection timeout.** `timeout` limits the whole exchange, connecting included. Making the connection is a separate setting on a `DestinationRule`: `connectionPool.tcp.connectTimeout`.
> - **Forgetting the app's own timeout.** An app can have its own limit. If it is shorter than Istio's, the app gives up first.

> *An abort window is measured by the sender's own communications officer. When it runs out, that sidecar answers `504` itself, and the flight log marks it `UT`.*
