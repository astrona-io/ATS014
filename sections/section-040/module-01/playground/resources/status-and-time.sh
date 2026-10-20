#!/usr/bin/env bash
# Sends one request from the shuttle pod and prints the HTTP status code and
# the total time. Every argument goes to curl, so the last one is the URL.
# Example: status-and-time.sh http://probe:8000/get
kubectl exec -n starfleet deploy/shuttle -- curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" "$@"
