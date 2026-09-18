# dotnet-dotnet-k8s-debug

儲存庫：https://github.com/zeroflare/dotnet-dotnet-k8s-debug （Public）

.NET 10 Minimal API，部署到 K3s 後用 **vsdbg + kubectl exec** 遠端下斷點。vsdbg 不開 TCP port。

| 檔案 | 內容 |
|------|------|
| `Dockerfile`（預設） | 一般 Release 執行（無 vsdbg／PDB／curl） |
| `Dockerfile.debug` | Debug、curl、**有** vsdbg + 同源 PDB |

push `main` 部署預設映像（tag = commit SHA）；要除錯時手動 Run **Build and Deploy** 選 `Dockerfile.debug`（tag = `<sha>-debug`）。

原理見 [docs/remote-k8s-dotnet-debug.md](./docs/remote-k8s-dotnet-debug.md)。  
除錯計劃見 [docs/debug-plan.md](./docs/debug-plan.md)。

## VS Code 遠端 debug

1. 安裝 **[C#](https://marketplace.visualstudio.com/items?itemName=ms-dotnettools.csharp)**（`ms-dotnettools.csharp`）。
2. 本機需 [.NET 10 SDK](https://dotnet.microsoft.com/download)。
3. 本機放置 `scripts/p.key`（勿提交）。
4. Actions 部署 **`Dockerfile.debug`**。
5. 在 `Program.cs` 下斷點 → Run and Debug 選 **MyApi: Attach K8s (SSH)** → F5  
   （Windows 會自動用 `launch.json` 裡的 `windows.pipeTransport`。）
6. Port-forward 後打 API：

```bash
ssh -i scripts/p.key -o IdentitiesOnly=yes -L 8080:localhost:8080 github@136.119.103.123 \
  'kubectl port-forward svc/my-app 8080:8080'
```

```bash
curl http://localhost:8080/
```

7. 停 debug 用 **Detach**。

### Windows：`p.key` too open

OpenSSH 要求私鑰 ACL 夠嚴。在 PowerShell **執行一次**即可（不需腳本）：

```powershell
icacls .\scripts\p.key /inheritance:r
icacls .\scripts\p.key /grant:r "$($env:USERNAME):(R)"
```

遠端 attach 設定全在 `.vscode/launch.json`，不依賴 `.ps1`。
