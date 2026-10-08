# Running A Rollout

A **canary release** moves users to a new version a little at a time. First a small share of users get it, then more, then everyone. If something goes wrong, you move everyone back in one step. Think of it as a test flight: a few signals go to the new ship class first. If the new ships hold up, the rest of the fleet follows. If they do not, every signal goes back to the proven ships.

Istio has no special machinery for this. A canary is the `VirtualService` from Part 1, applied a few times with new numbers. This part is about doing that safely: how the change works, how fast it lands, and how to measure the result without fooling yourself.

## Measuring a random split

Part 1 showed that each request is a separate random roll — every signal gets its own coin toss. So a small sample tells you almost nothing.

At a true 80/20 split, ten requests that all land on v1 are normal. It happens about one time in ten. Deciding from that that the weights are broken, and "fixing" a configuration that was correct, is the most common mistake on this topic.

A rough guide for reading your own tests:

| Sample size | What you can conclude at a set 80/20 |
| --- | --- |
| 10 | almost nothing; 10/0 and 6/4 are both normal |
| 100 | the split is in the right area; expect roughly 75–85 |
| 1000 | the number is close to the weight, within a percent or two |

Use 100 requests as your working minimum, and expect a few percent of wobble even then. If a task says "confirm the split", it means over enough requests to mean something.

## Moving the rollout forward

Each step of the rollout is the **same** VirtualService, `scout`, with new numbers. Because the name and namespace stay the same, every `kubectl apply` replaces the split before it. You do not delete anything between steps.

When the canary looks healthy, you raise its share. At 100, the old version gets nothing.

> [!TIP]
> **Try it – 50/50, then 100% v3**
>
> Start from the 80/20 canary in Part 1. Write step 2 and step 3 to files, then apply them one at a time:
>
> ```sh
> cat > virtualservice-scout-50-50.yaml <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: scout
>   namespace: starfleet
> spec:
>   hosts:
>   - scout
>   http:
>   - route:
>     - destination:
>         host: scout
>         subset: v1
>       weight: 50
>     - destination:
>         host: scout
>         subset: v3
>       weight: 50
> EOF
> cat > virtualservice-scout-v3.yaml <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: scout
>   namespace: starfleet
> spec:
>   hosts:
>   - scout
>   http:
>   - route:
>     - destination:
>         host: scout
>         subset: v3
> EOF
> kubectl apply -f virtualservice-scout-50-50.yaml
> count_versions
> kubectl apply -f virtualservice-scout-v3.yaml
> count_versions
> ```
>
> Expect roughly 10/10 first (a test run gave `11 scout-v1` and `9 scout-v3`), then `20 scout-v3`. You only changed numbers in the route. No pod was scaled or restarted. Step 3 has one destination, so it needs no `weight`.

## How fast a change lands

The change takes effect as fast as `istiod` can push it: a second or two on a small cluster. `istiod` is mission control. It radios the new flight plan to every sidecar without the ships having to land, so no pod restarts and no Deployment is touched. The application does not notice anything happened.

That is what makes weighted routing worth the configuration. The interesting number is not how fast you can move traffic *to* a new version. It is how fast you can move it *away*:

```mermaid
flowchart LR
    A["100 / 0"] --> B["80 / 20"]
    B --> C["50 / 50"]
    C --> D["0 / 100"]
    D -->|"one apply, seconds"| A
```

Forward is a rollout and backward is a rollback. They are the same operation with different numbers, and no step recreates a pod.

Rollback needs no special procedure. It is the old numbers, applied again. Compare that with a Deployment rollback, which recreates pods and takes as long as your readiness probes allow.

> [!TIP]
> **Try it – roll back**
>
> ```sh
> cat > virtualservice-scout-v1.yaml <<'EOF'
> apiVersion: networking.istio.io/v1
> kind: VirtualService
> metadata:
>   name: scout
>   namespace: starfleet
> spec:
>   hosts:
>   - scout
>   http:
>   - route:
>     - destination:
>         host: scout
>         subset: v1
> EOF
> kubectl apply -f virtualservice-scout-v1.yaml
> count_versions
> ```
>
> Expect `20 scout-v1`. One apply undid the whole rollout, within seconds.

## Changing weights with a patch

`kubectl apply` with the complete object is the safest way to change the numbers. A rollout script often uses a merge patch instead:

```sh
kubectl -n starfleet patch virtualservice scout --type merge -p '
spec:
  http:
    - route:
        - destination:
            host: scout
            subset: v1
          weight: 90
        - destination:
            host: scout
            subset: v3
          weight: 10'
```

Note that the patch restates the **whole** `http` list, including the parts that did not change. This is required. A JSON merge patch **replaces** a list in one piece. It does not merge it item by item, because there is no key it could use to match the items up. The same trap applies to `egress[].hosts` in section 010's `Sidecar`, and to every other list in every Istio object.

The practical rule: **for any list field, restate the whole list, or use `kubectl apply` with the complete object.** A `--type json` patch with an index path works, but it breaks easily, because the index moves the next time someone adds a rule.

## A rule above the weights changes who is counted

Rules are still checked from the top down, and the first match wins. So a header match placed **above** your weighted rule takes those requests out of the split entirely.

This is a common real rollout. Your own testers always use the newest version, and a small share of real users try the next one. Here, jason always gets v3, and everyone else is split 90% v1 and 10% v2:

```yaml
  http:
  - match:                 # testers: always v3
    - headers:
        end-user:
          exact: jason
    route:
    - destination:
        host: scout
        subset: v3
  - route:                 # everyone else: the canary split
    - destination:
        host: scout
        subset: v1
      weight: 90
    - destination:
        host: scout
        subset: v2
      weight: 10
```

The first rule matches jason, so the weights never apply to him. Everyone else falls through to the second rule.

> [!TIP]
> **Try it – testers on v3, everyone else 90/10**
>
> Write the full VirtualService above (with `apiVersion`, `metadata` and `hosts: [scout]`) to `virtualservice-scout.yaml`, apply it, then count:
>
> ```sh
> kubectl apply -f virtualservice-scout.yaml
> count_versions 5 -H "end-user: jason"
> count_versions 30
> ```
>
> Expect something like:
>
> ```text
>    5 scout-v3
>   27 scout-v1
>    3 scout-v2
> ```
>
> jason never enters the split. The 30 other requests divide roughly 90/10.

This pattern is useful, and it is also a trap. If you forget the first rule is there, your measured split will not match the weights, because the requests carrying that header were never part of the group the weights apply to.

The weights add up to 100 **inside their own route list**. Each `http` rule is counted on its own. There is no shared budget across rules.

## Common pitfalls

> [!WARNING]
> **Deciding anything from ten requests.** At a true 80/20, ten requests landing 10/0 happens about one time in ten. Count 100 before you trust a number.
>
> **Deleting the VirtualService between rollout steps.** You do not need to. The same name in the same namespace means `kubectl apply` replaces it in place.
>
> **Expecting a merge patch to edit one route item.** It replaces the whole `http` list. Restate it, or use `kubectl apply` with the complete object.
>
> **Using `--type json` with a list index.** It works, and it breaks the next time someone adds a rule.
>
> **Forgetting a match rule above the weighted one.** Those requests never enter the split, so you are measuring a different group than you think.
>
> **Treating a rollback as a separate procedure.** It is the old numbers, applied again.

> *A weight change is one apply and lands in seconds. That makes the rollback, not the rollout, the reason to use it.*
