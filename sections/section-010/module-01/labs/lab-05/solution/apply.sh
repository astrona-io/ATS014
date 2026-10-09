#!/usr/bin/env bash
# Reference solution, applied only by `astrona test` (the `testing:` block).
# `astrona run` never runs this, so students still do the work themselves.
# Kept in step with solution.md - if one changes, change the other.
set -euo pipefail

kubectl patch svc probe -n starfleet --type merge \
  -p '{"spec":{"ports":[{"name":"http","port":8000,"targetPort":8080}]}}'
