---
title: 上市、客服與版本發布營運
status: active
last_updated: 2026-08-12
---

# 上市、客服與版本發布營運

## 文件目的

本文件是 CoupleSpace 正式公開上市後的語系、客服、版本公告、雲端可靠性與成本營運規格。產品、工程、上架與客服皆由一人負責，因此所有流程以「單一 queue、可批次處理、可查詢、低中斷」為原則。

## 語系與市場邊界

- 公開上市 UI 同時支援繁中 `zh-Hant`、簡中 `zh-Hans`、英文 `en`、日文 `ja`。
- 繁中是產品文案 SSOT。功能名稱、狀態語意、隱私文案、錯誤訊息與客服答案先在繁中定稿，再翻譯至其他語言。
- 首輪只主動投放繁中市場。簡中、英文與日文先維持可用性與正確基本商店資訊，不同時建立在地廣告、創作者合作或內容行銷產線。
- 簡中只代表語言支援，首輪不上架中國大陸市場。未來若考慮進入，需另做法規、資料、商店供應、付款及客服評估。

### 單人翻譯工作流

1. 在繁中 canonical copy 定稿並賦予穩定 key。
2. 以 Xcode String Catalog 管理四語、複數、裝置差異與缺漏狀態。
3. 維護四語 glossary，特別固定 `Moment・此刻`、共同約定、解除配對、封存、匯出與隱私相關用語。
4. 機器翻譯只產生草稿；隱私、付款、刪除、解除配對、事故與 App Store 內容必須人工檢查。
5. 每次發布檢查截斷、日期／時間、動態字級、權限提示與關鍵流程；前三次正式發布記錄實際四語維護工時，再校準排程。

排程可先預留：小修補額外 1–2 小時、一般功能版本 4–8 小時、包含 onboarding、商店截圖或條款的大版本 12–24 小時。這些只是首輪規劃區間，不是已驗證工時；完成前三次正式發布後以實際紀錄取代。

## 客服入口與處理方式

### 分階段工具

- **TestFlight／種子期：** Apple TestFlight feedback 加上一個 `support@` 信箱。
- **公開低量期：** App 內「幫助與意見」表單接到單一 helpdesk。可先以 Plain Foundation 或同級一席方案 PoC；是否採購須在上線時依實際需要決定，不把特定供應商寫成不可替換架構。
- **知識庫：** 先以自有網站或 App 內 10–15 篇核心四語文章開始，不只為 Help Center 購買高階客服方案。
- **升級條件：** 只有當工單量、搜尋、權限或自動化節省的時間足以抵銷費用與 SDK 維護，才評估更高階 helpdesk。

Intercom 不作預設方案。可把「每月 inbound 超過約 100–150 張，且自動化預估能節省每週 5 小時以上」當作重新評估較重客服平台的規劃觸發點；實際採購仍由上線資料、隱私條件與總成本決定。

四種語言全部進入同一 queue，以 `zh-Hant`、`zh-Hans`、`en`、`ja` 標籤處理，不建立四個地址、四套 SLA 或四份獨立問題分類。

### 回覆承諾

- 不保證客服回覆時間，不承諾 24/7、幾小時或幾個工作日內回覆。
- 自動確認只說明「已收到」、提供 `feedback_id`、自助文章與服務狀態，不暗示真人已閱讀。
- 實際客服批次時段與每週工時依上線工單量、事故與開發排程決定，不預先固定為產品承諾。
- 涉及資料錯交、隱私、帳號遭入侵、資料遺失或付款的案件可提高內部分級，但內部優先級不轉化為公開 SLA。

### 工單資料與搜尋

每張工單至少保留：

- `feedback_id`、category、feature_area、severity、status、created_at。
- app version／build、iOS、device model、user locale、message language、reply language。
- `canonical_issue_key`、tags、linked issue、macro id／version、translation status。
- 經使用者同意的 pseudonymous user／relationship identifier 與最小診斷資料。

helpdesk 保留原文與回覆；產品 backlog 只保留去識別摘要、canonical issue、影響伴侶對數與工單連結。不得把私人訊息、照片或 Moment 內容做全文索引，也不得讓 AI 或客服供應商自動取得這些共同內容。

### 自助與回覆模板

- 上市前建立前 20 個問題的四語 macros，以及 10–15 篇核心 FAQ。
- 優先涵蓋登入、配對、同步、通知、訂閱、匯出、刪除、解除配對、已知問題與服務狀態。
- AI 可協助分類、摘要與翻譯草稿，但由人確認後送出；不得自動代表真人完成敏感決策。
- 相同問題以 canonical issue 聚合四語工單，修正產品後追蹤相關工單是否下降。

## 單人客服容量

正式容量只由上線資料決定。規劃時可使用：

`每週客服工時 = 活躍伴侶對 × 2 位 MAU × 月工單率 × 平均處理分鐘 ÷ 60 ÷ 4.33`

若暫以月工單率 2%、每張 20 分鐘估算：

| 活躍伴侶對 | 估計客服工時／週 |
| ---: | ---: |
| 500 | 1.54 小時 |
| 2,000 | 6.16 小時 |
| 5,000 | 15.40 小時 |
| 10,000 | 30.79 小時 |

