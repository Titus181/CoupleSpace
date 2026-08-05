---
title: W1 技術驗證紀錄
status: in_progress
last_updated: 2026-08-05
---

# W1 技術驗證紀錄

## 本週決策方式

W1 不先完成正式產品架構。先以最小真機 spike 驗證最大未知數，再依結果接受或否決候選方案。

目前並行驗證 Apple 原生 CloudKit Sharing，以及具備伺服器端身分、關係範圍授權、Realtime、物件儲存與推播 worker 的 Supabase。兩者都仍是 provisional 候選；必須完成各自尚缺的真機、弱網、資料生命週期與通知證據後，才進行正式架構決策。

## 候選方案狀態

| 閘門 | CloudKit Sharing 假設 | 驗證狀態 | 否決條件 |
| --- | --- | --- | --- |
| 身分與配對 | 使用 iCloud 帳號接受私人 `CKShare`，一個 share 對應一段伴侶關係 | 真機 A＋Simulator B、兩個 Apple ID 初步通過；兩支真機待驗證 | 無法穩定接受、恢復或限制為正確兩人 |
| 同步與聊天 | `CKSyncEngine` 同步 private/shared database；client UUID 形成穩定 record name；server timestamp 加 UUID 決定順序；本機 outbox 顯示傳送狀態 | 純規則測試已建立；共享標記雙向寫入與重啟恢復初步通過，離線與正式同步模型未驗證 | 離線重送造成遺失、重複、不可預期錯序，或 shared database 行為不足以可靠恢復 |
| 照片 | 顯示圖與縮圖先在裝置端重新編碼，再以 `CKAsset` 儲存；正式尺寸、品質、容量與保存期依實測決定 | 真機 A＋Simulator B、兩個 Apple ID 的雙向讀寫與重啟恢復初步通過；兩支真機、弱網與刪除待驗證 | 成本、速度、弱網恢復或刪除一致性不可接受 |
| 推播 | database subscription 只作變更提示；抓取並驗證 relationship/recipient 後才更新 App；使用者可見內容固定為泛化文案 | 資料最小化規則測試已建立；真機未驗證 | 錯發、鎖定畫面洩漏內容，或背景同步不足以支撐體驗 |
| 所有權與解除配對 | 雙方各自保留不可被對方剝奪的唯讀封存 | A1 政策已確認；Supabase 本機 RLS／封存測試、雲端 schema、Swift client、兩個 Apple 身分 Auth 與雙身分 pairing／RLS 通過；雲端第三身分拒絕與封存實測待驗證 | 無法提供雙方可理解、可稽核且不依賴單方善意的保留、匯出、刪除結果 |
| 有意義雙向互動 | 同一 relationship、同一 interaction object 內，兩個目前伴侶各至少有一次符合資格的 contribution；只記 ID、種類與時間，不記內容 | 純規則測試已建立 | 事件無法區分單方重複操作與真正雙方參與，或需要記錄私密內容 |

## CloudKit Sharing PoC

### 自動化範圍

- `MessageIdentity` 以 client UUID 產生穩定 record name，同一次重試不得建立第二筆訊息。
- delivery reducer 明確區分 queued、sending、sent、failed 與嘗試次數。
- 已有 server timestamp 時，以 server timestamp 排序；同時間以 UUID 穩定打破平手。
- 通知顯示文案不含訊息、照片或 Moment 內容。
- 有意義雙向互動必須包含預期的兩位不同參與者。
- 照片 record name 只由 client UUID 形成，不保存使用者原始檔名。
- 照片顯示圖最長邊限制為 1,600 px，縮圖最長邊限制為 320 px，且小圖不放大。

這些測試只證明 deterministic 規則，不證明 Apple 服務跨裝置可用。

### 真機操作前提

1. Xcode 的 `CoupleSpace` target 使用有效 Team 自動簽章。
2. `Signing & Capabilities` 具有 iCloud capability，勾選 CloudKit，container 為 `iCloud.com.titus.CoupleSpace`。
3. 兩支 iPhone 安裝同一個 Development build，分別登入不同且可用的 iCloud Apple ID。
4. 不使用 production container；本次只驗證 development environment。

