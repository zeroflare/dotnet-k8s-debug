#!/usr/bin/env bash
# kubectl 只在 K3s VM 上時使用。需要本機 SSH 金鑰，以及：
#   export K3S_SSH_HOST=...
#   export K3S_SSH_USER=...
set -euo pipefail

: "${K3S_SSH_HOST:?請設定 K3S_SSH_HOST}"
: "${K3S_SSH_USER:?請設定 K3S_SSH_USER}"

SSH=(ssh -T -o StrictHostKeyChecking=accept-new "${K3S_SSH_USER}@${K3S_SSH_HOST}")

POD="$("${SSH[@]}" kubectl get pods -l app=my-app -o jsonpath='{.items[0].metadata.name}')"
if [[ -z "${POD}" ]]; then
  echo "遠端找不到 label app=my-app 的 pod" >&2
  exit 1
fi

exec "${SSH[@]}" kubectl exec -i "${POD}" -c my-app -- "$@"
