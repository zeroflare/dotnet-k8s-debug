# 遠端 Kubernetes 上除錯 .NET：原理與過程

| 項目 | 內容 |
|------|------|
| 儲存庫 | https://github.com/zeroflare/k8s-debug （Public） |
| 主方案 | Microsoft **vsdbg** + **`kubectl exec`（stdio）** + **Portable PDB** |
| 預設映像 | `Dockerfile`：Release，無 vsdbg／PDB |
| 除錯映像 | `Dockerfile.debug`：Debug，內建 vsdbg + 同源 PDB |
| 環境 | Linux K3s／Kubernetes 容器內之 .NET 10 |
| IDE | Visual Studio Code（建議）／Visual Studio（Windows） |

---

## 1. 背景概念（簡要）

| 概念 | 說明 |
|------|------|
| **IDE** | 本機操作介面。VS Code 靠 Microsoft **C#** 擴充功能（`coreclr`）發起除錯。 |
| **除錯器（debugger）** | 真正 attach、設斷點、讀變數的程式。本專案為 **vsdbg**（在 `Dockerfile.debug` 內）。 |
| **DAP** | Debug Adapter Protocol；經 **stdio** 傳遞，不開除錯 TCP port。 |
| **Attach** | 程式已在跑，再掛上除錯器（K8s 幾乎都用這個）。 |
| **斷點** | 一般停在該行**執行前**；可改區域變數後 Continue。 |
| **PDB** | 符號檔；須與執行中 DLL **同一次 publish**。 |
| **Detach／Stop** | 遠端請用 **Detach**；Stop 可能殺掉 `dotnet`。 |

---

## 2. 原理：三個要件

| 要件 | 本專案作法 |
|------|------------|
| 除錯器 | `Dockerfile.debug` 安裝 linux **vsdbg** → `/vsdbg` |
| 符號 | `Dockerfile.debug` 保留同源 `/app/MyApi.pdb` |
| 通道 | IDE → **ssh** → **`kubectl exec -i`** → `/vsdbg/vsdbg`（stdio） |

**不必**手動進 shell，但 **必須有 `pods/exec`**。  
HTTP 8080 的 port-forward 只為打 API，與除錯通道無關。

### 2.1 為什麼是 exec，不是 4026？

Windows 常用 **msvsmon** 聽 TCP（約 **4026**）。  
Linux 容器上微軟路徑是 **vsdbg + stdio／exec**，不是 msvsmon。

### 2.2 vsdbg 與 PDB

| | vsdbg | PDB |
|--|-------|-----|
| 角色 | 控制程序 | 對回原始碼 |
| `Dockerfile`（預設） | 無 | 無 |
| `Dockerfile.debug` | **有** | **有**（同源） |
| 路徑 | `/vsdbg/vsdbg` | `/app/MyApi.pdb` |

---

## 3. 通訊與設定

```text
本機 IDE（attach）
        │  pipeTransport：ssh + kubectl exec -i … -- /vsdbg/vsdbg
        ▼
Pod（Dockerfile.debug）
        ├── /vsdbg/vsdbg
        ├── /app/MyApi.dll
        └── /app/MyApi.pdb
```

`launch.json`：`coreclr` + `attach` + `processId: 1` + `debuggerPath: /vsdbg/vsdbg` + `sourceFileMap`（`/src/MyApi` ↔ 本機）。

---

## 4. 兩個 Dockerfile

| 檔案 | 建置 | vsdbg | PDB | 環境 |
|------|------|-------|-----|------|
| **`Dockerfile`**（預設／自動 deploy） | Release | 無 | 無 | Production |
| **`Dockerfile.debug`** | Debug | 有 | 保留 | Development |

push `main` 用 `Dockerfile`。Actions 手動 Run deploy 選 `Dockerfile.debug` 才可遠端下斷點。

---

## 5. 先決條件 Checklist

| # | 條件 |
|---|------|
| 1 | Linux 容器；能 **`kubectl exec -i`**（本專案經 SSH） |
| 2 | 已部署 **`Dockerfile.debug`**（有 `/vsdbg/vsdbg` 與 `/app/MyApi.pdb`） |
| 3 | 本機原始碼與部署 commit 一致；`sourceFileMap` 正確 |
| 4 | VS Code + Microsoft C# |
| 5 | 建議 replicas = 1；注意 liveness |

---

## 6. 一次遠端除錯怎麼走

1. Actions 手動 deploy，選 **`Dockerfile.debug`**。  
2. 本機同 commit 原始碼下斷點 → **Attach K8s (SSH)**。  
3. Port-forward → 打 API → 命中斷點。  
4. **Detach**。  

Visual Studio：本專案遠端 attach 以 **VS Code + launch.json** 為主（不提供 `.ps1`）。

### 常見狀況

| 現象 | 可能原因 |
|------|----------|
| Attach 失敗 | 部署的是精簡映像、vsdbg 路徑不對、exec／SSH 問題 |
| 斷點不停／灰色 | 非 debug 映像、sourceFileMap 不對、本機碼與部署 commit 不同 |
| `0x80131c08`（TIMEOUT） | 殘留 attach；先 Detach，必要時重啟 Deployment |

---

## 7. GitHub Actions

| Workflow | 行為 |
|----------|------|
| **deploy** | push 用 `Dockerfile`；手動可選 `Dockerfile.debug` |

Secrets：`SSH_PRIVATE_KEY`、`SSH_HOST`、`SSH_USERNAME`。

---

## 8. 與其他方案對照

| | **vsdbg（本專案）** | **msvsmon.exe** | **netcoredbg** |
|--|---------------------|-----------------|----------------|
| 目標 | Linux 容器 | Windows | Linux／本機 |
| 通道 | stdio + exec | TCP ≈ 4026 | stdio 或 TCP server |
| Linux K8s | ✅ | ❌ | 可行，未採用 |

---

## 9. 產物與參考

| 路徑 | 用途 |
|------|------|
| `Dockerfile` | 預設精簡映像 |
| `Dockerfile.debug` | 除錯映像 |
| `.vscode/launch.json` | attach／pipeTransport |
| `.github/workflows/deploy.yml` | 建置部署 |

- 儲存庫：https://github.com/zeroflare/k8s-debug  
- [Attaching to remote processes](https://github.com/dotnet/vscode-csharp/blob/main/docs/debugger/Attaching-to-remote-processes.md)  
