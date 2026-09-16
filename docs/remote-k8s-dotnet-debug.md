# 遠端 Kubernetes 上除錯 .NET：原理與過程

| 項目 | 內容 |
|------|------|
| 儲存庫 | https://github.com/zeroflare/nhi-k8s-debug （Public） |
| 主方案 | Microsoft **vsdbg** + **`kubectl exec`（stdio）** + **Portable PDB** |
| 環境 | Linux K3s／Kubernetes 容器內之 .NET 10 |
| IDE | Visual Studio Code（建議）／Visual Studio（Windows） |

---

## 1. 背景概念（簡要）

| 概念 | 說明 |
|------|------|
| **IDE** | 本機操作介面。VS Code 靠 Microsoft **C#** 擴充功能（`coreclr`）發起除錯；VS 為完整 IDE。 |
| **除錯器（debugger）** | 真正 attach、設斷點、讀變數的程式。遠端場景下須跑在「碰得到目標 process」的地方（本專案＝容器內 **vsdbg**）。 |
| **DAP** | Debug Adapter Protocol。IDE 與除錯器之間的訊息格式；本專案經 **stdio** 傳遞，不是開一個 debug TCP port。 |
| **Launch** | 由除錯工作階段**啟動**程式。 |
| **Attach** | 程式**已在跑**，再把除錯器掛上去（K8s 情境幾乎都用這個）。 |
| **斷點** | 執行到該行**之前**暫停；可看／改區域變數，再 Continue 或單步。 |
| **PDB** | 符號檔：把 DLL 對回原始碼行號與變數名。須與執行中的 DLL **同一次建置**。 |
| **Detach／Stop** | Detach＝只斷開 IDE；Stop＝可能殺掉遠端 `dotnet`（Pod 會重啟）。遠端請用 **Detach**。 |

本機除錯：程式與 IDE 同機。  
遠端除錯：程式在容器／叢集，IDE 在筆電——本文件討論後者。

---

## 2. 原理：三個要件

應用在 **遠端 Linux 容器**，要能下斷點，缺一不可：

1. **除錯器**能接觸容器內的 `dotnet`  
2. **PDB**能把 DLL 對回本機原始碼  
3. **傳輸通道**讓 IDE 與遠端除錯器交換 DAP  

本專案對應關係：

| 要件 | 作法 |
|------|------|
| 除錯器 | 映像建置時安裝 **vsdbg** → `/vsdbg/vsdbg` |
| 符號 | `dotnet publish -c Debug` 產出 Portable PDB（可進映像，或事後 `kubectl cp`） |
| 通道 | IDE → **ssh** → **`kubectl exec -i`** → 容器內啟動 vsdbg（**stdin/stdout**） |

### 2.1 為什麼是 exec，不是 4026？

Windows 傳統遠端除錯常用 **msvsmon.exe** 聽 **TCP（約 4026）**。  
Linux／容器上 Microsoft 提供的是 **vsdbg**：設計為 IDE（或 pipe）用 **stdio** 對話，**不**在容器開除錯用 TCP port。

因此：

- **不必**（也無法用 msvsmon）在 Linux Pod 開 4026  
- **必須**具備對 Pod 的 **`kubectl exec`**（RBAC：`pods/exec`）  
- 操作上 **不必**手動 `kubectl exec -it … bash`；IDE 會自動 `exec -i` 跑 vsdbg  

應用 HTTP（本專案 **8080**）可用另一條 `port-forward` 打 API 觸發斷點，**與除錯通道分開**。

### 2.2 vsdbg 與 PDB 各做什麼

| | vsdbg | PDB |
|--|-------|-----|
| 角色 | 控制程序：暫停、繼續、單步、讀狀態 | 對應符號：哪一行、哪個變數 |
| 沒有它 | 無法（或極難）遠端 attach 做原始碼級除錯 | 往往仍能 attach，但**斷點對不到你的程式** |
| 放哪 | 容器內 `/vsdbg/vsdbg`（建議映像預裝） | 與 DLL 同目錄，本專案 `/app/NhiApi.pdb` |

框架 DLL（`/usr/share/dotnet/shared/...`）常缺 PDB，Debug Console 出現「Cannot find or open the PDB file」多半是框架，**不代表**應用 PDB 缺失。