### 兩支 iPhone 驗證步驟

1. 裝置 A 開啟「W1 技術驗證」，檢查 iCloud 帳號，建立共享關係 PoC。
2. A 點「邀請另一個 Apple ID」，以私人邀請傳給裝置 B。
3. B 接受分享並回到 App；不得將分享設為 anyone-with-link。
4. A 寫入驗證標記，B 重新整理並記錄看到的相同值與時間。
5. B 寫入另一個標記，A 重新整理並記錄看到的相同值與時間。
6. 將 App 強制結束並重開，雙方都應能再次重新整理同一筆記錄。
7. B 暫時離線時寫入的行為與錯誤必須明確；恢復網路後再測一次，不將手動重複點擊誤判為可靠重試。

### 通過證據

- 裝置型號、iOS 版本與 App build。
- 兩個不同 Apple ID 的確認，但不得記錄完整 Email、token 或其他秘密。
- 邀請接受、A→B 與 B→A 標記、重啟恢復的結果與時間。
- 任一 CloudKit 錯誤的完整錯誤碼；截圖不得包含私人通知或其他無關內容。

### 2026-08-04 初步實測證據

本次以一支真實 iPhone 作為 owner、一台 iPhone 17 Pro Simulator（iOS 26.5）作為 participant，分別登入兩個不同 Apple ID。App 為 development build `1.0 (1)`；真機型號與 iOS 版本未記錄。未保存完整 Email、token 或分享 URL。

- 真機 A 的 iCloud 帳號檢查可用，成功建立私人共享根記錄並邀請指定 participant。
- Simulator B 接受邀請後，可重新整理 shared database 的同一筆根記錄。
- A 寫入標記 `e15f87ab`，B 重新整理後看到相同值。
- B 寫入標記 `30f811e4`，A 重新整理後看到相同值。
- 雙方強制結束 App、重新開啟並重新整理後，仍看到 `30f811e4`。
- 真機首次啟動曾因未使用的預設 SwiftData container 無法載入而中止；移除該啟動依賴後真機正常執行。
- Simulator 首次開啟邀請時，App bundle 缺少 `CKSharingSupported`；改由來源 Info.plist 明確提供該鍵並確認建置產物為 `true` 後，邀請可交給 App 接受。

此結果只證明 development environment 中，真機與 Simulator 的跨 Apple ID 私人分享、雙向標記與前景重啟恢復可行。它不等同兩支真實 iPhone，也不涵蓋背景同步、推播、弱網、離線重試或資料生命週期；照片證據另記於下節，因此 G1 與 M0 仍未通過。

### 照片 `CKAsset` spike

目前 PoC 允許任一 participant 使用系統照片選擇器挑選一張圖片。App 解碼後重新繪製為 JPEG，產生最長邊 1,600 px 的顯示圖及 320 px 的縮圖，以兩個 `CKAsset` 儲存在根記錄下的 `PhotoPoC` 子記錄；根記錄只保存最新照片的 record name。此設計利用 parent hierarchy 讓子記錄沿用既有私人 `CKShare`，不保存原始檔名，也不新增照片庫完整存取權限。

本階段只驗證單張最新照片，不代表正式相簿、快取、上傳佇列、保存期限或刪除策略。真機驗證步驟：

1. 真機 A 選擇一張不含私人內容的測試照片並完成上傳。
2. Simulator B 點「重新整理共享照片」，應看到同一張縮圖。
3. B 加入另一張非私人測試照片後，A 重新整理應看到相同縮圖。
4. 雙方強制結束並重開 App，再次重新整理仍應看到最新照片。
5. 弱網、離線錯誤、取消選取、較大照片、旋轉方向與刪除一致性另行記錄，不以重複手動點擊當成可靠重試。

### 2026-08-04 照片初步實測證據

沿用上述真實 iPhone A 與 iPhone 17 Pro Simulator B、兩個不同 Apple ID 的 development 環境，使用不含私人內容的測試圖片驗證：

