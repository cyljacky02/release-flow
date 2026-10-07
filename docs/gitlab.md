# GitLab CI/CD 接入

根目錄 `.gitlab-ci.yml` 是範例應用的 pipeline，必須依專案 runner、build 及交付路徑調整。未在遠端 GitLab 執行或 lint 驗證。

## Runner

準備受管理的 Windows shell runner，設定 `shell = "powershell"`、tag `windows-powershell`。Runner 身分只應具有 build 與交付 inbox 的必要權限，**不要授予正式應用目錄及服務控制權限**。GitLab manual job 本身不是部門隔離機制；必須由 runner／目標端 ACL 與公司流程落實權限。

現有 PowerShell execution policy 由組織管理；範例不以 Bypass 改寫政策。

## 流程

1. `build_application` 執行權威 build 命令一次，保存共用產物。
2. `package_node_a`／`package_node_b` 共用 `.package_target` 範本，各自組裝套件；新增目標時配置對應目標目錄及具名 job。
3. `deliver_node_a`／`deliver_node_b` 共用 `.deliver_target` 範本，各自只依賴相應 package job，預設關閉。設定 `RELEASE_DELIVERY_ENABLED=true` 及 `RELEASE_INBOX_BASE` 才顯示 manual job。
4. 正式部署者在外部審查／核准完成後，使用 inbox 套件的 `tools/Deploy.ps1` 執行。**本版本只有模擬服務，不能正式操作 Windows services。**

`RELEASE_INBOX_BASE` 必須是可由 runner 寫入的批准投遞根目錄（如受控 UNC share），不能是 production path。來源及目標路徑能力需要環境管理者驗證；不在 repo 保存登入憑證。根目錄變數與 manual job 可操作權不提供合規保證。

每個 delivery job 只下載對應 package job 的 artifact；各目標 package 使用獨立子目錄。採具名 jobs 與共用範本，避免依賴新版 GitLab matrix expressions，亦避免某個目標 package 失敗連帶阻擋其他目標投遞。相容性仍需在實際 GitLab instance 驗證。

## 與本地的差異

| 項目 | 本地 DEMO | GitLab |
|---|---|---|
| build | 在唯一暫存目錄為 v1／v2 各 build 一次 | 每次 pipeline build 指定版本一次 |
| 目標設定 | 產生兩組假環境值 | repo 的 `examples/targets/<TargetId>`，需換成實際非秘密設定 |
| 投遞 | 本地隔離 inbox | runner 可寫入的批准 inbox |
| 換版 | 模擬部署者呼叫並自動確認，僅 DEMO | 不執行；另一部門稍後操作 |
| 服務 | 模擬 | 此 pipeline 不操作服務 |

ZIP 的 `.sha256` 必須經受控交付管道取得；若 ZIP 與摘要一起被竄改，一致性檢查無法識別來源。工具變更、部署設定變更與應用變更都應納入套件審查。

## 真實專案接入

以專案接入 skill 探索既有 build 命令，替換 `Build.ps1` 的範例內容，保留權威入口供 local／GitLab 共用。確認既有 pipeline stages、rules、tags 及 artifact 保留政策後合併，不直接覆蓋現有專案 YAML。用該 GitLab instance 的 CI Lint 驗證 YAML，runner 僅投遞測試 inbox 驗收後再申請正式交付權限。
