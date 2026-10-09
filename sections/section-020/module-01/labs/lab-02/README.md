---
estimated_duration: 15m
---

# Split Traffic Three Ways With Weights Lab

This graded lab checks that you can split the requests for one Service between three versions, in exact shares, and prove the split with live requests.

## What you will practise

A `VirtualService` is the Istio object that tells the sidecar proxies where to send requests for a host. One route in it can list several destinations, each with a `weight`: its share of the requests. The sidecar proxy of the sending pod makes one random pick for each request, so you only see the shares over many requests.

The `scout` Service runs three versions. A `DestinationRule` with the subsets `v1`, `v2` and `v3` already exists and is correct. A `VirtualService` sends every request to `v1`. Your task is to change that `VirtualService` so the requests split 60/30/10.

## What is in the lab

- A `kind` Kubernetes cluster with **Istio 1.30.5** installed with Helm, and `istioctl` ready to use.
- The namespace `starfleet` with `bridge`, `cargo`, `scout` v1, v2 and v3, `navcom`, and the `shuttle` client pod.
- The `scout` `DestinationRule` and a `VirtualService` that sends every `scout` request to `v1`.

## Running the lab

Start the cluster with the starting state in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-020/module-01/labs/lab-02
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-020/module-01/labs/lab-02
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-lab-020-01-02
```