此表不是工單預測、服務承諾或用戶上限。每週客服預算目前不定；上線後以真實月工單率、平均處理時間與開發負荷重算。當客服持續排擠可靠性與核心開發時，先暫緩投放、大型發布或新市場，修正前三大工單根因與自助內容。

## 使用者意見到產品決策

1. App 內送出結構化意見並取得 `feedback_id`。
2. helpdesk 以語言、版本、功能、嚴重度與 canonical issue 分類。
3. 每週檢視工單總工時、每千 MAU 工單、平均處理時間、重開率與 Top 10 問題。
4. 同一根因跨語言聚合，不以聲量最大的語言重複建立四張產品任務。
5. 產品 backlog 記錄問題、影響範圍、證據與工單連結，不複製私人內容。
6. 修正發布後比較 canonical issue 的工單率是否下降，據此關閉或繼續處理。

## 版本更新與事故公告

採三層公告，不使用客服信箱代替產品公告：

1. **App Store 版本說明：** 每次公開版本都提供四語短版，說明使用者可感知的新功能、重要修正及必要注意事項。
2. **App 內更新中心：** 保存較完整的版本歷史、已知問題、資料／隱私行為變更與相關 FAQ；只在新版本首次開啟時顯示一次非阻斷摘要。
3. **公開狀態頁：** 服務中斷、同步、登入、推播或資料處理事故使用狀態頁持續更新；客服回覆只連回同一事故項目，避免四語重複回答。

推播或 App 內強制提示只用於使用者必須採取行動、重大安全／資料風險或版本已無法安全使用的情況；一般功能更新不以推播打擾。公開發布優先使用 App Store phased release，並準備暫停發布、功能降級與回滾檢查表。

每次版本公告固定回答：

- 有什麼改變。
- 對使用者有什麼影響。
- 是否需要操作。
- 已知限制或修正中的問題。
- 哪裡查看服務狀態或提供意見。

## 雲端可靠性

- Supabase 是唯一遠端 SSOT；不建立 CloudKit 雙寫作為備援。
- Postgres constraint、RLS、RPC 與穩定 client UUID 保證授權及冪等；Realtime 只提示變更，client 重新經 RLS 讀取。
- 離線操作使用持久 outbox；事故時允許內容保留在裝置並顯示待送／失敗，不假裝已送達。
- 資料庫 PITR／備份不等於 Storage object 備份。公開付費前必須分別完成資料庫及照片復原演練，記錄實際可恢復範圍。
- 單人模式不公開承諾固定事故回覆或復原時間；以自動警報、狀態頁、降級模式、runbook、密碼管理器、離線 recovery codes 與緊急帳號恢復降低風險。
- 每週檢查 p95 latency、錯誤率、CPU／memory／DB size、連線、Realtime、Function、outbox age、Storage、egress 與異常成本斜率。

## 雲端成本與照片政策

成本主要由累積照片 Storage、媒體 egress、Realtime／Function 使用量與圖片轉換策略驅動，不應只以 MAU 推測。採下列控制：

- CoupleSpace 只保存適合共同時間線回顧的照片，不保存相機原始畫質檔案，也不宣稱可替代照片備份。
- iPhone 上傳前重新編碼，並評估固定 display JPEG 與 thumbnail；確切尺寸、壓縮品質與容量仍須真機畫質與成本測試。照片不按時間自動到期，成本以配額、警報與新增限制管理，不以靜默刪除既有內容控制。
- 使用分頁、增量同步、本機 disk cache、可重用的安全 URL 與適當 Cache-Control，避免每次開啟重抓完整歷史。
- 建立 50%／75%／90% 預算警報、每日異常斜率、每個活躍伴侶對成本與每張新增照片成本。
- 只有當真實數據顯示 egress、圖片處理或資料庫長期成為主要成本，才評估拆出專用物件儲存、CDN、升級 compute 或其他架構；不預先自架或雙寫。

2026-08-07 的規劃模型假設每對每天 2 張照片、每張重新編碼後 0.7 MB、每張每月下載 3 次，估計基礎 Supabase 月成本約為每個活躍伴侶對 US$0.026–0.035。這是依當日公開價格建立的情境，不含 PITR、異地物件備份、監控、客服 SaaS、人力、稅與退款，也不是 production 帳單。正式商業判斷必須以實際帳單與使用行為校準。

## 正式上市檢查

- 依[版本發布閘門](../../quality/release-gates.md)建立本次 release record；最後行為變更後的全部自動化測試，以及所有適用真機／資料生命週期 gate 均通過。
- 四語 UI、App Store metadata、版本說明、FAQ 與關鍵流程 QA 完成。
- 只啟動繁中市場投放；沒有中國大陸商店供應或市場活動。
- 單一客服 queue、案件識別、搜尋欄位、隱私同意、自動確認與狀態頁可用。
- 不承諾客服回覆時間；公開文案與 App 行為一致。
- 照片畫質適合共同回顧，且產品與商店文案未暗示原始畫質備份。
- 資料庫與 Storage restore drill、弱網／離線、兩支真機、推播隱私、匯出、刪除與解除配對 gate 通過。
- 成本警報、事故 runbook、phased release、暫停發布與降級流程完成。