- A 選擇並上傳測試照片後，B 重新整理可讀取並顯示同一張共享照片。
- B 選擇並上傳另一張測試照片後，A 重新整理可讀取並顯示同一張共享照片。
- 雙方強制結束 App、重新開啟並重新整理後，仍可讀取最新共享照片。

此結果初步證明單張最新照片的 `CKAsset` 子記錄可在 shared database 中雙向寫入與恢復。它不等同兩支真實 iPhone，也不涵蓋弱網、離線重試、大圖與方向組合、保存期限或刪除一致性，因此照片架構仍維持 provisional。

## 共同資料生命週期決策前提

Apple 的 [`CKShare.Participant`](https://developer.apple.com/documentation/cloudkit/ckshare/participant) 文件確認：participant 接受私人分享後，只有在狀態維持 `accepted` 期間能存取共享記錄；私人分享由 owner 管理 participant；只有 owner 能刪除共享 hierarchy 的根記錄；participant 嘗試刪除 share 時，只會將自己移出該 share。

因此可推導出以下限制：CloudKit Sharing 原生 owner／participant 模型可以支援兩人共同使用，但無法單獨保證解除配對後的對等結果。owner 可在 App 流程外停止分享，使 participant 在完成匯出或建立個人封存前失去存取；participant 也無法自行刪除 owner 的共享根記錄。若產品要求任何一方都不能單方面阻止另一方保留或刪除其應得資料，必須增加受管後端或接受明確的 best-effort 邊界。

### 已確認政策與否決方案

| 候選 | 解除配對後結果 | CloudKit-only 可行性 | 主要風險 |
| --- | --- | --- | --- |
| A1（accepted） | 雙方各自保留一份不可被對方剝奪的唯讀共同歷史；之後可獨立匯出或刪除自己的封存 | 不足：正常 App 流程可在停止分享前建立個人封存，但 owner 仍可在流程外先撤銷存取 | 無法保證 participant 永遠有時間完成封存，因此正式架構需驗證受管後端 |
| B | 共同歷史由雙方一起刪除，解除後都不保留 | 不足：只有 owner 能刪除共享根記錄 | participant 必須信任 owner 完成刪除 |
| C | owner 保留，participant 解除後失去共同歷史 | 原生模型最簡單 | 權利不對等，與「共同生活空間」定位衝突 |

2026-08-05 已確認採 A1，且雙方保留權不可被另一方單方面剝奪是硬性需求。因此 CloudKit Sharing 保留為 Apple 原生能力驗證結果，不升格為正式共同資料架構；下一步建立受管後端最小 spike，驗證伺服器端對等授權、封存確認與個人封存隔離。現階段仍不實作解除配對或刪除真實遠端資料。

## 受管後端候選

| 候選 | 符合項目 | W1 風險 | 結論 |
| --- | --- | --- | --- |
| Supabase | Swift SDK；Apple 登入；Postgres constraint／transaction；RLS；Realtime；Storage；Edge Functions | iPhone 離線佇列需由 App 明確實作並驗證 | 第一個 provisional spike 候選 |
| Firebase | Apple 登入；Firestore Security Rules；Realtime listener；Storage；Cloud Functions；Apple 平台預設離線 persistence | 同一 document 的離線衝突採 last-write-wins；A1 的關係與封存不變量需額外由 transaction／server function 協調 | 保留為替代候選 |

Supabase 的 [Swift 入門](https://supabase.com/docs/guides/getting-started/tutorials/with-swift)涵蓋 Auth、Postgres RLS 與 Storage，[Swift reference](https://supabase.com/docs/reference/swift/introduction)亦涵蓋 database changes、Edge Functions 與檔案；Apple 登入由 [Login with Apple](https://supabase.com/docs/guides/auth/social-login/auth-apple)支援。Firebase 的 [Apple 登入](https://firebase.google.com/docs/auth/ios/apple)、[Firestore Security Rules](https://firebase.google.com/docs/firestore/security/overview)與[離線資料](https://firebase.google.com/docs/firestore/manage-data/enable-offline)也符合候選能力；Firestore 官方文件明確指出多次離線修改同一 document 時採 last-write-wins。

本輪先選 Supabase，不是因為 Firebase 不可行，而是 A1 優先需要可測試的一對一唯一約束、伺服器 transaction、兩份 owner-isolated archive 與可審查的 RLS。訊息離線、冪等及排序仍採既有明確 outbox／client UUID／server timestamp 規則，不把資料庫自動同步當成可靠傳送證據。

### Supabase spike 通過條件

1. 兩個測試身分只能讀寫同一段 active relationship，第三人完全不可見。
2. 一個身分同時最多只能有一段未封存 relationship。
3. relationship 進入 `closing` 後，雙方都不能新增共同內容。
4. 每位 participant 的封存由伺服器從共同資料建立，且只有該 participant 可讀取、匯出或刪除。
5. 兩份個人封存都完成前，relationship 不得轉為 `archived`；刪除其中一份個人封存不得影響另一份。
6. 以上 constraint、function 與 RLS 必須在本機資料庫測試中同時涵蓋允許與拒絕案例，再進入雲端專案或 Swift SDK 整合。

### 2026-08-05 Supabase schema spike 證據

以 Supabase CLI 2.111.0 與 local stack 建立可重現 migration，先在本機驗證後再部署至專用雲端測試專案。schema 只保存 relationship、membership、無內容 shared item 與 personal archive metadata，不含真實訊息、照片或帳號資料。

- `supabase db reset --local` 成功從 migration 重建資料庫。
- `supabase test db` 的 16 個 pgTAP 案例全部通過：兩位 member 可見、第三人拒絕、一人不可同時加入兩段未封存關係、active 可寫、closing 禁止新內容、單方封存不足以結束、雙方封存後才 archived、伺服器複製共同項目、個人封存只能本人讀取與刪除、刪除一方封存不影響另一方。
- `supabase db lint --local` 回報沒有 schema error。
- 第一次測試曾抓到 PL/pgSQL 變數與欄位同名造成的 ambiguous reference；重新命名、重建資料庫後通過，未以 retry 或放寬 policy 掩蓋。
- 遠端 dry-run 只列出 `202608050001_w1_relationship_archive_spike.sql`；取得明確授權後已套用至雲端測試專案。
- 遠端 migration 歷史顯示 local／remote 皆為 `202608050001`，再次 dry-run 回報資料庫已是最新狀態。
- `supabase db lint --linked` 對遠端 `extensions` 與 `public` schema 回報沒有 schema error。
- iPhone target 已加入官方 `supabase-swift` package，解析並鎖定至 2.54.1；App composition 可從 bundle 設定建立 `SupabaseClient`。
- Project URL 可提交；publishable key 只由被 Git 忽略的 `Config/Secrets.xcconfig` 注入。repo 只保存無值的 include 與範本，產出的 App plist 已確認具有正確 URL 與 publishable-key 類型值，驗證過程未輸出 key。
- iPhone Simulator build 與 `build-for-testing` 通過，新增的設定允許／拒絕測試可編譯。`xcodebuild test` 在 Simulator runner 啟動階段約 90 秒無測試事件後人工中止，因此不可標示 runtime unit tests 通過。
- 人工啟動 iPhone 17 Pro Simulator 可正常顯示 W1 畫面。Supabase 2.x 首次啟動曾輸出 initial-session 遷移警告；client 明確啟用 `emitLocalSessionAsInitialSession` 新行為後重新啟動，Console 已確認無相同警告。正式登入狀態仍須在使用 session 前檢查 `isExpired`。

此階段先驗證本機 Postgres constraint、transaction、security-definer function 與 RLS 測試、相同 migration 的雲端部署與 schema lint，以及 Swift SDK 的設定、連結與建置；後續 Apple Auth 與雙身分 RLS 實測證據記於下節。Realtime、Storage、弱網、Push、服務中斷與計費仍未驗證，因此 Supabase 仍是 provisional 候選，不能標示為正式架構。

### Supabase Apple Auth 原生 spike

W1 App 已加入原生 `SignInWithAppleButton`，每次請求建立隨機 nonce，傳給 Apple 前以 SHA-256 雜湊，取得 Apple identity token 後再將原始 nonce 與 token 交給 Supabase `signInWithIdToken`。App 不要求姓名或 Email scope，不記錄 token、nonce、完整 Apple ID 或完整 Supabase user ID；畫面只顯示 Supabase UUID 的前八碼供雙身分實測辨識。

登入狀態由 Supabase `authStateChanges` 恢復。local session 若已過期，只顯示「等待更新」而不視為登入成功；有效 session 才開放登出操作。純規則測試涵蓋無 session、過期 session 與有效 session，並以固定輸入驗證 nonce 雜湊；iPhone Simulator unsigned build 與 `build-for-testing` 均通過。沿用先前 runner 卡住的限制，本輪未宣稱 runtime unit tests 通過。

### 2026-08-05 Apple Auth 實測證據

Supabase Apple provider 已啟用，`com.titus.CoupleSpace` 的 App capability、entitlement 與 development signing 生效。以先前的 iPhone 17 Pro Simulator（iOS 26.5）Apple ID B 與真實 iPhone Apple ID A 分別登入：

- Simulator B 建立 Supabase user `260fd271…`；第一次 Apple authorization 在取得 credential 前回報 `AKAuthenticationError -7071`／`AuthorizationError 1000`，第二次成功。強制結束 App 後 session 正常恢復，登出正常。
- 真機 A 建立不同的 Supabase user `6b60ac09…`；首次登入成功，強制結束 App 後 session 正常恢復，登出正常。
- App 畫面與紀錄只保留 UUID 前八碼，未保存完整 user ID、Apple ID、Email、identity token、nonce 或 Supabase session token。

兩個原生 Apple 身分、token 交換、session 恢復與登出均通過，因此 Apple Auth 閘門關閉。Simulator 首次錯誤列為非阻塞的 Apple authorization 暫時失敗；若真機重現或失敗率升高才重新開啟調查。

### Pairing invitation RPC

新增 migration `202608050002_w1_pairing_invitation_rpc.sql`，提供兩個只授權給 `authenticated` 的 security-definer RPC：建立／取回一小時有效的 invitation，以及由另一個身分接受 invitation。Invitation table 不授權 App 直接讀取；建立者不能接受自己的 token，已使用或過期 token 使用相同拒絕結果，並沿用每人最多一段 active relationship 的唯一約束。建立者在 invitation 尚未接受時可再次取得同一 token；若已過期則由伺服器輪替，避免 App 重啟後永久失去 pairing 能力。

- 本機資料庫由兩個 migrations 完整重建成功。
- 新舊兩份 pgTAP 共 28 個案例全部通過；新增案例包含 invitation 建立／恢復、本人拒絕、第二人接受、第三人不能重用、已配對者不能建立第二段關係、過期拒絕與建立者輪替過期 token。
- `supabase db lint --local` 對 `extensions`／`public` 無 schema error。
- Swift W1 畫面已加入 invitation 建立／分享／接受、relationship member count、RLS marker 寫入與重新整理；iPhone Simulator `build-for-testing` 通過。
- 遠端 dry-run 只列出 `202608050002_w1_pairing_invitation_rpc.sql`，未包含 seed、role 或其他 migration；取得明確授權後已部署。
- 遠端 migration history 顯示 local／remote 皆有 `202608050001` 與 `202608050002`；部署後再次 dry-run 回報已是最新狀態，`db lint --linked` 對 `extensions`／`public` 無 schema error。
- 推送完成後，CLI 的 migration catalog 快取輔助步驟曾發生 2.5 秒連線逾時；migration history、再次 dry-run 與 linked lint 三項獨立驗證均成功，因此不影響部署結果。

### 2026-08-05 雲端雙身分 pairing／RLS 實測證據

沿用真機 A 的 Supabase user `6b60ac09…` 與 Simulator B 的 `260fd271…`，只建立無內容的 W1 測試 relationship 與 marker metadata；未保存 invitation token 或完整 user ID。

- A 建立一次性 invitation，B 成功接受；兩端重新整理後都看到 relationship `201d2338…`、狀態 `active` 與成員 `2/2`。
- B 寫入新的 RLS marker 後，A 重新整理能看到同一標記；A 再寫入另一標記後，B 重新整理也能看到對方標記。標記完整值未記錄。
- 兩端強制結束 App 並重開後，Supabase session、同一 relationship 與 `2/2` membership 都能重新載入。

此結果通過兩個正確 member 的雲端 RPC、RLS select／insert 與前景重啟恢復允許路徑。第三身分不可見仍只有本機 pgTAP 證據；closing 與雙份 personal archive 的後續雲端證據另記於下節。

### Supabase Realtime spike

W1 Swift client 已加入 relationship-scoped `shared_items` insert 訂閱。訂閱只以 relationship UUID 作伺服器端 filter；收到事件後不直接信任或顯示 payload，而是重新執行既有 RLS select 取得最新 marker。登出、找不到有效 relationship 或手動停止時會移除 channel，避免下一個身分沿用前一個訂閱。

新增 migration `202608050003_w1_shared_items_realtime.sql`，以可重複執行的條件將 `public.shared_items` 加入 `supabase_realtime` publication。新增 pgTAP assertion 驗證 publication membership；本機三份測試共 29 個案例通過，`public` schema lint 無錯誤，iPhone Simulator unsigned `build-for-testing` 通過。

取得明確授權後已將 migration 部署至雲端。原始 push 在顯示套用成功後未自行結束，於遠端 migration history 已確認 local／remote 都有 `202608050003` 後中止 CLI 收尾程序；後續單一連線 dry-run 回報遠端已是最新狀態，`db lint --linked --schema public` 無錯誤。雙裝置免手動重新整理的實際事件傳遞尚未驗證，因此 Realtime 閘門仍為待實測。

### 2026-08-05 雲端 Realtime 實測證據

沿用真機 A 與 iPhone 17 Pro Simulator B 的兩個 Apple 身分及 relationship `201d2338…`。兩端都載入狀態 `active`、成員 `2/2` 並啟動 relationship-scoped Realtime：

- A 寫入新的 marker 後，B 未按重新整理便收到事件，重新執行 RLS select 並顯示新 marker。
- B 寫入另一個 marker 後，A 同樣未按重新整理便收到事件並顯示新 marker。
- 截圖顯示狀態「收到 Realtime 變更，已重新讀取 RLS 資料」；未記錄完整 marker、user ID 或其他 payload。

此結果通過同一 active relationship 內兩個正確 member 的雙向 Realtime insert 通知，以及事件後重新讀取 RLS 資料的 client 行為。斷線重連、背景喚醒與第三身分無法訂閱仍未由本次成功推論為通過。

### Supabase Storage 私有照片 spike

新增 migration `202608050004_w1_private_photo_storage.sql`，建立非公開 bucket `couplespace-w1-photos`，單檔限制 5 MiB 且只接受 JPEG。物件路徑固定為 `relationship UUID/client UUID.jpg`，不保存原始檔名；只有 active relationship member 可讀，只有上傳者可刪，第三身分不可讀寫，relationship 進入 `closing` 後禁止新增照片。

Swift W1 client 沿用既有最長邊 1,600 px、JPEG quality 0.8 的裝置端重新編碼，先上傳 Storage，再以相同 client UUID 寫入 `shared_items` photo metadata；若 metadata 寫入失敗會嘗試刪除 orphan object。另一端由 RLS 取得最新 photo client UUID，再從私有 bucket 下載，不使用 public URL。

本機四份 pgTAP 共 39 個案例通過，包含 bucket privacy／大小、兩位 member 讀取、第三人拒絕、非上傳者不可刪、closing 禁止上傳與上傳者可刪；刪除測試使用 Storage API 同等的 `storage.allow_delete_query` 受控旗標，未停用 Supabase 的直接刪除保護 trigger。iPhone Simulator unsigned `build-for-testing` 通過。migration 已部署至雲端；遠端 migration history 顯示本機與遠端 `202608050001`～`202608050004` 一致，後續 dry-run 回報資料庫已是最新狀態，linked `public` schema lint 無錯誤。CLI 在套用 `004` 後未自行返回，經 migration history 確認成功後中止等待程序。

### 2026-08-05 雲端 Storage 跨裝置實測證據

沿用同一 active relationship 內的真機 A 與 iPhone 17 Pro Simulator B，以及各自的 Apple 身分：

- A 上傳私有測試照片後，B 手動重新整理 Supabase Storage 照片並成功顯示該照片。
- B 上傳另一張私有測試照片後，A 手動重新整理並成功顯示該照片。
- 截圖顯示私有照片上傳成功狀態、照片預覽與重新整理操作；未記錄 Storage object path、完整 relationship ID 或 user ID。

此結果通過同一 active relationship 內兩位 member 的私有照片雙向上傳、metadata RLS 查詢與 private bucket 下載。自動即時更新、第三身分的雲端拒絕、closing／archive、弱網與刪除一致性仍未由本次成功推論為通過。

### Supabase closing／personal archive client spike

W1 Swift client 已接上既有 `begin_unpairing` 與 `seal_personal_archive` RPC，並加入明確的不可逆確認：第一步將測試關係轉為 `closing`，第二步由每位成員各自建立 owner-isolated personal archive。client 可顯示自己的封存項目數；雙方完成後，active relationship RLS 不再回傳共同關係，畫面只保留本人可讀的封存狀態。

原 Storage policy 只允許 active member 讀取，會讓 relationship archived 後的 personal archive 留下 photo metadata 卻失去實際照片。新增 migration `202608050005_w1_archived_photo_access.sql`，讓持有該 relationship personal archive 的 owner 繼續唯讀原私有照片；刪除自己的 archive 只撤銷自己的存取，另一方仍可讀。Swift client 會由 personal archive item 的 client UUID 讀取照片，仍不使用 public URL。

此變更不決定正式解除配對 UX、匯出格式、保存期限、兩份 archive 都刪除後的 object GC 或刪除排程。本機 reset 已成功套用 `001`～`005`；五份 pgTAP 共 46 個案例通過，新增案例涵蓋 archived 後雙方可讀照片、第三人不可讀，以及單方刪除 archive 不影響另一方；`public` schema lint 無錯誤，iPhone Simulator unsigned build 通過。

取得明確授權後已將 `005` 部署至雲端測試專案。遠端 migration history 顯示本機與遠端 `202608050001`～`202608050005` 一致，後續 dry-run 回報資料庫已是最新狀態，linked `public` schema lint 無錯誤。CLI 在套用後未自行返回，經 migration history 確認成功後中止等待程序。

### 2026-08-05 雲端 closing／personal archive 實測證據

沿用同一 relationship 內的真機 A 與 iPhone 17 Pro Simulator B，以及各自的 Apple 身分：

- A 開始解除配對後，兩端重啟 App 都顯示 relationship `closing`。
- closing 狀態下，兩端分別嘗試新增 marker 與上傳照片，四個共同資料寫入操作都被伺服器拒絕。
- 兩端各自完成 personal archive 並重新整理後，各自顯示封存項目數 `8`。
- 兩端都能從自己的 personal archive 讀取原私有照片；未記錄照片內容、object path、完整 relationship ID 或 user ID。

此結果通過 closing 後禁止共同 marker／photo 寫入、雙方各自建立 owner-isolated archive，以及 archived photo 的雙方唯讀允許路徑。第三身分的雲端拒絕、刪除單方 archive 後的實際存取撤銷、雙方都刪除後的 object GC 與兩支真實 iPhone 仍未由本次成功推論為通過。

## W1 尚未關閉

- CloudKit Sharing 的兩支真實 iPhone、兩個 Apple ID 雙向證據。
- 以雲端 Supabase 測試專案驗證第三身分拒絕與 archive 刪除／GC；兩個 Apple 身分的 Auth、pairing、active relationship RLS marker、Realtime 雙向事件、Storage 私有照片雙向讀寫，以及 closing／雙份 personal archive／archived photo 已通過。
- 照片弱網、離線重試、大圖與方向組合、保存期限及刪除一致性實測。
- 推播接收者、背景同步與鎖定畫面隱私真機實測。
- 最終登入、同步、聊天、照片、推播與資料生命週期架構決策。

在上述證據完成前，G1 與 M0 維持未通過，不進入大量功能實作。
