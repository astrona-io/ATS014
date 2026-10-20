#!/usr/bin/env bash
# Sends 30 requests from the fortio pod with N connections at once and prints
# the count of each HTTP status code.
# Example: load-test.sh 2
kubectl exec -n starfleet deploy/fortio -c fortio -- \
  fortio load -c "$1" -qps 0 -n 30 -loglevel Warning http://probe:8000/get 2>&1 | grep -E "^Code"
