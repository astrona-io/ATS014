#!/usr/bin/env bash
# Sends N requests (default 20) over ONE connection: a single curl process
# gets N URLs and reuses its connection for all of them. Then counts which
# probe version answered.
# Usage: count-reused.sh [N] [host:port]          (default host:port is probe-tcp:8000)
count="${1:-20}"
target="${2:-probe-tcp:8000}"
urls=()
for _ in $(seq 1 "$count"); do
  urls+=("http://$target/hostname")
done
kubectl exec -n starfleet deploy/shuttle -- curl -s --max-time 20 "${urls[@]}" \
  | grep -o 'probe-v[0-9]' | sort | uniq -c
