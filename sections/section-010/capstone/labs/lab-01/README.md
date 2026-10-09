# Route With Subsets And Scope Proxies With A Sidecar Capstone Lab

This graded capstone lab combines two skills into one specification, on a mesh with no traffic configuration at all. The first skill is routing: subsets in a `DestinationRule`, and header, path and query matches in a `VirtualService`. The second skill is scoping: a `Sidecar` resource that limits which hosts the proxies of a namespace hold configuration for.

The two halves interact, and that is the point. A `Sidecar` that is too narrow removes the clusters that your routing needs, and the requests then fail the same way as requests to a subset that does not exist.

The lab uses its own small app (`catalog`, `shopper`, `pricing` and `coldstore` in the `storefront`, `partners` and `archive` namespaces), not the Starfleet. There is no step-by-step guide until you have tried it. Work from the specification.

## Running the lab

Start the cluster with the starting state in place:

```bash
astrona run --git git@github.com:astrona-io/ATS014.git -c sections/section-010/capstone/labs/lab-01
```

When you think you have finished, send it for grading:

```bash
astrona submit -c sections/section-010/capstone/labs/lab-01
```

When you are done, remove the lab:

```bash
astrona destroy ats-014-capstone-010
```