---

## 3. 通訊與設定

```text
本機 IDE（VS Code + Microsoft C#）
  launch.json：request = attach，processId = 1
        │
        │  pipeTransport
        │  ssh -i … user@host
        │  kubectl exec -i deploy/… -c my-app --
        │  /vsdbg/vsdbg   （DAP over stdio）
        ▼
Pod 容器 my-app
        ├── /vsdbg/vsdbg
        ├── /app/NhiApi.dll     （常見 PID 1）
        └── /app/NhiApi.pdb
```

本專案 kubectl 在 K3s VM 上，故 `pipeTransport` 以 **ssh** 包一層；若本機已有指向該叢集的 kubeconfig，可改為直接 `kubectl exec`（原理相同）。

### 3.1 launch.json 重點欄位

| 欄位 | 意義 |
|------|------|
| `type: coreclr` | .NET 除錯 |
| `request: attach` | 附加到已執行程序 |
| `processId` | 容器內目標 PID（單一進入點時常為 `1`） |
| `pipeTransport.pipeProgram` / `pipeArgs` | 如何建立到遠端 shell 的管道（ssh + kubectl） |
| `debuggerPath` | 容器內 vsdbg 路徑 |
| `sourceFileMap` | 容器編譯路徑（如 `/src/NhiApi`）→ 本機工作區，斷點才開對檔 |

### 3.2 工作階段生命週期（簡圖）

1. IDE 透過 pipe 在遠端啟動 vsdbg  
2. vsdbg **attach** 到 `dotnet`（PID）  
3. IDE 依 PDB + sourceFileMap **綁定斷點**  
4. 請求進入程式 → 命中斷點 → 暫停  
5. Continue／Step／改變數  
6. **Detach** 結束（程序繼續跑）  

---

## 4. 映像裡要準備什麼

`Dockerfile` 做的事（對除錯有意義的部分）：

1. **`dotnet publish -c Debug`**：產出 `NhiApi.dll` + Portable PDB  
2. **安裝 vsdbg**（預先下載的 binary，不是現場編譯應用）：

   ```bash
   curl -sSL https://aka.ms/getvsdbgsh | /bin/sh /dev/stdin -v latest -l /vsdbg
   ```

3. 安裝 **procps**（提供 `ps`，方便選 process）  
4. 進入點 `dotnet NhiApi.dll`，聽 **8080**  

若政策不希望映像常駐 PDB：可用 Release／無 PDB 部署，除錯前再用第 6 節 Actions **只拷 PDB**；**vsdbg 仍建議留在除錯用映像**。

---

## 5. 先決條件 Checklist

| # | 條件 |
|---|------|
| 1 | 目標為 **Linux** 容器上的 .NET（本專案 K3s） |
| 2 | 映像內有 **vsdbg**，路徑與 `debuggerPath` 一致 |
| 3 | **PDB 與執行中 DLL 同建置**（或接受僅能弱除錯） |
| 4 | 能 **`kubectl exec -i`** 進目標容器（本專案經 SSH 到 VM） |
| 5 | VS Code + **Microsoft C#**（勿依賴會忽略 pipeTransport 的替代實作） |
| 6 | 本機原始碼與部署版本一致；`sourceFileMap` 正確 |
| 7 | 建議 **replicas = 1**；放寬或關閉過短的 **livenessProbe** |

