# nhi-k8s-debug

儲存庫：https://github.com/zeroflare/nhi-k8s-debug （Public）

.NET 10 Minimal API，部署到 K3s 後用 **vsdbg + kubectl exec** 遠端下斷點。vsdbg 不開 TCP port。

預設映像為 **Release，不含 PDB／vsdbg**；除錯前用 Actions 注入，結束後可再刪除。

原理見 [docs/remote-k8s-dotnet-debug.md](./docs/remote-k8s-dotnet-debug.md)。

## VS Code

1. 安裝 **[C#](https://marketplace.visualstudio.com/items?itemName=ms-dotnettools.csharp)**（`ms-dotnettools.csharp`）。
2. 本機需 [.NET 10 SDK](https://dotnet.microsoft.com/download)（`.vscode/settings.json` 已設 `dotnet.dotnetPath`）。
3. Run and Debug：
   - **macOS / Linux**：選 **NhiApi: Attach K8s (SSH)**
   - **Windows**：選 **NhiApi: Attach K8s (SSH) [Windows]**

### Windows：`p.key` too open / 意外結束 255

OpenSSH 認為私鑰權限太寬。**NhiApi: Attach K8s (SSH) [Windows]** 會經 `k8s-exec-ssh.ps1` 自動收緊 ACL；也可先手動跑：

```powershell
icacls .\scripts\p.key /inheritance:r
icacls .\scripts\p.key /grant:r "$($env:USERNAME):(R)"

ssh -T -i .\scripts\p.key -o BatchMode=yes -o IdentitiesOnly=yes `
  -o StrictHostKeyChecking=accept-new github@136.119.103.123 -- kubectl get pods -l app=my-app
```

手動連成功後再 F5。

## 遠端 debug

1. GitHub Actions 手動跑 **Enable Debug Tools (vsdbg + PDB)**（`git_ref` 須對齊目前 pod 的 DLL commit）  
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

5. 停 debug 用 **Detach**；可再跑 **Remove Debug Tools (vsdbg + PDB)** 清掉容器內工具  

## 手動開 / 關除錯工具（不重建 image）

| Workflow | 作用 |
|----------|------|
| **Enable Debug Tools (vsdbg + PDB)** | 下載 linux-x64 vsdbg + 依 `git_ref` 建出匹配 PDB，拷進 pod `/vsdbg` 與 `/app/NhiApi.pdb` |
| **Remove Debug Tools (vsdbg + PDB)** | 刪除 `/vsdbg` 與 `/app/NhiApi.pdb` |

需與 deploy 相同的 `SSH_*` secrets。Pod 重建後注入的檔案會消失，需再 Enable。

## Visual Studio（Windows）

```powershell
.\scripts\Start-VsK8sAttach.ps1
```

`scripts/p.key` 不要提交。