## TestFlight 轉正式版的資料延續

階段一的真實使用者資料不是可丟棄 fixture。TestFlight 只負責 3–7 天熟人圈煙霧測試；進入 App Store 正式版時，同一段 relationship 的完整歷史必須無刪檔、無重建地接續使用。

- External TestFlight 與 App Store 正式 build 使用同一個正式 Bundle ID、帳號身分規則、穩定 user／relationship／client UUID，以及同一套正式遠端 SSOT；若發布架構需要環境搬移，必須先完成可重複、可稽核且已演練的資料 migration，不能要求使用者重新配對或手動搬資料。
- 開發 fixture、自動測試帳號與可回收壓力資料不得混入真實 production 資料；正式 TestFlight 開始前需確認 production 環境乾淨，dev／staging 仍保持分離。
- 聊天、照片、Moment、回應、共同約定、專屬討論、共同時間線、個人封存與必要關聯 metadata 均由遠端產品資料／私有 Storage 延續。分析事件、裝置 cache 或 TestFlight 安裝本身都不是資料備份。
- App Store 上架前必須以真實升級路徑演練：在 TestFlight 建立雙人資料與離線待送項目，安裝 release candidate／正式 build，重新登入或重新安裝後恢復 relationship 與完整歷史，確認待送項目只送達一次且沒有錯序。
- schema／Storage migration 預設採向後相容、可觀察及可回復方式；不得為正式上線重建 production 資料庫、改發新身分或靜默清空 client outbox。任何必要的破壞性 migration 必須先阻擋發布並另行取得明確決策。
- TestFlight 的 StoreKit／Sandbox 交易與測試 entitlement 不視為正式購買，也不搬成付費權益；正式上市的 30 天 Plus Launch Pass 由伺服器以 relationship 及活動資格獨立授予。
- TestFlight build 可暫時繼續運作不代表轉版完成。需在 App 內與測試通知提供清楚的正式版安裝指引，並在測試 build 到期前確認早期使用者已能由 App Store 接續使用。

## 手機遺失、換機與完整恢復

CoupleSpace 的恢復承諾以遠端 SSOT 為準。使用者遺失或損壞原手機、換機或重新安裝後，以同一帳號完成驗證，即可恢復本人有權存取的完整共同歷史；不能要求仍持有舊手機、由裝置對裝置搬移或重新配對。

- 恢復範圍至少包含 active／archived relationship、membership、聊天正文與 server timestamp、照片 metadata 與 Private Storage object、Moment／回應、共同約定／專屬討論、共同時間線、未讀／排序所需狀態，以及本人個人封存。
- server timestamp、穩定 client UUID、內容引用與 Storage object identity 必須維持，避免恢復後重複、錯序、斷裂或 Moment 無法返回原對話／約定。
- 上市前須以第二支已清除本機狀態的真實 iPhone 演練：同一帳號登入後重新取得 relationship，逐類核對數量、正文、照片可讀性、時間、順序與關聯，再執行重新安裝回歸。資料庫與 Storage restore drill 另須證明供應商／營運事故後仍能恢復兩者一致版本。
- 只有伺服器已接受並可由另一裝置重新讀取的內容才算已同步。仍在本機 Outbox、尚未完成遠端 metadata finalization 或上傳的內容，若裝置永久遺失就可能無法恢復；介面不得以模糊的成功狀態隱藏此限制。
- 正式用戶的完整內容只作 App 功能、同步、恢復、匯出、封存、安全與經授權支援之用。一般產品分析不讀取或複製正文、照片或回答；必要的 break-glass 維運存取須最小權限、指定原因、限時並留下 audit log。
- 若提供內容研究模式，兩位伴侶必須分別明確同意、可隨時撤回，並清楚顯示範圍與期間；不同意不得影響 Free、Plus、Launch Pass 或核心功能。

## 尚待上線資料決定

- 每週實際可投入客服的工時與批次時段。
- 採用哪一個 helpdesk 供應商，以及何時需要付費知識庫或更高階自動化。
- 確切照片尺寸、壓縮品質、容量與免費／Plus 正式限制；保存生命週期已由 PD-022 定案。
- 繁中以外市場的主動投放順序；中國大陸市場不在本輪候選內。

## 外部參考

- [Apple：Localize App Store information](https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information/)
- [Apple：String Catalog](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)
- [Apple：View TestFlight feedback](https://developer.apple.com/help/app-store-connect/test-a-beta-version/view-tester-feedback)
- [Apple：Release a version update in phases](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases)
- [Supabase：Pricing](https://supabase.com/pricing)
- [Supabase：Database backups](https://supabase.com/docs/guides/platform/backups)
- [Supabase：Production checklist](https://supabase.com/docs/guides/deployment/going-into-prod)
- [Supabase：Storage scaling](https://supabase.com/docs/guides/storage/production/scaling)
- [Supabase：Smart CDN](https://supabase.com/docs/guides/storage/cdn/smart-cdn)
- [Plain：Pricing](https://www.plain.com/pricing)
