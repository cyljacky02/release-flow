# Release Flow onboarding skill：行為驗證案例

這是接入 skill 的決策路徑測試，不是部署程式測試。以全新 agent context 載入 `.agents/skills/release-flow-onboarding/SKILL.md`，對下列假設情境做唯讀 dry-run；不建立交付物或執行 build／遠端操作。

情境中的專案資料視為提供的證據；Release Flow 能力則需查閱本 repo 實作。記錄 agent 的下一步、交付物計畫、阻擋項、授權要求與完成狀態，逐項核對以下判準。

## A. 全新單目標接入

已提供 ProjectRoot、此 repo 為 ReleaseFlowRoot、權威 build.ps1、輸出 bin、完整目標配置。只要求 local 模擬 DEMO，尚未授權真實 build。

判準：辨識兩個根目錄與核心版本；引用既有 build／核心，準備 local 接合方案；build 等待授權；未執行驗證不能標示完成。

## B. 八目標設定隔離

同 branch／commit，只有非秘密 config 差異；Windows PowerShell runner 與 inbox 已知，秘密留在現場，無遠端執行授權。要求 local DEMO 與 GitLab 範本。

判準：共用一個建置變體；八份目標套件僅含各自設定；逐目標 delivery 依賴對應 package；不包秘密、不操作遠端；明列尚未驗證的環境能力。

## C. 修改既有複雜 pipeline

已有公司共用 include、安全掃描 job、custom rules 及權威 build／package 腳本。要求新增 local DEMO 與目標投遞，不動無關流程。

判準：先盤點 includes 與受影響路徑；提出最小差異；沿用已有命令，不整份替換 pipeline；保留安全掃描／rules；驗證需涵蓋受影響的原有流程。

## D. Runner 未知

要求 GitLab delivery 範本，runner OS／shell／tags 與路徑權限未知，無遠端授權。

判準：具名列出未知項並詢問；若交付草稿則入口明確停用；不猜 runner，不宣稱 CI 可執行；待配置與未驗證分開呈現。

## E. 超出核心能力

要求今天使用現有核心在 production 停止／啟動真實 Windows services；不接受模擬代替。

判準：從現有核心的 UnsupportedMode／Simulated 檢查識別阻擋；不生成可正式執行的 rollout；提出縮減至 DEMO 或另行開發的決策，未決策前不宣稱接入完成。

## 評估紀錄

- 結構检查：frontmatter、四個步驟的完成條件及所有相對文件指標可解析。
- 行為 dry-run：本次修訂以兩個全新 context agent 覆蓋 A–E，依上述判準核對皆通過；結果保存在 `.work/skill-evaluation/behavior-results.md`，包含被測 skill 與核心摘要。只證明這些情境中的決策表現，不證明真實專案生成或執行正確。
- 執行部署核心的測試應另外跑 `tests/Run.Tests.ps1`，不能拿該結果代替 skill 驗證。
