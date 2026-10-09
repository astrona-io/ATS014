#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
set -euo pipefail

# Fault 1: stage 2 must send the signal on to port 443, where the TLS settings apply.
kubectl patch virtualservice partner-via-gate -n starfleet --type json \
  -p '[{"op":"replace","path":"/spec/http/1/route/0/destination/port/number","value":443}]'

# Fault 2: credentialName is read from the gate's namespace. Copy the Secret there.
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
kubectl get secret partner-client-cert -n starfleet -o jsonpath='{.data.tls\.crt}' | base64 -d > "$WORK/client.crt"
kubectl get secret partner-client-cert -n starfleet -o jsonpath='{.data.tls\.key}' | base64 -d > "$WORK/client.key"
kubectl get secret partner-client-cert -n starfleet -o jsonpath='{.data.ca\.crt}' | base64 -d > "$WORK/ca.crt"
kubectl create secret generic partner-client-cert -n istio-egress \
  --from-file=tls.crt="$WORK/client.crt" --from-file=tls.key="$WORK/client.key" \
  --from-file=ca.crt="$WORK/ca.crt" --dry-run=client -o yaml | kubectl apply -f -
