# release-flow

以 PowerShell 自動化既有的人工換版流程。Developer 準備套件，正式環境由另一部門依已核准流程執行。

**目前交付是可執行的本地 DEMO／驗證版，不是已驗收的 production 工具。** 核心只允許模擬服務；真實 Windows service 整合、電源中斷耐受、完整磁碟空間預估及安全稽核尚未驗證／完成。

## 快速開始

Windows PowerShell 5.1（或相容 PowerShell）及 .NET ZIP API，不需 Docker、VM 或額外套件。

```powershell
powershell -NoProfile -File ./scripts/Demo.ps1
powershell -NoProfile -File ./tests/Run.Tests.ps1
```

DEMO 對 v1、v2 各 build 一次，再分別組裝 node-a、node-b 套件；真實建立 ZIP、驗證 manifest、投遞、快照、檔案換版及復原，服務操作為模擬。輸出保留在 `.work/` 的唯一目錄，不刪除既有資料。

## 專案結構

- `src/ReleaseFlow.psm1`：共用計畫／執行／復原核心。
- `scripts/Build.ps1`：範例應用的 build 入口，接入真實專案時替換內容。
- `scripts/Package.ps1`：使用既有 build，加入單一目標設定與工具。
- `scripts/Deliver.ps1`：核對 ZIP 摘要、安全解壓到新投遞目錄，不啟動正式換版。
- `scripts/Deploy.ps1`：文字選單與非互動入口。
- `.gitlab-ci.yml`：Windows shell-runner 範例，build 一次、按目標 package／delivery。
- `.agents/skills/release-flow-onboarding/SKILL.md`：協助 developer 接入專案。
- [設計共識](docs/design/deployment-workflow-v1.md)、[操作指南](docs/operations.md)、[GitLab 設定](docs/gitlab.md)。
- [真實 legacy Java 接入案例](examples/legacy-java/README.md)：固定來源的 eXist／WSO2 評估與 ImageJ loose-class 編譯、loader、檔案部署驗證。

## 限制與安全邊界

本地測試不表示正式環境權限、ACL、服務、檔案鎖定及 GitLab runner 已驗收。Hash 用於一致性，不等於來源簽章。CLI 確認／GitLab manual job 不取代公司核准與存取控制。

部署套件包含 PowerShell 程式碼，應整份審查並經受控管道交付。工具不建立沙箱；受信任檢查腳本仍須審查。復原還原檔案及服務狀態，不撤銷資料庫或外部副作用。
