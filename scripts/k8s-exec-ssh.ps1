# kubectl 只在 K3s VM 上時使用。先設定 K3S_SSH_HOST、K3S_SSH_USER。
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($env:K3S_SSH_HOST)) {
    throw "請設定環境變數 K3S_SSH_HOST"
}
if ([string]::IsNullOrWhiteSpace($env:K3S_SSH_USER)) {
    throw "請設定環境變數 K3S_SSH_USER"
}

$sshTarget = "$($env:K3S_SSH_USER)@$($env:K3S_SSH_HOST)"
$pod = ssh -T -o StrictHostKeyChecking=accept-new $sshTarget kubectl get pods -l app=my-app -o jsonpath="{.items[0].metadata.name}"
if ([string]::IsNullOrWhiteSpace($pod)) {
    throw "遠端找不到 label app=my-app 的 pod"
}

& ssh -T -o StrictHostKeyChecking=accept-new $sshTarget kubectl exec -i $pod -c my-app -- @args
