# nhi-k8s-debug

.NET 10 Minimal API，部署到 K3s 後用 **vsdbg + kubectl exec** 遠端下斷點。vsdbg 不開 TCP port。

## VS Code

1. 安裝 **[C#](https://marketplace.visualstudio.com/items?itemName=ms-dotnettools.csharp)**（`ms-dotnettools.csharp`）。
2. 本機需 [.NET 10 SDK](https://dotnet.microsoft.com/download)（`.vscode/settings.json` 已設 `dotnet.dotnetPath`）。
3. Run and Debug 選 **NhiApi: Attach K8s (SSH)**。

## 遠端 debug

1. 在 `Program.cs` 下斷點  
2. **NhiApi: Attach K8s (SSH)** → F5  
3. Port-forward 後打 API：

```bash
ssh -i scripts/p.key -o IdentitiesOnly=yes -L 8080:localhost:8080 github@136.119.103.123 \
  'kubectl port-forward svc/my-app 8080:8080'
```

```bash
curl http://localhost:8080/weatherforecast
```

停 debug 用 **Detach**，不要 Stop。

## 手動開 / 關 PDB（不重建 image）

GitHub Actions → **Run workflow**（需與 deploy 相同的 `SSH_*` secrets）：

| Workflow | 作用 |
|----------|------|
| **Enable PDB in K3s Pod** | 依輸入的 `git_ref` 在 runner 上 `publish -c Debug` 產生 PDB，`kubectl cp` 到 pod `/app/NhiApi.pdb` |
| **Remove PDB from K3s Pod** | 刪除 pod 內 `/app/NhiApi.pdb` |

`git_ref` **必須與目前 pod 裡的 `NhiApi.dll` 同一 commit**，否則斷點對不上。Pod 不會因加/刪 PDB 而重啟；vsdbg 仍須在 image 內（本 repo Dockerfile 已安裝）。

## Visual Studio（Windows）

```powershell
.\scripts\Start-VsK8sAttach.ps1
```

`scripts/p.key` 不要提交。
