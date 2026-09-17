# nhi-k8s-debug

儲存庫：https://github.com/zeroflare/nhi-k8s-debug （Public）

.NET 10 Minimal API，部署到 K3s 後用 **vsdbg + kubectl exec** 遠端下斷點。vsdbg 不開 TCP port。

預設映像為 **Debug + 內建 vsdbg + 同源 PDB**（預設不刪 PDB，方便遠端改斷點變數）。deploy 會把同源 PDB 存成 **GitHub Actions Artifact**；必要時可用 Enable 再注入 pod（不存 K3s 主機）。

原理見 [docs/remote-k8s-dotnet-debug.md](./docs/remote-k8s-dotnet-debug.md)。

## VS Code

1. 安裝 **[C#](https://marketplace.visualstudio.com/items?itemName=ms-dotnettools.csharp)**（`ms-dotnettools.csharp`）。
2. 本機需 [.NET 10 SDK](https://dotnet.microsoft.com/download)（`.vscode/settings.json` 已設 `dotnet.dotnetPath`）。
3. Run and Debug：
   - **macOS / Linux**：選 **NhiApi: Attach K8s (SSH)**
   - **Windows**：選 **NhiApi: Attach K8s (SSH) [Windows]**

### Windows：卡住、進不了 debug mode / `p.key` too open

VS Code 的 DAP 需要 **ssh.exe 直接當 pipe**；中間夾 PowerShell 常會卡在已連上 vsdbg 卻不進 debug。

請用 **NhiApi: Attach K8s (SSH) [Windows]**：會先跑 `fix-ssh-key-acl`，再用系統 OpenSSH 直連（參數與 macOS 相同）。

若仍 too open，手動：

```powershell
.\scripts\Fix-SshKeyAcl.ps1 .\scripts\p.key
```

## 遠端 debug

1. push `main` 自動部署（映像內已有 vsdbg + PDB）  
2. 在 `Program.cs` 下斷點  
3. **NhiApi: Attach K8s (SSH)** → F5  
4. Port-forward 後打 API：

```bash
ssh -i scripts/p.key -o IdentitiesOnly=yes -L 8080:localhost:8080 github@136.119.103.123 \
  'kubectl port-forward svc/my-app 8080:8080'
```

```bash
curl http://localhost:8080/weatherforecast
```

5. 停 debug 用 **Detach**

若 Pod 裡 PDB 被拿掉，可跑 **Enable Debug Tools (PDB)**：從該次 deploy 的 GitHub Artifact 下載後注入。

## 手動開 / 關 PDB（可選）

| Workflow | 作用 |
|----------|------|
| **Enable Debug Tools (PDB)** | 依目前 Deployment image tag，下載 `NhiApi-pdb-<sha>` Artifact 注入 `/app/NhiApi.pdb` |
| **Remove Debug Tools (PDB)** | 從執行中 pod 刪除 `/app/NhiApi.pdb`（映像內仍有；重建 pod 會回來） |

需與 deploy 相同的 `SSH_*` secrets。Artifact 預設保留 30 天。
## Visual Studio（Windows）

Visual Studio **不能**像 VS Code 一樣按綠色 Run 就走 `pipeTransport`（沒有同等 F5 設定）。請：

1. 用 VS 開啟 `NhiApi.sln`，在 `Program.cs` 下斷點  
2. PowerShell 跑：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-VsK8sAttach.ps1
```

腳本已用 **UTF-8 BOM**；若中文仍亂碼，先執行 `chcp 65001` 再跑。

腳本會對「已開啟的 VS」直接下 `DebugAdapterHost.Launch` 開始 attach。  
若自動下命令失敗，加 `-LaunchJsonOnly`，再把印出的命令貼到 Command Window（`Ctrl+Alt+A`）。

停 debug 用 **Debug → Detach All**，不要 Stop。

`scripts/p.key` 不要提交。
