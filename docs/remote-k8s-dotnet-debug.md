# 遠端 Kubernetes 上除錯 .NET：原理與過程

| 項目 | 內容 |
|------|------|
| 儲存庫 | https://github.com/zeroflare/nhi-k8s-debug （Public） |
| 主方案 | Microsoft **vsdbg** + **`kubectl exec`（stdio）** + **Portable PDB** |
| 預設映像 | **Release + 內建 vsdbg + 同源 PDB**（預設不刪 PDB；deploy 另備份） |
| 環境 | Linux K3s／Kubernetes 容器內之 .NET 10 |
| IDE | Visual Studio Code（建議）／Visual Studio（Windows） |

---

## 1. 背景概念（簡要）

| 概念 | 說明 |
|------|------|
| **IDE** | 本機操作介面。VS Code 靠 Microsoft **C#** 擴充功能（`coreclr`）發起除錯。 |
| **除錯器（debugger）** | 真正 attach、設斷點、讀變數的程式。本專案為映像內 **vsdbg**。 |
| **DAP** | Debug Adapter Protocol；經 **stdio** 傳遞，不開除錯 TCP port。 |
| **Attach** | 程式已在跑，再掛上除錯器（K8s 幾乎都用這個）。 |
| **斷點** | 一般停在該行**執行前**；可改區域變數後 Continue。 |
| **PDB** | 符號檔；須與執行中 DLL **同一次 publish**（另一次編譯的 PDB 檔在也對不上）。 |
| **Detach／Stop** | 遠端請用 **Detach**；Stop 可能殺掉 `dotnet`。 |

---

## 2. 原理：三個要件

| 要件 | 本專案作法 |
|------|------------|
| 除錯器 | Dockerfile 安裝 linux **vsdbg** → `/vsdbg` |
| 符號 | 映像內保留同源 `/app/NhiApi.pdb`；deploy 另備份到 VM，必要時 Enable 再注入 |
| 通道 | IDE → **ssh** → **`kubectl exec -i`** → `/vsdbg/vsdbg`（stdio） |

**不要**用另一次 `dotnet publish` 重編 PDB 蓋上去：MVID 不同，斷點會失效。

**不必**手動進 shell，但 **必須有 `pods/exec`**。  
HTTP 8080 的 port-forward 只為打 API，與除錯通道無關。

### 2.1 為什麼是 exec，不是 4026？

Windows 常用 **msvsmon** 聽 TCP（約 **4026**）。  
Linux 容器上微軟路徑是 **vsdbg + stdio／exec**，不是 msvsmon。

### 2.2 vsdbg 與 PDB

| | vsdbg | PDB |
|--|-------|-----|
| 角色 | 控制程序 | 對回原始碼 |
| 沒有它 | 無法用本方案 attach | 往往能 attach，斷點對不到你的碼 |
| 預設映像 | **有** | **有**（與 DLL 同一次 publish；預設不刪） |
| 路徑 | `/vsdbg/vsdbg` | `/app/NhiApi.pdb` |

---

## 3. 通訊與設定

```text
本機 IDE（attach）
        │  pipeTransport：ssh + kubectl exec -i … -- /vsdbg/vsdbg
        ▼
Pod
        ├── /vsdbg/vsdbg          ← 映像內建
        ├── /app/NhiApi.dll
        └── /app/NhiApi.pdb       ← 映像內建（同源）；可選 Enable 從備份再注入
```

`launch.json`：`coreclr` + `attach` + `processId: 1` + `debuggerPath: /vsdbg/vsdbg` + `sourceFileMap`（`/src/NhiApi` ↔ 本機）。  
Dockerfile 的 publish 目錄是 `/src/NhiApi`，PDB 內路徑才會對得上。

---

## 4. 預設映像（含 vsdbg + PDB）

Dockerfile：

1. `dotnet publish -c Release -p:DebugType=portable -p:DebugSymbols=true`  
2. 安裝 **vsdbg**（與 curl／unzip／procps）  
3. 拷入應用後**保留** `NhiApi.pdb`（預設不刪）  
4. `ASPNETCORE_ENVIRONMENT=Production`  

