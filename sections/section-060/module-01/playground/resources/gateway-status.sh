#!/usr/bin/env bash
# Sends one request through the ingress gateway on localhost:8080 and prints
# only the HTTP status code. First argument: the path. Second argument: the Host
# header (default starfleet.example.com).
# Example: gateway-status.sh /productpage
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: ${2:-starfleet.example.com}" "http://localhost:8080$1"
