# 本機 kubectl 已指向 K3s 時使用（Visual Studio / Windows VS Code）。
$ErrorActionPreference = "Stop"

$pod = kubectl get pods -l app=my-app -o jsonpath="{.items[0].metadata.name}"
if ([string]::IsNullOrWhiteSpace($pod)) {
    throw "找不到 label app=my-app 的 pod"
}

& kubectl exec -i $pod -c my-app -- @args
