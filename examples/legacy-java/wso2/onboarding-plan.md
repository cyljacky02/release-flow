# WSO2 EI 6.6.0：多服務接入規劃（未執行）

來源與完整證據見 [研究報告](../../../docs/research/legacy-java-windows-candidates.md)。固定來源為 product-ei `bfdf341ab6dcfccce35c88b8a1567604f07ba8f5`；Carbon Kernel 4.5.3 固定為 `e07e00f16b91983e679d04f80aeba67fb08ebe39`。

## 可確認的部署拓撲

[官方 Windows service 文件](https://wso2docs.atlassian.net/wiki/spaces/EI660/pages/6522341/Running+the+Product+as+a+Windows+Service) 支援 ESB、business-process、broker、analytics profile，要求多服務使用獨立 server pack，避免共用檔案鎖定／併發問題。這不是四個服務已安裝的證據。

各 profile 需獨立盤點 application home、wrapper home/config、Windows service 名稱、端口、持久資料與 log。預設 `WSO2CARBON` 不可未經確認重複用於多個 SCM service。實際服務数量、相依關係、停止／啟動順序與驗證方式尚待指定環境提供，不由範例猜測。

## 接合方案

- 保留既有 Maven／產品打包流程與 OSGi JAR 布局，不改成 loose-class 模式。
- 共用已審查的產品產物，按 profile／部署目標組裝非秘密設定及投遞；各 delivery 只依賴自己的 package。
- 各 profile 保有獨立換版計畫與復原集；版本混用的可接受性需先確認。
- 設定、資料庫／消息資料、log、憑證與 secrets 的歸屬需逐一核對，不能把整個 server pack 都列為可覆蓋範圍。

## 阻擋與授權

| 項目 | 狀態／下一步 |
|---|---|
| 真實 YAJSW／Windows service 控制 | 當前 Release Flow 核心僅 Simulated，正式 rollout 阻擋；先開發及驗證支援或明確縮減為模擬 |
| 建置可重現性 | 固定 source commit 仍不夠：distribution POM 會抓 moving update.zip；需確認批准的產物與摘要／依賴來源 |
| JDK／YAJSW 配對 | 本機 JDK25，不視為已驗收的 legacy 配對；需隔離環境與確認版本 |
| Runner／inbox／service account | 未提供，pipeline 只能是停用草稿，不進行遠端操作 |
| 服務 graph、健康檢查、資料副作用 | 未提供；需決策後才產生可執行 deployment config |

未建立可正式執行的配置、未下載完整 EI distribution、未 build、未安裝／啟動任何服務。此案例驗證的是接入規劃與能力閘門，而不是產品部署成功。
