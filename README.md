# nhi-k8s-debug

.NET 10 Minimal API，部署到 K3s 後用 **vsdbg + kubectl exec** 從 VS Code / Visual Studio 遠端下斷點。vsdbg 不開 TCP port。

## 本機執行

需要 [.NET 10 SDK](https://dotnet.microsoft.com/download)。開 `NhiApi.sln`，或在 VS Code 選 **NhiApi: 本機**。

- API：http://localhost:5080/weatherforecast
- 健康檢查：http://localhost:5080/health

## 遠端 debug（K3s）

Image 是 Debug 組態，內含 Portable PDB 與 `/vsdbg/vsdbg`。

1. 本機 kubectl 已指向該叢集：VS Code 選 **NhiApi: Attach K3s (kubectl)**
2. kubectl 只在 VM 上：設定 `K3S_SSH_HOST`、`K3S_SSH_USER` 後選 **NhiApi: Attach K3s (SSH)**
3. Visual Studio（Windows）：在 repo 根目錄跑 `.\scripts\Start-VsK8sAttach.ps1`，把印出的命令貼到 Command Window（`Ctrl+Alt+A`）

停 debug 用 **Detach All**，不要 Stop（Stop 會殺掉 pod 裡的 `dotnet`）。

在 `Program.cs` 的 `/weatherforecast` 下斷點，再打該 API 即可停住。