操作細節見 [README](https://github.com/zeroflare/nhi-k8s-debug/blob/main/README.md)。

---

## 6. 一次遠端除錯怎麼走

### 6.1 建議流程

1. **部署**含 vsdbg（及可選 PDB）之映像（本專案：push `main` → deploy workflow）。  
2. 本機開啟**與部署相同 commit** 的原始碼，在目標行下斷點。  
3. VS Code Run and Debug → **NhiApi: Attach K8s (SSH)** → F5。  
4. 另開終端 **port-forward** 應用埠，對會走到斷點的 API 發請求（例如 `/`、`/weatherforecast`）。  
5. 命中後檢視／修改變數 → Continue 或單步。  
6. 結束：**Detach**，不要 Stop。  

### 6.2 Visual Studio（Windows）

遠端仍是容器內同一套 vsdbg。本機執行 `scripts/Start-VsK8sAttach.ps1`，依輸出於 Command Window 啟動 attach。同樣需要 SSH／kubectl exec 能力與匹配的 PDB。

### 6.3 常見狀況

| 現象 | 可能原因 |
|------|----------|
| Attach 失敗／立刻結束 | 無 exec 權限、ssh／金鑰錯誤、pod 未 Ready、vsdbg 路徑不對 |
| 能 attach 但斷點灰色或不停 | PDB 缺失或與 DLL 不同版；sourceFileMap 不對；本機碼與映像不同 commit |
| 停一下 Pod 被重啟 | liveness 過短，誤判程序不健康 |
| Debug Console 一堆框架缺 PDB | 通常可忽略（框架 runtime 無符號） |

---

## 7. 用 GitHub Actions 新增／刪除 PDB（不重建映像）

**動機：** vsdbg 管控制；PDB 管符號。可對**執行中** Pod 只改 `/app/NhiApi.pdb`，不 `docker build`、不換 Deployment image。

| Workflow | 檔案 | 行為 |
|----------|------|------|
| **Enable PDB in K3s Pod** | [pdb-enable.yml](https://github.com/zeroflare/nhi-k8s-debug/blob/main/.github/workflows/pdb-enable.yml) | checkout `git_ref` → `publish -c Debug` → scp → `kubectl cp` 到 Pod |
| **Remove PDB from K3s Pod** | [pdb-disable.yml](https://github.com/zeroflare/nhi-k8s-debug/blob/main/.github/workflows/pdb-disable.yml) | `kubectl exec … rm -f /app/NhiApi.pdb` |

觸發：GitHub **Actions** → 選 workflow → **Run workflow**（手動）。Secrets 與 deploy 相同：`SSH_*`。

**約束：**

- `git_ref` **必須**對齊目前 Pod 內 DLL 的 commit  
- **不**安裝 vsdbg（映像裡要先有）  
- 預設**不**重啟 Pod；Pod **重建後**事後拷入的 PDB 可能消失，需再 Enable  
- 現行實作以單一／Deployment 目標為主，多 replica 時可能只改到一個執行個體  

建議模式：平時可無 PDB → 要查問題再 Enable → attach → 可選 Remove。

---

## 8. 與其他方案對照

| | **vsdbg（本專案）** | **msvsmon.exe** | **netcoredbg** |
|--|---------------------|-----------------|----------------|
| 來源 | Microsoft | Microsoft | Samsung（開源） |
| 目標 OS | **Linux** 容器 | **Windows** | Linux／本機 |
| 通道 | **stdio + kubectl exec** | **TCP ≈ 4026** | stdio 或 **TCP `--server`** |
| Linux K8s | ✅ 主路徑 | ❌ 非標準方案 | 可行，本專案未採用 |
| 何時考慮 | 容器／K8s 遠端原始碼除錯 | 遠端 Windows 服務 + VS Attach | 禁止 exec、只准 port-forward debug port |

**決策一句話：** Linux Pod 要微軟官方路徑 → **vsdbg + exec**；不要期待 msvsmon／4026。若政策禁止 exec，再評估 **netcoredbg TCP**（須改映像與 IDE 接法）。

---

## 9. 產物與參考

| 路徑 | 用途 |
|------|------|
| `Dockerfile` | Debug 建置、安裝 vsdbg |
| `k8s/my-app.yaml` | Deployment／Service |
| `.vscode/launch.json` | attach、pipeTransport、sourceFileMap |
| `.github/workflows/deploy.yml` | 建置並部署 |
| `.github/workflows/pdb-enable.yml` / `pdb-disable.yml` | 手動加／刪 PDB |
| `scripts/Start-VsK8sAttach.ps1` | Visual Studio 輔助 |

- 儲存庫：https://github.com/zeroflare/nhi-k8s-debug  
- [Attaching to remote processes](https://github.com/dotnet/vscode-csharp/blob/main/docs/debugger/Attaching-to-remote-processes.md)（vsdbg／pipeTransport）  
- [Remote Debugging](https://learn.microsoft.com/en-us/visualstudio/debugger/remote-debugging)（msvsmon）  
- [netcoredbg](https://github.com/Samsung/netcoredbg)  
