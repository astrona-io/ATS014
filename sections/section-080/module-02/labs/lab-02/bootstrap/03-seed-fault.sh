#!/usr/bin/env bash
# The lab's starting state: the partner route through the egress gateway,
# with MUTUAL origination at the gateway, and two faults:
#   - stage 2 of the VirtualService sends the request to port 80 of the partner,
#     where nothing listens, so the TLS settings for 443 are never used (fault 1)
#   - the client certificate Secret only exists in starfleet; credentialName is
#     read from the gateway's own namespace, istio-egress (fault 2)
# The ServiceEntry, the Gateway, the gateway's DestinationRule and the MUTUAL
# DestinationRule are correct.
set -euo pipefail
cd "$(dirname "$0")"

kubectl apply -f ../resources/starting-state.yaml

echo
echo "==> Starting state applied: requests to partner.outpost.example do not get through yet"
