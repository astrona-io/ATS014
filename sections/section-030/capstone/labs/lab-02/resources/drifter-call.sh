#!/usr/bin/env bash
# Sends one request from the drifter (namespace outpost, no sidecar proxy) to
# the probe Service and prints the HTTP status code. The code 000 means curl
# got no HTTP response (for example a reset connection).
kubectl exec -n outpost deploy/drifter -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://probe.starfleet.svc.cluster.local:8000/hostname || true
