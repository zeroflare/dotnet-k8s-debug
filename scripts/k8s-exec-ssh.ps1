# 透過 SSH 在 K3s VM 上執行 kubectl exec，把 vsdbg stdio 接到本機 debugger。
$ErrorActionPreference = "Stop"

$hostName = if ($env:K3S_SSH_HOST) { $env:K3S_SSH_HOST } else { "136.119.103.123" }
$userName = if ($env:K3S_SSH_USER) { $env:K3S_SSH_USER } else { "github" }
$keyPath = if ($env:K3S_SSH_KEY) { $env:K3S_SSH_KEY } else { Join-Path $PSScriptRoot "p.key" }

if (-not (Test-Path $keyPath)) {
    throw "找不到 SSH 私鑰：$keyPath"
}

# Windows OpenSSH 要求私鑰 ACL 僅目前使用者可讀，否則會報 Permissions ... are too open
$keyFull = (Resolve-Path $keyPath).Path
icacls $keyFull /inheritance:r | Out-Null
icacls $keyFull /grant:r "$($env:USERNAME):(R)" | Out-Null

$sshArgs = @(
    "-T",
    "-i", $keyFull,
    "-o", "BatchMode=yes",
    "-o", "IdentitiesOnly=yes",
    "-o", "StrictHostKeyChecking=accept-new",
    "-o", "LogLevel=ERROR",
    "$userName@$hostName"
)

$pod = ssh @sshArgs kubectl get pods -l app=my-app -o jsonpath="{.items[0].metadata.name}"
if ([string]::IsNullOrWhiteSpace($pod)) {
    throw "遠端找不到 label app=my-app 的 pod"
}

& ssh @sshArgs kubectl exec -i $pod -c my-app -- @args
