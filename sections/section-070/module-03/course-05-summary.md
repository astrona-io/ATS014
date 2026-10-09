# Summary

A machine outside Kubernetes, such as a virtual machine, can often be reached from the mesh by its IP address. Istio does not know it, though. The caller's sidecar proxy sends the request through `PassthroughCluster`, without any rules, and no routing rule or policy can name the machine.

A `WorkloadEntry` describes one such machine to Istio. Its `address` says where the machine is, its `labels` let a `ServiceEntry` select it, and its `serviceAccount` gives it the identity `spiffe://<trust-domain>/ns/<namespace>/sa/<service-account>`. The ServiceAccount must exist in the same namespace as the entry. A `WorkloadEntry` alone has no host name and no port, so the caller's proxy builds no cluster for it.

A `ServiceEntry` with `location: MESH_INTERNAL`, `resolution: STATIC` and a `workloadSelector` gives the machines one host name and port. `istiod` sends the addresses of the selected entries to every proxy as the endpoints of an `EDS` cluster. A second `WorkloadEntry` with the same labels becomes a second endpoint, with no change to the `ServiceEntry`. The selector also picks pods with matching labels in the same namespace, and a `ServiceEntry` cannot have both `endpoints` and a `workloadSelector`.

`MESH_INTERNAL` makes the machine part of the mesh: the identity counts, policies can name it, and callers use mTLS (mutual TLS) toward it. A machine without a sidecar proxy fails that handshake with `503 UF` and `WRONG_VERSION_NUMBER` in the access log. `MESH_EXTERNAL` makes the request work but gives the machine no identity, so it is the wrong fix. For a stand-in that can never accept mTLS, a `DestinationRule` with `tls` mode `DISABLE` lets callers send plain HTTP; a real machine with `istio-agent` does not need it.

A selector that matches no entry gives an empty endpoint list and `503 UH`, and `istioctl analyze` reports nothing. The endpoint list from `istioctl proxy-config endpoints` is the first thing to check.

A `WorkloadGroup` is a template with labels, a ServiceAccount and ports, but no address. A real virtual machine running `istio-agent` registers against it, and `istiod` creates and later removes the `WorkloadEntry` for it. The machine needs the agent, a ServiceAccount token, the mesh's root certificate, configuration files, a network path to `istiod` on port `15012` and an address the pods can reach. `istioctl x workload entry configure` builds the files from the group.

Key facts to remember:

- A `WorkloadGroup` relates to `WorkloadEntry` objects the way a Deployment relates to Pods: one template, many instances. `istiod` creates the entries when machines register.
- Use `resolution: STATIC` when a `workloadSelector` selects entries, because the entries already hold the addresses.
- `503 UH` with an empty endpoint list means the selector and the entry labels do not match.
- `503 UF` with `WRONG_VERSION_NUMBER` on a `MESH_INTERNAL` host means the caller uses mTLS and the machine does not.
- The `istio-token` file that `istioctl` writes is a working credential.

<!-- astrona:playground:destroy -->
