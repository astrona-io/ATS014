#!/usr/bin/env bash
# Sends one plain http:// request from the shuttle pod to httpbin.org/get and
# prints the address that httpbin.org saw, then the HTTP status code.
# Example: call-httpbin.sh
kubectl exec -n starfleet deploy/shuttle -- curl -s --max-time 15 -w "\n%{http_code}\n" http://httpbin.org/get | grep -E '"url"|^[0-9]{3}$'
