# 透過 SSH 在 K3s VM 上執行 kubectl exec，把 vsdbg stdio 接到本機 debugger。
$ErrorActionPreference = "Stop"

$hostName = if ($env:K3S_SSH_HOST) { $env:K3S_SSH_HOST } else { "136.119.103.123" }
$userName = if ($env:K3S_SSH_USER) { $env:K3S_SSH_USER } else { "github" }
$keyPath = if ($env:K3S_SSH_KEY) { $env:K3S_SSH_KEY } else { Join-Path $PSScriptRoot "p.key" }

if (-not (Test-Path $keyPath)) {
    throw "找不到 SSH 私鑰：$keyPath"
}

$sshArgs = @(
    "-T",
    "-i", $keyPath,
    "-o", "IdentitiesOnly=yes",
    "-o", "StrictHostKeyChecking=accept-new",
    "$userName@$hostName"
)

$pod = ssh @sshArgs kubectl get pods -l app=my-app -o jsonpath="{.items[0].metadata.name}"
if ([string]::IsNullOrWhiteSpace($pod)) {
    throw "遠端找不到 label app=my-app 的 pod"
}

& ssh @sshArgs kubectl exec -i $pod -c my-app -- @args
