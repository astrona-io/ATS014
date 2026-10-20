#!/usr/bin/env bash
# Sends one request from the shuttle pod (default: https://httpbin.org/get) and
# prints the HTTP status code, the total time and the exit code of curl.
# Example: call-external.sh https://httpbin.org/get
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 10 "${1:-https://httpbin.org/get}"
echo "  exit=$?"
