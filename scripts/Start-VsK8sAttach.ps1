# Visual Studio：產生 DebugAdapterHost 用的 launch.json，並對「已開啟」的 VS 直接下 attach。
# 注意：VS 不像 VS Code 能用綠色 Run 跑 pipeTransport；這是最接近一鍵的做法。
param(
    [switch]$LaunchJsonOnly
)

# Windows PowerShell 5.1：避免中文訊息亂碼
if ($PSVersionTable.PSVersion.Major -lt 6) {
    try {
        chcp 65001 | Out-Null
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
        $OutputEncoding = New-Object System.Text.UTF8Encoding $false
    } catch {
        # ignore
    }
}

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "src\NhiApi"
$execScript = Join-Path $PSScriptRoot "k8s-exec-ssh.ps1"
$slnPath = Join-Path $repoRoot "NhiApi.sln"

& (Join-Path $PSScriptRoot "Fix-SshKeyAcl.ps1") (Join-Path $PSScriptRoot "p.key")

$launchPath = Join-Path $env:TEMP "nhi-k8s-debug-attach.launch.json"
$launch = @{
    version = "0.2.0"
    adapter = "powershell"
    adapterArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$execScript`" /vsdbg/vsdbg --interpreter=vscode"
    languageMappings = @{
        "C#" = @{
            languageId = "3F5162F8-07C6-11D3-9053-00C04FA302A1"
            extensions = @("*")
        }
    }
    exceptionCategoryMappings = @{
        CLR = "449EC4CC-30D2-4032-9256-EE18EB41B62B"
        MDA = "6ECE07A9-0EDE-45C4-829D-818D8FC401D4"
    }
    configurations = @(
        @{
            name = "NhiApi Attach K3s"
            type = "coreclr"
            request = "attach"
            processId = "1"
            sourceFileMap = @{
                "/src/NhiApi" = $sourcePath
            }
        }
    )
}

$launch | ConvertTo-Json -Depth 8 | Set-Content -Path $launchPath -Encoding UTF8
Write-Host "已寫入 $launchPath"

$commandArg = "/LaunchJson:`"$launchPath`""
if ($LaunchJsonOnly) {
    Write-Host "在 Visual Studio Command Window (Ctrl+Alt+A) 執行："
    Write-Host "DebugAdapterHost.Launch $commandArg"
    Write-Host "停 debug 請用 Debug > Detach All，不要 Stop Debugging。"
    return
}

$dte = $null
foreach ($progId in @("VisualStudio.DTE.17.0", "VisualStudio.DTE.16.0", "VisualStudio.DTE")) {
    try {
        $dte = [Runtime.InteropServices.Marshal]::GetActiveObject($progId)
        break
    } catch {
        # try next
    }
}

if (-not $dte) {
    Write-Host "找不到已開啟的 Visual Studio。"
    Write-Host "請先開啟 $slnPath，再重跑本腳本；或用 -LaunchJsonOnly 改手動貼 Command Window。"
    Write-Host "手動命令：DebugAdapterHost.Launch $commandArg"
    exit 1
}

try {
    $dte.ExecuteCommand("DebugAdapterHost.Launch", $commandArg)
    Write-Host "已對 Visual Studio 下達 DebugAdapterHost.Launch。"
    Write-Host "停 debug 請用 Debug > Detach All，不要 Stop Debugging。"
} catch {
    Write-Host "自動下命令失敗：$($_.Exception.Message)"
    Write-Host "請在 Command Window (Ctrl+Alt+A) 手動執行："
    Write-Host "DebugAdapterHost.Launch $commandArg"
    exit 1
}
