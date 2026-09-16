# 遠端 Kubernetes 上除錯 .NET：原理與過程

| 項目 | 內容 |
|------|------|
| 儲存庫 | https://github.com/zeroflare/nhi-k8s-debug （Public） |
| 主方案 | Microsoft **vsdbg** + **`kubectl exec`（stdio）** + **Portable PDB** |
| 預設映像 | **Release**，**不含** vsdbg／PDB（由 Actions 動態注入） |
| 環境 | Linux K3s／Kubernetes 容器內之 .NET 10 |
| IDE | Visual Studio Code（建議）／Visual Studio（Windows） |

---

## 1. 背景概念（簡要）

| 概念 | 說明 |
|------|------|
| **IDE** | 本機操作介面。VS Code 靠 Microsoft **C#** 擴充功能（`coreclr`）發起除錯。 |
| **除錯器（debugger）** | 真正 attach、設斷點、讀變數的程式。本專案為容器內 **vsdbg**（預設不在映像內，除錯前注入）。 |
| **DAP** | Debug Adapter Protocol；經 **stdio** 傳遞，不開除錯 TCP port。 |
| **Attach** | 程式已在跑，再掛上除錯器（K8s 幾乎都用這個）。 |
| **斷點** | 一般停在該行**執行前**；可改區域變數後 Continue。 |
| **PDB** | 符號檔；須與執行中 DLL **同一次建置參數／同一 commit**。 |
| **Detach／Stop** | 遠端請用 **Detach**；Stop 可能殺掉 `dotnet`。 |

---

## 2. 原理：三個要件

| 要件 | 本專案作法 |
|------|------------|
| 除錯器 | Actions **Enable** 時下載 linux-x64 **vsdbg** → `kubectl cp` 到 `/vsdbg` |
| 符號 | Actions 依 `git_ref` 用與 Dockerfile **相同**之 publish 參數建 PDB → `/app/NhiApi.pdb` |
| 通道 | IDE → **ssh** → **`kubectl exec -i`** → `/vsdbg/vsdbg`（stdio） |

預設映像只跑應用：精簡、無除錯工具。要除錯時再注入；結束可 **Remove** 整組刪除。

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
| 預設映像 | 無 | 無（建置時有產出但會刪掉） |
| 注入後路徑 | `/vsdbg/vsdbg` | `/app/NhiApi.pdb` |

---

## 3. 通訊與設定

```text
本機 IDE（attach）
        │  pipeTransport：ssh + kubectl exec -i … -- /vsdbg/vsdbg
        ▼
Pod（Enable 之後）
        ├── /vsdbg/vsdbg
        ├── /app/NhiApi.dll
        └── /app/NhiApi.pdb
```

`launch.json`：`coreclr` + `attach` + `processId: 1` + `debuggerPath: /vsdbg/vsdbg` + `sourceFileMap`（`/src/NhiApi` ↔ 本機）。  
Enable 建 PDB 時刻意用與 Dockerfile 相同的 `/src/NhiApi` 目錄配置，路徑才對得上。

---

## 4. 預設映像（無除錯工具）

Dockerfile：

1. `dotnet publish -c Release -p:DebugType=portable -p:DebugSymbols=true`（先產出可匹配的 PDB）  
2. 拷入最終映像後 **`rm -f /app/*.pdb`**  
3. **不安裝** vsdbg、不裝 debug 用 apt 套件  
4. `ASPNETCORE_ENVIRONMENT=Production`  

應用 DLL 為 Release；Enable 必須用**相同 Release + portable** 參數重建 PDB，才能與映像內 DLL 對應。

---

## 5. 先決條件 Checklist

| # | 條件 |
|---|------|
| 1 | Linux 容器上的 .NET；能 **`kubectl exec -i`**（本專案經 SSH） |
| 2 | 除錯前已跑 **Enable Debug Tools**（容器內有 `/vsdbg/vsdbg` 與匹配 PDB） |
| 3 | Enable 的 `git_ref` = 目前 DLL 的 commit |
| 4 | VS Code + Microsoft C#；`sourceFileMap` 正確 |
| 5 | 建議 replicas = 1；注意 liveness |

---

## 6. 一次遠端除錯怎麼走

1. 部署預設映像（push `main` → deploy）。  
2. Actions：**Enable Debug Tools (vsdbg + PDB)**，`git_ref` 對齊部署 commit。  
3. 本機同 commit 原始碼下斷點 → **Attach K8s (SSH)**。  
4. Port-forward → 打 API → 命中斷點。  
5. **Detach**；可選 **Remove Debug Tools**。  

Visual Studio：同一遠端 vsdbg，用 `scripts/Start-VsK8sAttach.ps1`。

### 常見狀況

| 現象 | 可能原因 |
|------|----------|
| Attach 失敗 | 尚未 Enable、vsdbg 路徑不對、exec／SSH 問題 |
| 斷點不停／灰色 | 未注入 PDB、`git_ref` 與 DLL 不一致、sourceFileMap 不對 |
| Remove 後又要除錯 | 再跑一次 Enable（Pod 重建後也要） |
| `0x80131c08`（TIMEOUT） | 殘留 attach／連線卡住；先 Detach，必要時重啟 Deployment |

---

## 7. GitHub Actions：注入／移除 vsdbg + PDB

| Workflow | 行為 |
|----------|------|
| **[Enable Debug Tools](https://github.com/zeroflare/nhi-k8s-debug/blob/main/.github/workflows/debug-enable.yml)** | 下載 vsdbg（linux-x64）+ 同版 PDB → `/vsdbg`、`/app/NhiApi.pdb` |
| **[Remove Debug Tools](https://github.com/zeroflare/nhi-k8s-debug/blob/main/.github/workflows/debug-disable.yml)** | 刪除 `/vsdbg` 與 `/app/NhiApi.pdb` |

- 手動 **Run workflow**；Secrets：`SSH_PRIVATE_KEY`、`SSH_HOST`、`SSH_USERNAME`  
- **不**重建映像、**不**改 Deployment image  
- Pod 重建後注入檔會沒，需再 Enable  
- 多 replica 時現行實作可能只打到一個 Pod  

---

## 8. 與其他方案對照

| | **vsdbg（本專案）** | **msvsmon.exe** | **netcoredbg** |
|--|---------------------|-----------------|----------------|
| 目標 | Linux 容器 | Windows | Linux／本機 |
| 通道 | stdio + exec | TCP ≈ 4026 | stdio 或 TCP server |
| Linux K8s | ✅ | ❌ | 可行，未採用 |

Linux Pod 不要用 msvsmon／4026；本專案為 vsdbg + exec，工具可按需注入。

---

## 9. 產物與參考

| 路徑 | 用途 |
|------|------|
| `Dockerfile` | Release 應用、無 PDB／vsdbg |
| `.vscode/launch.json` | attach／pipeTransport |
| `.github/workflows/deploy.yml` | 建置部署 |
| `.github/workflows/debug-enable.yml` | 注入 vsdbg + PDB |
| `.github/workflows/debug-disable.yml` | 移除 vsdbg + PDB |

- 儲存庫：https://github.com/zeroflare/nhi-k8s-debug  
- [Attaching to remote processes](https://github.com/dotnet/vscode-csharp/blob/main/docs/debugger/Attaching-to-remote-processes.md)  
- [Remote Debugging](https://learn.microsoft.com/en-us/visualstudio/debugger/remote-debugging)（msvsmon）  
- [netcoredbg](https://github.com/Samsung/netcoredbg)  
