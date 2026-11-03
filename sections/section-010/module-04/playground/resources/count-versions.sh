#!/usr/bin/env bash
# Sends 10 requests from a client pod and counts which probe version answered.
# Arguments: the client's namespace, the client's Deployment name, then
# everything else goes to curl (the last one is the URL).
# A request that gets no pod name back is counted as "status <code>".
# Example: count-versions.sh starfleet shuttle http://probe:8000/hostname
namespace="$1"
client="$2"
shift 2
for _ in $(seq 1 10); do
  output=$(kubectl exec -n "$namespace" "deploy/$client" -- curl -s -w '\n%{http_code}' --max-time 10 "$@")
  code="${output##*$'\n'}"
  body="${output%$'\n'*}"
  version=$(grep -o 'probe-v[0-9]' <<<"$body" | head -1)
  echo "${version:-status $code}"
done | sort | uniq -c
