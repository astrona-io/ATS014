#!/usr/bin/env bash
# Sends one plain http:// request from the shuttle pod to partner.outpost.example
# and prints the response body, then the HTTP status code.
# Example: call-partner.sh
kubectl exec -n starfleet deploy/shuttle -- curl -s --max-time 10 -w "%{http_code}\n" http://partner.outpost.example/
