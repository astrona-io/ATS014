#!/usr/bin/env bash
# Prints the probe pod that each of eight users reaches through the x-user header.
# Example: pod-per-user.sh
for user in alice bob carol dave erin frank grace heidi; do
  printf "%-6s %s\n" "$user" "$(kubectl exec -n starfleet deploy/shuttle -- curl -s -H "x-user: $user" http://probe:8000/hostname | grep -o 'probe-[^"]*')"
done
