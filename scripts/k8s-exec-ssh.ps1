# 透過 SSH 在 K3s VM 上執行 kubectl exec，把 vsdbg stdio 接到本機 debugger。
# 供 Visual Studio DebugAdapterHost 使用；VS Code Windows 請用 launch.json 直連 ssh.exe（避免 PowerShell 擋 DAP stdio）。
$ErrorActionPreference = "Stop"

$hostName = if ($env:K3S_SSH_HOST) { $env:K3S_SSH_HOST } else { "136.119.103.123" }
$userName = if ($env:K3S_SSH_USER) { $env:K3S_SSH_USER } else { "github" }
$keyPath = if ($env:K3S_SSH_KEY) { $env:K3S_SSH_KEY } else { Join-Path $PSScriptRoot "p.key" }

& (Join-Path $PSScriptRoot "Fix-SshKeyAcl.ps1") $keyPath
$keyFull = (Resolve-Path $keyPath).Path

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
