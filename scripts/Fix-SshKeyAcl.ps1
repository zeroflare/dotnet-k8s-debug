# Windows OpenSSH：私鑰 ACL 只能給目前使用者讀，否則會 too open。
$ErrorActionPreference = "Stop"
$keyPath = if ($args.Count -ge 1) { $args[0] } else { Join-Path $PSScriptRoot "p.key" }
if (-not (Test-Path $keyPath)) {
    throw "找不到 SSH 私鑰：$keyPath"
}
$keyFull = (Resolve-Path $keyPath).Path
icacls $keyFull /inheritance:r | Out-Null
icacls $keyFull /grant:r "$($env:USERNAME):(R)" | Out-Null