deploy 會再備份同源 PDB 到 VM（供 Enable 補注）。

---

## 5. 先決條件 Checklist

| # | 條件 |
|---|------|
| 1 | Linux 容器上的 .NET；能 **`kubectl exec -i`**（本專案經 SSH） |
| 2 | 映像內有 `/vsdbg/vsdbg` 與 `/app/NhiApi.pdb` |
| 3 | 本機原始碼與部署 commit 一致；`sourceFileMap` 正確 |
| 4 | VS Code + Microsoft C# |
| 5 | 建議 replicas = 1；注意 liveness |

---

## 6. 一次遠端除錯怎麼走

1. 部署（push `main` → deploy；vsdbg + PDB 已在 image）。  
2. 本機同 commit 原始碼下斷點 → **Attach K8s (SSH)**。  
3. Port-forward → 打 API → 命中斷點。  
4. **Detach**。  

若執行中 PDB 被刪，可跑 **Enable Debug Tools (PDB)** 從 VM 備份注入。

Visual Studio：同一遠端 vsdbg，用 `scripts/Start-VsK8sAttach.ps1`。

### 常見狀況

| 現象 | 可能原因 |
|------|----------|
| Attach 失敗 | vsdbg 路徑不對、exec／SSH 問題 |
| 斷點不停／灰色 | PDB 被刪且未 Enable、sourceFileMap 不對、本機碼與部署 commit 不同 |
| `0x80131c08`（TIMEOUT） | 殘留 attach／連線卡住；先 Detach，必要時重啟 Deployment |

---

## 7. GitHub Actions：PDB 備份／注入／移除

| Workflow | 行為 |
|----------|------|
| **deploy** | build／push image（含 PDB）；另備份到 `~/my-app-pdbs/<sha>/` |
| **[Enable Debug Tools](https://github.com/zeroflare/nhi-k8s-debug/blob/main/.github/workflows/debug-enable.yml)** | 依 Deployment image tag 注入備份 PDB（可選） |
| **[Remove Debug Tools](https://github.com/zeroflare/nhi-k8s-debug/blob/main/.github/workflows/debug-disable.yml)** | 從執行中 pod 刪除 PDB（映像重建後會回來） |

- Enable／Remove 手動 **Run workflow**；Secrets：`SSH_PRIVATE_KEY`、`SSH_HOST`、`SSH_USERNAME`  
- 多 replica 時現行實作可能只打到一個 Pod  

---

## 8. 與其他方案對照

| | **vsdbg（本專案）** | **msvsmon.exe** | **netcoredbg** |
|--|---------------------|-----------------|----------------|
| 目標 | Linux 容器 | Windows | Linux／本機 |
| 通道 | stdio + exec | TCP ≈ 4026 | stdio 或 TCP server |
| Linux K8s | ✅ | ❌ | 可行，未採用 |

Linux Pod 不要用 msvsmon／4026；本專案為 vsdbg + exec。

---

## 9. 產物與參考

| 路徑 | 用途 |
|------|------|
| `Dockerfile` | Release 應用 + 內建 vsdbg + 同源 PDB |
| `.vscode/launch.json` | attach／pipeTransport |
| `.github/workflows/deploy.yml` | 建置部署 + 備份 PDB |
| `.github/workflows/debug-enable.yml` | 可選注入 PDB |
| `.github/workflows/debug-disable.yml` | 可選移除執行中 PDB |

- 儲存庫：https://github.com/zeroflare/nhi-k8s-debug  
- [Attaching to remote processes](https://github.com/dotnet/vscode-csharp/blob/main/docs/debugger/Attaching-to-remote-processes.md)  
- [Remote Debugging](https://learn.microsoft.com/en-us/visualstudio/debugger/remote-debugging)（msvsmon）  
- [netcoredbg](https://github.com/Samsung/netcoredbg)  
