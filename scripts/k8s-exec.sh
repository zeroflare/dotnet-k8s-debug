#!/usr/bin/env bash
# 本機 kubectl 已指向 K3s 時使用。VS Code pipeTransport 會把 vsdbg 路徑當參數傳進來。
set -euo pipefail

POD="$(kubectl get pods -l app=my-app -o jsonpath='{.items[0].metadata.name}')"
if [[ -z "${POD}" ]]; then
  echo "找不到 label app=my-app 的 pod" >&2
  exit 1
fi

exec kubectl exec -i "${POD}" -c my-app -- "$@"
