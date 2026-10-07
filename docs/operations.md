# 操作指南（本地 DEMO 版）

## 支援範圍

此版只支援 `ServiceMode = Simulated`，不允許真實 Windows service 控制。請先用隔離目錄完成 DEMO；不得將本版本直接用於正式環境。設計共識是目標契約，尚未完成的正式環境能力見 README。

## 本地 DEMO

```powershell
powershell -NoProfile -File scripts/Demo.ps1
powershell -NoProfile -File tests/Run.Tests.ps1
powershell -NoProfile -File tests/Safety.Tests.ps1
powershell -NoProfile -File tests/Interruption.Tests.ps1
```

每次使用新的 `.work/` 子目錄，保留測試證據。範例 build 產生可執行的 PowerShell 示範應用，不是實際專案的 compiler；接入專案時替換 `scripts/Build.ps1` 的內容。

服務模型有一個原本啟動的 worker 及一個原本停止的 optional；停止／啟動順序不同。這僅驗證工作流，不證明 Windows services API、依賴、權限與檔案鎖定行為。

## 分步演練

先在新目錄建立兩個版本及兩組目標：

```powershell
$root = Join-Path $PWD '.work/manual-demo'
./scripts/New-DemoEnvironment.ps1 -Root $root
$config = Join-Path $root 'node-a.json'
$package = Join-Path $root 'inbox/node-a/2.0.0'
$plan = Join-Path $root 'approved-plan.json'
```

首次納管需先檢查 v1 現場，再模擬已完成外部核准：

```powershell
./scripts/Deploy.ps1 -Action Baseline -TargetConfigPath $config -ConfirmExecution
./scripts/Deploy.ps1 -Action Plan -TargetConfigPath $config -PackagePath $package -PlanPath $plan
```

檢查計畫與核准的目標一致後，使用文字選單選擇執行：

```powershell
./scripts/Deploy.ps1 -TargetConfigPath $config -PackagePath $package -PlanPath $plan
```

非互動模式必須明確提供確認：

```powershell
./scripts/Deploy.ps1 -Action Apply -TargetConfigPath $config -PlanPath $plan -ConfirmExecution
./scripts/Deploy.ps1 -Action Status -TargetConfigPath $config
./scripts/Deploy.ps1 -Action Recover -TargetConfigPath $config -ConfirmExecution
```

套件內也包含 `tools/Deploy.ps1` 與當次 `ReleaseFlow.psm1`；部署入口不依賴 AI skill。

## 換版與復原

- manifest 描述完整目標內容，計畫比對現場與來源基準。
- 來源漂移、錯誤目標或核准後變更會阻擋；修正原因並重新審查／產生計畫，不強制覆蓋。
- 先停止模擬服務，再建立快照／復原資料，最後才套用異動。
- 嘗試啟動目標版本前的檔案失敗可自動復原；啟動後驗證失敗保留待處理狀態，需明確執行復原。
- 只撤銷最近一次符合資格的操作，不跨多次歷史倒帶。未改應用的 `Aborted` attempt 不會取代前一次成功部署的復原資格；工具驗證保留的 lineage 與現場後跳過它，保留所有 journal，且不越過已完成的 recovery。
- 升版與降版皆可撤銷；復原回到本次開始前的实际檔案狀態。
- `.work/.../targets/<TargetId>/state` 保留 baseline、runs、操作紀錄與備份；不要手動移除未完成操作資料。`Status.PendingRuns` 包含 orphan journals，不能只看 `CurrentRun`。
- 若 pointer 寫入失敗留下一筆完全未碰應用或服務的 `Preparing` run，可在確認原始 inventory、baseline、服務及設定未變後，明確執行 `ResolvePreparation`：

  ```powershell
  ./scripts/Deploy.ps1 -Action ResolvePreparation -TargetConfigPath $config -RunId '<Preparing RunId>' -ConfirmExecution
  ```

  此操作只把已驗證未異動的 preparation 標為 `Aborted`，不更動應用檔案／服務、不刪 journal。其他階段或缺少 journal 的 run 不得用它清除，需要既有人工決策流程。
- 每個 run 包含 `report.json`、`report.txt`、快照及成功換版後的 `snapshot.zip`。ZIP 不包含 ACL 保證，復原以原檔案與 journal 中繼資料為準。
- 每個 run 的 `tools/` 保存當次核心、非秘密環境設定及獨立復原入口；可在原始套件不存在時執行 `tools/Recover.ps1 -ConfirmExecution`。

模擬故障只用於本地測試，不放到正式入口選單。核心測試 API 支援檔案套用後失敗與健康檢查失敗，演練資料保留供檢查。

## 人工介入與救援

遇到未完成操作、復原失敗或檔案鎖定時，保留工作區、錯誤輸出及備份，交回 developer／既有決策流程。不要用重新採用 baseline 或刪除 current 紀錄跳過問題。

工具無法執行時：

1. 依公司流程安排維護並確認需要停止的服務；保留現場副本，不盲目啟動可能不完整的應用。
2. 保存 run 的操作紀錄、來源 baseline 及原檔案備份，讓 developer 判斷每一個已發生的異動。
3. 按復原集刪除本次新增檔案，還原本次覆蓋／刪除的原內容及必要 ACL；不要整個覆蓋 production root，避免破壞保護資料。
4. 比對來源檔案 hash，按已核准順序恢復原本運行的服務並驗證。
5. 由 developer 核對狀態與紀錄後再恢復工具管理，補齊事故及復原報告。

這是救援檢查清單，不是適用所有正式環境的已驗收人工腳本；使用前須補齊該專案路徑、服务及資料副作用說明。

## 驗證與後續驗收

本地快速測試涵蓋在明確持久化邊界 kill deployment／recovery child process，及模擬 stop／start／recovery failure。測試 seam `PauseAfterFiles`／`PauseSignalPath` 只供隔離 fault tests，訊號檔須位於 application／state／package 範圍外；測試由新進程執行並有逾時與清理，不調整 execution policy。這不涵蓋突然斷電、真實服務、完整存取控制、安全競態防護及跨機協調。待接入實際專案後，需在可丟棄 Windows 環境驗證 ACL／檔案鎖定／程序中斷、runner 投遞與公司權限分工。外部變更單與版本授權的技術綁定、備份保留／清理及完整空間預估亦需後續補強，不能因 DEMO 成功就宣稱 production ready。
