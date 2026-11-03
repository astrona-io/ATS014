#!/usr/bin/env bash
# Prints the connection settings that the shuttle's sidecar proxy holds for the
# probe cluster: connect timeout, idle timeout, maximum connection duration and
# TCP keepalive. Run it after you change the probe DestinationRule.
# Example: show-connection-settings.sh
istioctl proxy-config cluster deploy/shuttle -n starfleet \
  --fqdn probe.starfleet.svc.cluster.local --port 8000 -o json \
  | grep -E '"connectTimeout"|"idleTimeout"|"maxConnectionDuration"|"keepalive'
