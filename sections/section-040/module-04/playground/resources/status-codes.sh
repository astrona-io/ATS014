#!/usr/bin/env bash
# Prints the HTTP status code of 20 requests from the shuttle pod to the probe.
# Example: status-codes.sh
kubectl exec -n starfleet deploy/shuttle -- sh -c \
  'for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code} " http://probe:8000/hostname; done; echo'
