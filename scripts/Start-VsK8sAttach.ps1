# Visual Studio：產生 DebugAdapterHost 用的 launch.json，並印出要貼到 Command Window 的命令。
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "src\NhiApi"
$execScript = Join-Path $PSScriptRoot "k8s-exec-ssh.ps1"

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
Write-Host "在 Visual Studio 開啟 NhiApi.sln，Command Window (Ctrl+Alt+A) 執行："
Write-Host "DebugAdapterHost.Launch /LaunchJson:`"$launchPath`""
Write-Host "停 debug 請用 Debug > Detach All，不要 Stop Debugging。"
