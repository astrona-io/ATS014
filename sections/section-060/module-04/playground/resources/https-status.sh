#!/usr/bin/env bash
# Sends one HTTPS request through the ingress gateway on localhost:8443 and
# prints only the HTTP status code. First argument: the path. Second argument:
# the host name (default starfleet.example.com). curl sends that name in the
# TLS handshake (SNI) because of --resolve, and -k accepts a self-signed
# certificate.
# Example: https-status.sh /productpage
host="${2:-starfleet.example.com}"
curl -sk -o /dev/null -w "%{http_code}\n" --resolve "${host}:8443:127.0.0.1" "https://${host}:8443$1"
