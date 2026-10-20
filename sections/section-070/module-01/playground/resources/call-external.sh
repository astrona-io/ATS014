#!/usr/bin/env bash
# Sends one request from the shuttle pod and prints the HTTP status code, the
# total time and the exit code of curl. Every argument goes to curl.
# Example: call-external.sh http://httpbin.org/get
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 "$@"
echo "  exit=$?"
