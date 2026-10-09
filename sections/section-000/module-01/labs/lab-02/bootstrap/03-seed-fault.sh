#!/usr/bin/env bash
# The lab's starting state: the cargo beacon (Service) selects a label no ship
# carries. Its selector says app=carg0 (a zero instead of an "o"), so the
# Service has no endpoints. The bridge page shows "Error fetching product
# details", every signal to cargo ends in 503 UH, and istioctl analyze stays
# clean. Finding and fixing the selector is the task.
set -euo pipefail

kubectl -n starfleet patch service cargo --type merge \
  -p '{"spec":{"selector":{"app":"carg0"}}}'
