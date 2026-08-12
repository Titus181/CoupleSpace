# CoupleSpace 測試控制中心

這個目錄是 CoupleSpace 測試與版本發布的索引，不取代實際測試程式。Swift unit／UI tests、Supabase pgTAP 與 Edge Function tests 仍留在原本可執行的位置：

- `CoupleSpaceTests/`
- `CoupleSpaceUITests/`
- `supabase/tests/database/`
- `supabase/functions/**/**.test.ts`
- `evals/`

## 文件

- [測試目錄](test-catalog.md)：穩定 ID、責任層級、實際程式位置與必要 gate。
- [版本發布閘門](release-gates.md)：開發、合併、TestFlight 與正式發布的阻擋規則。
- [回歸紀錄](regression-history.md)：曾經發生的缺陷及其永久 regression。
- [版本驗證紀錄模板](release-record-template.md)：每個 release candidate 的可稽核結果。
- `releases/`：依版本保存已填寫的 release record，不覆寫歷史結果。
- `manual/`：無法由 Simulator 可靠取代的真機、Apple 服務與資料生命週期清單。
- `scripts/run-full-automated-suite.sh`：目前全部本機自動化 gate 的單一入口。

## 日常流程

1. 行為改動前，找出受影響的 catalog ID 與風險。
2. 在最低可靠層級新增或更新測試；修 bug 時，盡可能先讓 regression 在修正前失敗。
3. 開發中跑 affected tests 與 affected target build。
4. 完成垂直切片後，跑相關 database／unit／UI／Harness gate。
5. 合併前跑完整 iPhone automated suite；TestFlight 或正式發布前依 `release-gates.md` 執行全部必要 gate。
6. 每次版本複製 `release-record-template.md` 到 `releases/`，記錄 commit、build、結果與人工證據。

統一腳本需要 RTK、Supabase CLI、Deno、Xcode command line tools，以及可用的本機 Supabase／Simulator 環境。缺少任一工具時會直接阻擋，不會跳過對應測試後假裝完整 suite 通過；可先使用 `--dry-run` 檢查預定命令。

## 新增測試的完成條件

- 分配不重複且穩定的 ID；既有 ID 不因檔名或實作重構而重用。
- 記錄防範的失敗、測試層級、實際路徑與適用 gate。
- 不為同一規則機械式複製 unit、integration 與 UI 測試。
- 真機項目必須寫出前置條件、操作、預期結果與證據，不得只寫「看起來正常」。
- 測試淘汰或改變語意時，在 PR／commit 與 catalog 記錄原因；不得為了變綠而靜默刪除 assertion。
- 測試 fixture、log、截圖與 `.xcresult` 不得包含 secrets 或真實私人內容。

## 證據保存

`.xcresult`、DerivedData、真機截圖與測試匯出通常不提交 Git。版本紀錄只保存必要統計、產生時間、commit、build、測試環境及安全的 artifact 路徑或 CI 連結。若 artifact 含帳號、通知或私人資料，先去識別並依最小保存原則處理。
