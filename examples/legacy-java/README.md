# 真實 legacy Java 接入案例

研究對照與來源證據：[`docs/research/legacy-java-windows-candidates.md`](../../docs/research/legacy-java-windows-candidates.md)。三個案例各自覆蓋部分需求，沒有把它們拼成一個假稱真實的多服務系統。

## 結果與範圍

| 案例 | 實際做了什麼 | 沒有宣稱什麼 |
|---|---|---|
| eXist-db 3.6.1 | 取得固定 commit 的 13 個 source/config/script 檔案；7 個靜態檢查通過，2 個 Ant XML 以禁用外部實體的 parser 檢查 | 不是完整 checkout；未 build、未執行 Ant／BAT 或 YAJSW |
| ImageJ 1.51u | 編譯真實原始碼為 430 個 loose classes；使用真實 loader 做不初始化的 plugin class resolution；兩目標 file deployment/recovery 通過 18 個斷言 | 沒有啟動 GUI、執行 plugin、操作真實服務或驗收完整產品 |
| WSO2 EI 6.6.0 | 多 profile／YAJSW 服務接入規劃及阻擋項 | 未 build／投遞／部署；服務 graph 不憑空假設 |

固定 commits 及來源清單在 `sources.json`。下載來源為 GitHub HTTPS 的 commit URL，下載後記錄 SHA256；摘要不是獨立來源簽章。舊版本不代表安全版本，第三方檔案授權與來源需另行審查。

## 重跑 ImageJ 接合驗證

需要 Windows PowerShell 5.1、網路下載來源、`javac`／`java`。本次使用本機 Zulu JDK 25.0.4.1，compiler 的 `--release 8` 只指定輸出 API／bytecode，不證明整個產品在 Java8 runtime 上通過。

使用新工作目錄；scripts 拒絕重置既有目錄：

```powershell
$root = Join-Path $PWD ('.work/legacy-' + [Guid]::NewGuid().ToString('N'))
./scripts/legacy/Get-Sources.ps1 -Root $root
$metadata = Get-Content (Join-Path $root 'acquisition.json') -Raw | ConvertFrom-Json
./scripts/legacy/Inspect-Exist.ps1 -SourcesRoot $root -OutputPath (Join-Path $root 'exist-inspection')
$build = Join-Path $root 'imagej-build'
./scripts/legacy/Build-ImageJ.ps1 -SourcePath $metadata.ImageJSourcePath -OutputPath $build
./scripts/legacy/Verify-ImageJPlugin.ps1 -BuildPath $build -OutputPath (Join-Path $root 'loader-probe')
./scripts/legacy/Demo-ImageJ.ps1 -SourcesRoot $root -BuildPath $build -Root (Join-Path $root 'deployment-demo')
```

### 相較原 BAT 的明確調整

- 核對原 `compile.bat` 的五行內容；前四個 javac source groups 維持順序。
- 不執行第五行 `java ij.ImageJ`，也不直接執行上游 BAT。
- 將 source 複製至新 worktree，排除原始預編譯 `.class`；啟用 `-proc:none`，禁止 annotation processors 執行。
- 使用 JDK25 `--release 8`，並明確枚舉檔案，而不是依賴 shell wildcard 行為。
- 將上游真實 `plugins/JavaScriptEvaluator.source` 原樣複製為 `.java`，另行編譯為 `plugins/JavaScriptEvaluator.class`，不放進 JAR。
- 編譯輸出保留 package hierarchy；runtime loader probe 的 classpath 不含 plugin 目錄，由上游 `PluginClassLoader` 解析它。

Probe 執行本 repo 的小型 Java main 及已檢查的上游 loader constructor，使用 `Class.forName(name, false, loader)`；不初始化／實例化 plugin、不呼叫 `run`，不開啟 GUI。它證明 class resolution，不證明 plugin 業務功能或 JavaScript engine 在本 JDK 可用。

### 真實檔案與合成部署 fixture 的界線

ImageJ 來源、編譯 class、loader 及 external plugin 均是真實上游內容。兩台 fixture node、模擬 worker、`deployment/target.json` 與保護資料是本地測試 scaffolding，不是 ImageJ 原生設定／service topology。

初始 fixture 保存編譯的 core classes 及上游真實 `MacAdapter.class`；目標移除該舊 class，新增本次編譯的 `JavaScriptEvaluator.class`，並更新 exercise-only metadata。這不是兩個 ImageJ 發行版的升／降版。MacAdapter 的位元組只作檔案復原測試，從未載入／執行。

全流程使用現有共用 build/package/delivery/deployment 核心，不修改 Java 原始碼、不重新打成 JAR。備份後還原完整初始 fixture，並驗證原始 inbox 被移走時仍可復原。

輸出是 compilation／deployment fixture，不是完整可啟動 ImageJ 發行包：資源、GUI、完整 plugin 功能及 Windows services 都未驗收。

## 驗證證據

本次本地證據在 `.work/legacy-java-01/`：

- `acquisition.json`：固定來源與下載摘要。
- `imagej-final-build/build-attempt.json`、`javac.log`：五個 source groups 全部 exit 0，共 430 classes。
- `imagej-final-probe/probe-results.json`、`probe.log`：真實 loader 的非初始化 class resolution 通過。
- `imagej-final-demo/exercise-results.json`：18 個檔案部署／設定隔離／復原斷言通過。
- `exist-static-inspection/inspection-results.json`：7 個 source-only 檢查，未執行 legacy build。

## GitLab 草稿

`imagej/gitlab-ci.example.yml` 沿用相同 acquisition／build／probe／package／delivery 腳本，不另寫一套編譯或復原實作。它是未合併至根 pipeline 的 opt-in 範例，所有 jobs 預設停用；runner tag 明確標為待配置。按目標獨立依賴 package，正式 service／GUI 執行不在 pipeline 中。

啟用前必須確認 Windows runner、JDK、受批准的測試 inbox 及來源下載權限；同時審查 JVM probe 的授權範圍。以實際 GitLab instance 的 CI Lint 與測試 runner 驗收，再按最小差異合併至既有專案 pipeline。本地 YAML 解析通過不表示遠端 pipeline 通過。

eXist 的評估見 `exist/onboarding-assessment.md`；WSO2 的規劃見 `wso2/onboarding-plan.md`。這些規劃不計入 ImageJ 的測試成功數，也不代替正式服務整合驗證。
