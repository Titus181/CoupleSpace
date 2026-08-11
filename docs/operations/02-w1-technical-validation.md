---
title: W1 技術驗證紀錄
status: in_progress
last_updated: 2026-08-10
---

# W1 技術驗證紀錄

## 本週決策方式

W1 不先完成正式產品功能。先以最小真機 spike 驗證最大未知數，再依結果接受或否決候選方案。

2026-08-06 已接受 TD-001：Supabase 是 iPhone v1 使用者身分、伴侶關係、共同資料與資料生命週期的唯一遠端系統紀錄；CloudKit Sharing 保留為實驗證據，不進行雙寫。PD-022 已接受照片不按時間自動到期，並沿用 active relationship、owner-only 個人封存、明確刪除與最後引用 GC 的既有生命週期。個人封存匯出候選已通過真機交付與內容核對，但匯出大型資料、production 推播與必要真機證據仍未完成，因此 G1 與 M0 尚未通過。

## 候選方案狀態

| 閘門 | TD-001 已接受方向 | 驗證狀態 | 尚未關閉的風險 |
| --- | --- | --- | --- |
| 身分與配對 | Sign in with Apple credential 交由 Supabase Auth；Postgres constraint、RLS 與 RPC 管理一對一 relationship | 真機 A＋Simulator B、兩個 Apple ID 的登入、配對、session 恢復與雙向 RLS 初步通過；遠端測試專案的第三 authenticated UUID 對 relationship、memberships、shared items、personal archives 與 Storage 均不可見，四種敏感 RPC 亦拒絕 | 兩支真實 iPhone 待驗證 |
| 同步與聊天 | Realtime 只作變更提示並重新經 RLS 讀取；client UUID、server timestamp 與持久 outbox 提供冪等和穩定順序 | 單筆及三筆 FIFO marker metadata outbox 的斷網、重啟、重連、順序與雙裝置一致性通過；message／marker 各 100 筆本機持久化與完整 FIFO drain regression 通過 | 正式訊息內容、長佇列真機壓力、自動排程與弱網仍待驗證 |
| 照片 | 裝置端重新編碼後存入 Supabase 私有 Storage；metadata 經 relationship RLS 管理；不按時間自動到期 | 真機 A＋Simulator B 雙向讀寫、重啟恢復、封存唯讀與最後引用 GC 通過；三張持久 FIFO upload outbox 的斷網、跨啟動、重送與順序通過，另有 32 筆本機檔案持久化／FIFO drain regression；實際 JPEG regression 證明大圖縮放、方向正規化與 GPS 移除，真機高解析直向照片跨裝置方向／比例亦通過；closing orphan reconciliation、月 30 張／累積 1 GB 配額與拒絕後 orphan 清理均通過遠端實測；PD-022 的保存政策與既有 lifecycle 一致，不需 migration | 頻繁弱網與真機容量壓力待驗證 |
| 推播 | 伺服器驗證 relationship／recipient 後才送出泛化 APNs 文案；App 收到提示後重新讀取 | migrations 009／010、APNs secrets 與 Edge sender 已部署；兩支真實 iPhone 的雙向背景、終止與鎖定 development sandbox 通知皆成功，既有 Watch 鏡像通知亦成功 | 仍需 production／TestFlight 證據 |
| 所有權與解除配對 | Supabase 伺服器建立雙份 owner-isolated 唯讀封存，兩人可獨立刪除或匯出 | closing、雙份封存、archived photo、owner-only 獨立刪除與最後引用 Storage GC 的雲端實測通過；version 1 manifest＋JPEG 資料夾候選通過真機交付核對，64 張／4 MiB 合成照片磁碟 staging、部分 staging 清理與下載前容量預檢 regression 通過；migration 013 已部署測試專案 | 最終格式、大型真機壓力、實際低磁碟空間與中斷後續傳待驗證 |
| 核心雙向互動與聊天活躍 | PD-020 將同一 Moment／題目／共同約定內的雙方參與定義為核心雙向互動；同週雙方各至少一則聊天訊息另列聊天活躍。完整內容留在產品資料／私有 Storage，分析事件只保存內容參照與必要 metadata | 純規則涵蓋單方重複、混合物件、重複內容參照、第二位參與完成時間、週期邊界與雙方聊天；編碼 regression 確認沒有私密內容欄位 | 雲端彙整事件尚未實作；產品資料與 Storage 的備份／還原及演練另列 release gate |

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

2026-08-05 已確認採 A1，且雙方保留權不可被另一方單方面剝奪是硬性需求。因此 CloudKit Sharing 保留為 Apple 原生能力驗證結果，不升格為正式共同資料架構。後續 Supabase spike 已完成伺服器端對等授權、封存確認、個人封存隔離、獨立刪除與最後引用 Storage GC；2026-08-06 由 TD-001 正式接受為 v1 共同資料受管後端。

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

### Supabase 持久 outbox／冪等重送 spike

為了驗證離線重送而不先建立正式聊天架構，本輪只處理一筆不含內容的 marker metadata。App 在第一次送出前先以 `UserDefaults` 按 Supabase user UUID 保存 relationship UUID、client UUID 與 attempt count；同一使用者尚有待送 marker 時，再次點擊或明確重試都沿用相同 client UUID，不建立第二筆。成功後才清除本機 outbox；失敗或 App 結束時保留。metadata 解碼失敗會明確報錯並阻止新寫入，不把損壞資料靜默視為空 outbox。

新增 migration `202608050007_w1_idempotent_marker_rpc.sql`，由 authenticated session 推導 creator，且只在 active relationship 接受 marker。相同 relationship／client UUID 由同一 creator 重送時回傳既有 server timestamp；另一 creator 嘗試冒領同一 UUID、第三人寫入或 closing 後重送均被拒絕。這是 marker spike，不代表正式訊息內容已選擇 `UserDefaults`，也不包含多筆佇列、自動背景排程、退避、網路監聽或照片 upload outbox。

本機 reset 已成功套用 `001`～`007`；七份 pgTAP 目前共 67 個案例全部通過，案例涵蓋首次寫入、相同識別重送不重複、兩個不同識別各自建立且重送後維持兩筆、creator／kind 由 session 決定、身分碰撞、第三人與 closing 拒絕。`public` schema lint 無錯誤；iPhone Simulator unsigned build 與 `build-for-testing` 通過。Simulator test runner 再次停在既有測試啟動問題、未進入案例，因此不宣稱 runtime unit suite 通過；另以實際 `G1TechnicalRules.swift` 完成三個獨立程序的 write／read／clear smoke test，確認單筆 metadata 可跨程序恢復。

`007` 已部署至 Supabase 測試專案。2026-08-06 使用真實 iPhone A 與 iPhone 17 Pro Simulator B、兩個不同 Apple 身分建立新的 active relationship，雙方確認關係代碼 `dd36812f` 與成員 `2/2` 一致後完成以下驗證：

- A 斷網後寫入 marker，網路錯誤明確顯示，outbox 保留為待重試且 attempt count 為 1。
- A 強制結束並重開 App，待送 marker 仍存在。
- A 恢復網路並重試後，outbox 顯示 marker `52c467a0` 已送達。
- B 重新整理後看到相同 marker；雙方再次強制結束、重開並重新整理後，仍看到同一識別。

此結果通過單筆 marker metadata 的離線失敗、跨啟動保存、明確重試與跨裝置恢復；資料庫 pgTAP 另證明相同 client UUID 重送只保留一筆。它不代表正式聊天內容、多筆佇列、自動背景重送、退避、弱網錯序或照片 upload outbox 已完成。

### Supabase 多筆 FIFO outbox 本機 spike

在不加入正式訊息內容的前提下，單筆 store 已擴為同一 Supabase user key 下的 ordered metadata queue。舊版單一 `MarkerOutboxEntry` JSON 仍可 fallback decode 成一筆 queue，不會把既有離線資料視為損壞；其他 malformed data 繼續明確拋錯。每次「寫入新的」會建立新的 client UUID 並加到尾端；processor 一次只傳 head，送出前只增加 head 的 attempt count，RPC 成功後亦只在 client UUID 符合時移除該 head。若中途失敗，失敗的 head 與所有 tail 都保留；任何 session 或網路 `await` 前即鎖住 enqueue／drain 路徑，傳送期間 UI 也禁止啟動第二個 processor，避免 async interleaving 以舊 snapshot 覆寫 queue。畫面只顯示最近三筆 marker 的 8 碼短 token（舊到新），供跨裝置驗證筆數與順序，不揭露完整 UUID 或內容。

既有 `007` RPC 已以 `(relationship_id, client_id)` 獨立冪等，不需新增 migration。pgTAP 新增兩個不同 client UUID 各自建立及重送案例後，七份檔案共 67 個案例通過。iPhone target build 與含新增 Swift regressions 的 `build-for-testing` 通過；regressions 涵蓋 FIFO round-trip、只移除已確認 head、tail attempt 不變、最後一筆移除後清空、legacy 單筆 decode 與 corruption throw。Simulator test runner 等待 60 秒仍未進入案例，因此中止且不宣稱 runtime suite 通過；另以實際 `G1TechnicalRules.swift` 執行 runtime smoke，確認兩筆順序、head attempt 與移除 head 後保留 tail。

2026-08-06 沿用同一 active relationship 的真實 iPhone A 與 iPhone 17 Pro Simulator B，完成三筆 FIFO 人工驗證：

- 雙方先確認 relationship `active`、成員 `2/2` 且關係代碼一致。
- A 斷網後依序建立三筆 marker；每次都等待離線錯誤返回，Outbox 最終顯示三筆待送。
- A 保持離線強制結束並重開 App，三筆 Outbox 全部保留。
- A 恢復網路、重新整理關係後只按一次重試，三筆依序送達且 Outbox 清空。
- A 與 B 的「最近 3 個標記（舊 → 新）」顯示三個相同短 token，順序完全一致。
- 雙方再次強制結束、重開並重新整理後，仍顯示相同三筆與順序。完整 UUID 與內容未記錄。

此結果通過三筆 metadata queue 的離線 enqueue、跨啟動保存、單一 processor FIFO drain、跨裝置筆數／順序一致及重啟恢復。尚未加入自動背景重送、退避、網路監聽、容量上限或正式 message sequence，也未涵蓋較長佇列與受控弱網延遲；這些限制保留為後續驗證邊界。

2026-08-07 另以 deterministic unit regression 將 message 與 marker queue 各擴至 100 筆，確認序列化後順序不變、每次 attempt 只落在 head、逐筆 acknowledgement 能完整 drain 且重新載入為空。這關閉本機資料結構在較長樣本下的基本 FIFO 風險，但不是正式容量上限，也不取代真機長佇列、頻繁斷線、退避與背景排程證據。

### Supabase Storage 私有照片 spike

新增 migration `202608050004_w1_private_photo_storage.sql`，建立非公開 bucket `couplespace-w1-photos`，單檔限制 5 MiB 且只接受 JPEG。物件路徑固定為 `relationship UUID/client UUID.jpg`，不保存原始檔名；只有 active relationship member 可讀，只有上傳者可刪，第三身分不可讀寫，relationship 進入 `closing` 後禁止新增照片。

Swift W1 client 沿用既有最長邊 1,600 px、JPEG quality 0.8 的裝置端重新編碼，先上傳 Storage，再以相同 client UUID 寫入 `shared_items` photo metadata。另一端由 RLS 取得最新 photo client UUID，再從私有 bucket 下載，不使用 public URL；後續持久重試接縫記於下節。

本機四份 pgTAP 共 39 個案例通過，包含 bucket privacy／大小、兩位 member 讀取、第三人拒絕、非上傳者不可刪、closing 禁止上傳與上傳者可刪；刪除測試使用 Storage API 同等的 `storage.allow_delete_query` 受控旗標，未停用 Supabase 的直接刪除保護 trigger。iPhone Simulator unsigned `build-for-testing` 通過。migration 已部署至雲端；遠端 migration history 顯示本機與遠端 `202608050001`～`202608050004` 一致，後續 dry-run 回報資料庫已是最新狀態，linked `public` schema lint 無錯誤。CLI 在套用 `004` 後未自行返回，經 migration history 確認成功後中止等待程序。

### 2026-08-05 雲端 Storage 跨裝置實測證據

沿用同一 active relationship 內的真機 A 與 iPhone 17 Pro Simulator B，以及各自的 Apple 身分：

- A 上傳私有測試照片後，B 手動重新整理 Supabase Storage 照片並成功顯示該照片。
- B 上傳另一張私有測試照片後，A 手動重新整理並成功顯示該照片。
- 截圖顯示私有照片上傳成功狀態、照片預覽與重新整理操作；未記錄 Storage object path、完整 relationship ID 或 user ID。

此結果通過同一 active relationship 內兩位 member 的私有照片雙向上傳、metadata RLS 查詢與 private bucket 下載。自動即時更新、第三身分的雲端拒絕、closing／archive、弱網與刪除一致性仍未由本次成功推論為通過。

### Supabase 照片持久 FIFO outbox spike

為驗證照片在斷網及 App 重啟後仍可明確重試，而不先建立正式相簿或多照片佇列，W1 client 新增單張 `PhotoOutboxEntry`：依 Supabase user UUID 保存 relationship UUID、client UUID、attempt count 與受控本機檔名；重新編碼後的 JPEG 以完整檔案保護寫入 Application Support。已有待送照片時不允許選取另一張覆寫，待送照片完成前也不允許由本裝置開始解除配對。

2026-08-06 在單張實測通過後，以相同 entry 與檔案格式最小升級為 `PhotoOutboxQueue`。新照片只附加在尾端；processor 每次只處理 queue head，伺服器確認 object 與 metadata 後才移除該筆本機檔案與 metadata，錯序 acknowledgement 一律拒絕。既有單張 UserDefaults payload 可解碼成只有一筆的 queue，不要求使用者清除 App 資料。W1 畫面只顯示最近三張 client token（舊到新）與最新縮圖，不記錄原始檔名或照片內容。

每次重試沿用同一 client UUID 及 deterministic Storage path。第二次以後會先確認同一路徑是否已存在，處理 App 在 object upload 後中止的情境；寫入 metadata 前亦查核既有 row 必須屬於同一 creator 且種類為 `photo`。只有 Storage object 與 RLS metadata 都確認成功後才刪除本機 JPEG 與 outbox metadata。損壞 metadata、非法檔名或遺失檔案不會被靜默視為空 outbox。

- 新增 deterministic tests：跨 store instance 恢復資料與 attempt、拒絕覆寫待送照片、遺失本機檔案時保留 metadata 並明確報錯。
- 一次性 macOS smoke 直接編譯同一份 `G1TechnicalRules.swift`，實際寫入、重新載入、增加 attempt、拒絕覆寫與清除，輸出 `photo-outbox-smoke-ok`。
- iPhone Simulator generic `build-for-testing` 通過，且 actor-isolation warning 已清除。
- 後續由 Xcode crash report 定位，runner 無事件並非單純 infrastructure stall：測試 host 啟動 W1 畫面時提前建立 `CloudKitSharingPoC.shared`，`CKContainer.default()` 在測試簽署環境觸發 `SIGABRT`。TD-001 已將 CloudKit PoC 退居實驗紀錄，因此已從目前 Supabase W1 畫面移除該 singleton 與 CloudKit 操作區，不刪除歷史 PoC 原始碼。同一 Simulator 指令重跑後，`CoupleSpaceTests` 21 個案例全數通過，包含照片 outbox 跨 store 恢復、拒絕覆寫、遺失檔案保留 metadata 與 pending photo 阻擋解除配對。
- 原始單張切片沒有新增 migration。當時不包含多張照片、背景自動重送、退避、網路監聽、容量／保存期限政策，亦未宣稱永久拒絕或解除配對競態下的 orphan cleanup 已完整處理。

多張 FIFO 升級後，iPhone generic Simulator build 與 `build-for-testing` 通過；加入 relationship 顯示快照及實際 JPEG regression 後，`CoupleSpaceTests` 26 個 runtime cases 全數通過。新增／更新案例涵蓋兩張照片的 FIFO、只允許 acknowledgement queue head、attempt 只增加在 head、舊單張 payload 與檔案無損載入、第一張檔案遺失時仍保留後續 metadata 與檔案、relationship 快照依 Supabase user 隔離與清除，以及含 EXIF orientation=6 與 GPS 的 2400×1200 JPEG。該 JPEG 經既有 production processor 後輸出正向 800×1600 full image、160×320 thumbnail，orientation 已正規化且 GPS dictionary 已移除，因此無需新增第二套照片處理器。原本「單張拒絕覆寫」限制已由 append-only queue 取代；尚未加入自動背景重送、退避、網路監聽、容量上限、保存期限或正式相簿。

2026-08-07 本機再以 32 筆、每筆 1 KiB 的合成 JPEG payload 驗證檔案與 metadata 跨 store 載入、head attempt、逐筆資料一致、FIFO drain，以及成功後檔案目錄清空。此樣本只驗證 queue／檔案生命週期，不代表照片數量、檔案大小或儲存容量政策。

真機 A＋Simulator B 驗證步驟：

1. 確認雙方登入同一個 `active` relationship，B 保持連線。
2. A 關閉網路後選取一張不含私人內容的測試照片；等待 Photo Outbox 顯示待重試。
3. A 保持離線強制結束並重開 App；重新整理後應仍顯示同一張待送照片及 attempt count。
4. A 恢復網路，只按一次「重試待送照片」；成功後 Photo Outbox 應清空。
5. B 點「重新整理 Supabase Storage 照片」，應看見 A 上傳的同一張測試照片。
6. A 再次強制結束並重開；不得重新出現已送達的待送照片。

2026-08-06 真機 A＋Simulator B 已完成上述全流程：A 斷網選照後 Outbox 顯示待送，強制關閉並重啟後仍恢復同一張待送照片；恢復網路並只重試一次後，B 重新整理即看見同一張照片，A 再次重啟也未復活已送達項目。因此單張照片的離線持久化、人工重送、跨裝置可見性與成功後清除已通過。這不代表多照片 FIFO、背景自動重送、網路頻繁切換、大圖與方向組合已通過。

同日再完成三張流程：A 斷網依序加入三張測試照片，強制結束並保持離線重開後 queue 與順序均保留；恢復網路只啟動一次重送，B 依原順序看到三張且 A 再次重啟沒有復活已送達項目。因此三張 FIFO 的離線 enqueue、跨啟動保存、單一 processor drain、跨裝置順序與成功清除通過。仍未涵蓋頻繁斷線、大圖、方向組合、自動退避與容量上限。

高解析方向回歸亦於 2026-08-06 通過：真機上傳未編輯的直向高解析測試照片後，Simulator 重新整理可看到相同 client token；照片方向正確，沒有拉伸、裁切或比例錯誤。Simulator 強制結束、重開並再次整理後結果不變。這與 26 個 runtime cases 中的 EXIF orientation／GPS fixture 一起關閉本輪大圖方向風險；頻繁弱網、容量上限與保存期限仍未定案。

### 照片 upload／closing orphan reconciliation

盤點發現 photo outbox 原本仍有一個解除配對競態：Storage upload 已成功，但另一裝置在 metadata insert 前把 relationship 轉為 `closing`，會使 metadata 被拒絕，留下沒有 `shared_items` 引用的 Storage object 與永久待送的本機 outbox。這不是容量政策問題，而是刪除一致性與解除配對阻斷風險，因此優先於設定任意的商業容量數字處理。

新增 migration `202608070011_w1_photo_orphan_cleanup.sql`，只讓原上傳者在仍是 active member，或仍持有該 relationship personal archive 且伺服器確認沒有 matching photo metadata 時，經 Storage API 刪除自己擁有的 W1 orphan object；正常封存照片即使同為上傳者所有也不可刪除。partner 仍受 `owner_id` 限制，第三身分也沒有 member／archive 權限。Client 在伺服器已確認 `closing`／`archived` 後逐筆整理 photo outbox：若 matching photo metadata 已存在，就只確認本機項目已送達；若 metadata 明確不存在，才刪除 deterministic path 的 orphan object，且 Storage API 成功後才移除本機 JPEG／queue。網路錯誤、查詢失敗或 identity collision 都保留 queue，不推測成功。

本機從空資料庫套用 migrations `001`～`011`，11 份 pgTAP 共 125 個案例全數通過，新增案例證明 archived orphan 只能由原上傳者刪除，partner／第三身分均被拒絕、已有 sealed metadata 引用的正常照片仍受保護，且不建立重複 GC job；`public` schema lint 無錯誤。Swift 新增五個 reconciliation cases，iPhone 17 Simulator `CoupleSpaceTests` 36／36 通過，`build-for-testing` 亦成功。migration 011 已推送 Supabase 測試專案，遠端 migration 清單與最終 dry-run 均確認資料庫為最新。

跨裝置時序亦已通過：真機 A 斷網後把照片排入 Outbox，Simulator B 保持連網並開始解除配對，B 先顯示 `closing`；A 因離線顯示「重新整理 RLS 狀態失敗」是預期行為，並不代表 closing 未生效。A 恢復網路後重新整理，才取得遠端 `closing`、清除待送照片且重啟後不復活；其餘 closing 寫入拒絕條件均符合。這關閉 migration 011 的 deployment／cross-device gate。

### 斷網冷啟動 relationship 顯示快照

實測發現已登入使用者在完全斷網下強制結束並重開 App 時，遠端 `refresh` 尚未成功前，關係代碼與成員數會回到空狀態。W1 client 因此加入最小唯讀快照：每次 Supabase 成功回傳 relationship 與 membership 後，依 Supabase user UUID 保存 relationship UUID、status 與 member count；冷啟動先恢復這三個顯示欄位，再嘗試遠端更新。伺服器成功確認目前無關係或關係已封存時清除 active snapshot；登出只清空畫面，不把另一使用者的資料載入目前 session。

此快照只改善離線顯示，不授權 marker、message、photo、Realtime 或解除配對操作；所有寫入仍必須有有效 session 並通過 RPC／RLS。UI 以「顯示上次已同步資料」和「Supabase 已更新」區分來源。加入後續照片 regression 後，`build-for-testing`、26 個 Simulator runtime tests、Harness 與 diff hygiene 已通過。

2026-08-06 真機完成「在線整理 → 斷網 → 強制結束 → 重開 → 恢復網路再整理」回歸：離線重開後關係代碼與 `2/2` 立即由快照恢復，重新連線後亦能回到 Supabase 最新狀態。因此原本的斷網冷啟動空白問題已關閉。

Xcode 26.6 真機 development run 的慢啟動跳窗已保留證據，內容為 `Launching “CoupleSpace” is taking longer than expected`，並明示 `LLDB is likely reading from device memory to resolve symbols`。本次選擇 Continue 後 App 正常啟動，且沒有 CoupleSpace crash、watchdog `0x8badf00d` 或 App 首畫面逾時證據，因此歸類為 debugger／symbol resolution 延遲，不當成 production App 啟動效能失敗。若後續脫離 Xcode 啟動仍然緩慢，或產生 watchdog／hang report，再獨立量測 App launch。

同次上傳與下載期間 console 出現 `nw_connection_copy_protocol_metadata_internal ... unconnected nw_connection`、`Connection has no local endpoint` 與 socket handler 訊息；但該次照片上傳、跨裝置下載、token、方向、比例及重啟恢復全數成功，沒有對應 API error 或資料缺失，因此只記為本輪非阻斷的 Network.framework 診斷輸出，不加入猜測性 retry 或 suppress hack。若未來同時發生實際 request failure，需以發生時間對照 device console 與 Supabase error 再判斷。

### Supabase 文字訊息契約與 FIFO outbox spike

新增 migration `202608060008_w1_text_message_contract.sql`，在既有 `shared_items` 上建立最小純文字訊息契約：正文去除首尾空白後必須為 1～4,000 個字元，由 `write_shared_message` RPC 從 Supabase session 派生 creator，並以 `(relationship_id, client_id)` 實行冪等。相同識別只有在 creator、kind 與正文全數相同時能視為安全重送；第三身分、不同正文碰撞與 closing relationship 均由伺服器拒絕。

為避免解除配對後只封存 metadata，同一 migration 擴充 `personal_archive_items.text_content`，並讓 `seal_personal_archive` 連同訊息正文複製至各自 owner-isolated archive。這沒有新建第二套封存或訊息系統。

Swift W1 client 新增只產生 `W1 test <token>` 的非私人測試訊息，以 UserDefaults 持久 FIFO queue；失敗保留穩定 client UUID、正文、順序與 attempt count，成功只移除已確認的 head。待送訊息尚未清空時，本裝置不允許開始解除配對。此 W1 畫面不接受真實私人輸入，也未實作已讀、回覆、編輯、刪除、推播或正式聊天 UI。

- 本機從空資料庫成功套用 migration `001`～`008`。
- 8 份 pgTAP 共 81 個案例全數通過；新案例包含正規化、一般空白、換行／tab、超長拒絕、冪等重送、正文碰撞、第三人、closing 與封存正文保留。
- iPhone `build-for-testing` 通過，`CoupleSpaceTests` 23 個 Simulator runtime 案例全數通過。
- migration 008 已於 2026-08-06 部署至雲端測試專案；遠端 migration history 顯示 local／remote `202608060008` 對齊，第二次 dry-run 回報 `Remote database is up to date`，linked schema lint 回報 `No schema errors found`。
- 2026-08-06 真機 A＋Simulator B 已完成三則文字訊息 FIFO 全流程：A 在線寫入後 B 可見相同 `W1 test <token>`；A 斷網連續建立三筆後 Outbox 顯示三筆待送，保持離線強制結束並重開 App 仍保留原順序；恢復網路只觸發一次重送後，B 依原順序看到三則且沒有重複，A 再次重啟時 Outbox 已清空。
- 此結果通過單一真機與 Simulator 的跨 Apple 身分文字同步、離線持久化、跨啟動 FIFO、恢復網路人工重送及冪等清除；100 筆本機 regression 另通過持久化與完整 FIFO drain。尚未完成兩支真實 iPhone、長佇列真機壓力、頻繁斷線、自動退避、背景重送與雲端封存正文實測。

### 登入／前景 outbox recovery 候選

W1 client 在 Supabase 登入狀態可用或 App 由背景回到前景時，會以單一 coordinator 先執行既有 RLS refresh，再建立本次恢復計畫。計畫只接受 `active` relationship，且每一種 queue 的所有項目都必須屬於目前 relationship；順序固定為 marker、message、photo。`closing`、`archived`、沒有目前 relationship、混入舊 relationship 或另一個 recovery 尚未結束時均不自動送出。每個 processor 仍沿用既有穩定 client UUID、FIFO、伺服器冪等與失敗保留，不建立第二套傳送邏輯。

原始切片只代表「登入或回到前景後立即嘗試一次」。2026-08-07 的下一個最小候選在同一 coordinator 加入有限次短退避：首次失敗且同一 active relationship 仍有待送項目時，等待 1 秒、4 秒再試，合計最多三次；三次後停止並保留既有 Outbox，等待下一次前景事件或人工重試。它不加入網路監聽、無限輪詢或 iOS background task，`closing`、`archived`、舊 relationship 與並行重入拒絕規則不變。iPhone 17 Pro Simulator 的完整 `CoupleSpaceTests` 56／56 通過；新增純規則案例固定最大次數、兩段延遲與越界不重試。

2026-08-07 真機 A＋Simulator B 已完成兩條一次性自動恢復流程。第一條在 A 斷網排入 marker、message、photo 後讓 App 進入背景，恢復網路再回到 App，全程不按人工重試或重新整理，三種 Outbox 自動送達並清空，B 可見相同內容且沒有重複。第二條在相同三種待送項目存在時保持斷網強制結束 A，先恢復網路再重新啟動 App；Supabase session 恢復後三種 queue 同樣自動 drain，B 核對內容、順序與去重均正常。

同日另完成三次有限短退避的真機驗證。短暫斷線案例由真機 A 建立待送 marker 並觸發前景 recovery，在不按人工重試的情況下於退避視窗內恢復網路；Outbox 自動清空，Simulator B 只看到一次相同 marker。耗盡案例則讓 A 持續離線至三次嘗試完成，畫面顯示「前景自動重試已暫停；待送項目已保留」，queue 與穩定 identity 均未遺失；恢復網路並再次觸發前景事件後自動送達，B 仍只收到一次。這關閉 W1 的一次性與有限短退避登入／前景 recovery 證據，但不代表 App 在背景中自行傳送，也不接受為正式長時間退避或網路監聽方案。

下一個最小候選加入 `NWPathMonitor`，但只在 App 位於前景、Supabase 已登入，且已明確觀察到 unavailable→available 轉換時，呼叫同一個 recovery coordinator。初次監測即為 available 不觸發，available→available、available→unavailable 與 unavailable→unavailable 也不觸發；既有單一執行、active relationship、marker→message→photo 順序及三次有限重試規則完全沿用。新增純規則案例後，iPhone 17 Pro Simulator 的完整 `CoupleSpaceTests` 59／59 通過，零失敗與零跳過。這不是 background task、長時間退避或無限輪詢。其後真機 A 保持 App 在前景，完全斷網後建立一筆待送 marker；不切換 App、不按重新整理或人工重試，恢復網路後 Outbox 自動清空，Simulator B 重新整理只看到一次相同 marker，確認網路轉換觸發與既有穩定 identity 正常。

### 照片配額原子確認候選

PD-021 已接受 Free 每段關係每月 30 張照片及累積 1 GB 作為首輪研究起點，但不能只靠 App 隱藏按鈕或本機計數。migration `202608070012_w1_photo_quota.sql` 因此新增 `finalize_w1_photo_upload`：上傳仍先進入私有 Storage，RPC 再鎖住 relationship row、確認 active membership、核對 deterministic path、object owner 與 Storage metadata bytes，最後才建立 photo shared item。authenticated client 的一般 insert policy 明確排除 photo，雙方同時上傳也會由同一 relationship lock 串行計數。RPC 以 UTC 月曆月計 30 張，累積總量以 1,000,000,000 bytes 計算；這兩個精確語意都是 W1 候選，尚未升格為永久產品規則。

照片 Outbox 另加入獨立於遠端配額的本機容量預檢。Client 在把已重新編碼 JPEG 寫入 Application Support 前，以檔案實際 bytes 比較該 volume 的已知可用空間；明確不足時回報「裝置可用空間不足，未保存待送照片」，且不建立 JPEG 或 queue metadata。可用容量無法取得時維持相容，仍交由既有原子寫入錯誤保護，不加安全倍數或推測性 queue 上限。完整 `CoupleSpaceTests` 61／61 通過，涵蓋剛好足夠、少一 byte、未知容量與拒絕後無殘留；尚未以真機實際低磁碟狀態驗證。

2026-08-10 以真機 A 在 active relationship 選擇測試照片並完成上傳，沒有出現容量不足錯誤；Simulator B 重新整理後可讀取另一裝置上傳的私有照片，且 Photo Outbox 顯示沒有待送照片。這關閉容量預檢加入後的正常真機上傳回歸，不是低磁碟案例，因此實際低空間 gate 維持未通過。

RPC 對相同 relationship／client identity 的重試保持冪等；不同 owner、kind 或 bytes 的碰撞一律拒絕。若回傳月新增或總容量上限，client 先透過既有 owner-only Storage policy 刪除剛上傳的 orphan，成功後才移除該筆本機 outbox；若網路、RPC 或清理失敗則保留原 JPEG 與 queue 供重試。migration 012、本機 Storage metadata、月界線、總容量、第三身分、closing 與直接 insert bypass 共 14 個新 pgTAP 已連同既有資料庫合約通過 139／139；iPhone `CoupleSpaceTests` 現為 55／55。新增的 client regressions 明確涵蓋成功確認、兩種配額拒絕文案、未知拒絕保留重試、先刪除遠端 object 再 acknowledge、遠端清理失敗時不得碰觸本機 Outbox，以及配額提示必須插入實際訊息與剩餘佇列數。2026-08-07 migration 012 已推送 Supabase 測試專案，遠端版本紀錄與本機一致。真機 A 與 Simulator B 隨後在同一 active relationship 近乎同時各上傳一張照片；雙方重新整理後都顯示同一張最新照片，最近照片列包含兩個不同的新 token，兩邊 Outbox 均清空，且沒有重複項目或錯誤提示，證明遠端 relationship lock 路徑可接受並排序兩筆競爭寫入。其後以固定 UUID、月初時間與 1 byte metadata 的可回收 fixture 將同一 relationship 從原有 5 張補至本月 30 張；真機 A 上傳第 31 張時正確顯示月上限、最近三個 token 不變且 Outbox 清空。遠端前後核對皆為 30 筆 metadata／5 個 Storage objects，證明被拒照片的 object 已刪除且沒有建立 metadata；刪除 25 筆 fixture 後回復原有 5 筆／5 個，無 fixture 殘留。第二組 fixture 使用前一月份、單筆不超過 5 MB 的 200 筆 metadata，將累積量補至 999,999,999 bytes 且本月仍只有原有 5 張；真機 A 再上傳時正確顯示 1 GB 上限、實際文案及「未建立共享照片」，Outbox 清空。遠端仍為 205 筆 metadata／5 個 Storage objects／999,999,999 bytes，證明被拒照片同樣沒有 metadata 或 orphan；清理後精準回復 5 筆／5 個／1,164,373 bytes，無 fixture 殘留。metadata-only fixture 曾短暫使 App 的最近照片查詢顯示「尚無照片」，屬受控測試資料副作用，清理後即可恢復，並非正常產品資料路徑。

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

### 個人封存刪除與 Storage GC spike

新增 migration `202608050006_w1_personal_archive_deletion_queue.sql`，取消 App 對 `personal_archives` 的直接 `DELETE` 權限，改由 `delete_personal_archive` RPC 驗證 owner 與 relationship 已為 `archived`。第一位 owner 刪除只移除自己的封存；最後一份封存刪除後，伺服器才依既有 deterministic path 將 photo object 排入受保護的 `storage_gc_queue`。這可避免 direct delete 繞過最後引用判斷，也避免任一方在解除配對尚未完成時先刪除封存而卡住流程。

實際物件由 `process-storage-gc` Edge Function 使用 Storage API 刪除，不直接刪除 `storage.objects` metadata。這遵循 Supabase 的 [Delete objects](https://supabase.com/docs/guides/storage/management/delete-objects) 與 [Storage schema](https://supabase.com/docs/guides/storage/schema/design) 指引，避免留下仍佔空間的 orphan object。worker 不接受 client 指定 path，只讀取伺服器建立的 queue；登入驗證失敗即拒絕，Storage API 失敗則保留工作並增加 attempt count。App 在 archived 狀態提供明確的清理重試入口，避免刪除封存成功但短暫網路錯誤後無法再次觸發 worker。

本機 reset 已成功套用 `001`～`006`；六份 pgTAP 共 57 個案例全數通過，涵蓋 direct delete 禁止、closing 階段禁止刪除、第三人拒絕、第一份封存刪除不排入 GC、最後一份封存刪除只排入 photo path，以及另一方封存不受影響。`public` schema lint 無錯誤，Edge Function runtime 成功 bundle／啟動，iPhone Simulator unsigned build 通過。

取得明確授權後，已將 `006` 套用至雲端測試專案並部署 `process-storage-gc` version 1。遠端 migration history 顯示本機與遠端 `001`～`006` 一致，後續 dry-run 回報資料庫已是最新狀態，linked `public` schema lint 無錯誤；Function 清單顯示狀態 `ACTIVE` 且 `verify_jwt = true`，不含 authorization header 的請求回傳 HTTP 401。CLI 套用 migration 後曾出現 migration catalog cache 連線逾時警告，但 migration history、dry-run 與 lint 均成功，因此沒有重複套用。

部署完成當下尚未刪除雲端測試資料；破壞性驗證依序確認單方刪除後另一方仍可讀，再確認最後一方刪除後 object 與 queue 都被清除。

第一階段雲端刪除實測已通過：真機 A 永久刪除自己的 personal archive 後，封存項目數歸零、封存照片消失，且 App 明確提示另一方不受影響；Simulator B 隨後重新整理仍顯示 `8` 個封存項目並可讀取原私人照片。此結果證明 owner-only archive delete 與「尚有另一份封存時不排入照片 GC」的允許路徑。最後一份封存刪除及實際 object／queue 清理仍待驗證。

第二階段雲端刪除實測亦通過：Simulator B 永久刪除最後一份 personal archive 後，封存項目數歸零、照片消失，App 顯示最後一份照片已完成清理。隨後以 Management API 執行只讀聚合查詢，確認 `storage_gc_queue = 0`、`personal_archives = 0`，且私有 bucket `couplespace-w1-photos` 的 `storage.objects = 0`。因此本次測試同時證明 queue 已完成、兩份個人封存都已刪除，以及實際 Storage object 已移除，不只是在 App 端失去讀取權限。

### 私人推播伺服器邊界 spike

新增 migration `202608060009_w1_private_push_boundary.sql`。`push_devices` 只允許登入使用者透過 security-definer RPC 登記正規化 APNs token，`authenticated` 不具有直接讀取 token 表的權限；token 綁定固定 bundle ID 與 sandbox／production 環境。`enqueue_w1_test_push` 不接受 recipient、標題、正文、訊息或照片參數，只接受 relationship 與穩定 event UUID；伺服器確認 relationship 為 active 且恰有兩名 active member 後，自行選擇另一位成員，並以唯一鍵提供冪等排程。`push_delivery_jobs` 只保存 routing metadata 與通用 `w1_generic` 種類，不具有私人內容欄位。

iOS W1 畫面加入系統通知授權與 `registerForRemoteNotifications` 接點。AppDelegate 每次收到 APNs token 都交給 Supabase 登記，不把 token 寫入本機持久儲存、畫面或 log；畫面只顯示 SHA-256 前八碼供雙裝置辨識。泛化 payload 固定顯示「CoupleSpace 有新動態／打開 App 查看」，只帶 event kind 與 event UUID，不帶 relationship、sender、訊息或照片內容。

本機 reset 已成功套用 `001`～`009`；九份 pgTAP 共 99 個案例全數通過，包含 token 表／工作表不可由登入 client 直接讀取、受信 sender 的最小讀寫權限、token 正規化、錯誤 token／環境拒絕、伺服器推導正確收件者、第三身分／單人成員／closing 拒絕及 event 重送去重。`public` schema lint 無錯誤。iPhone Simulator `build-for-testing` 通過；指定 iPhone 17 Pro Simulator 的 `CoupleSpaceTests` 28 個案例全數通過，包含 payload 資料最小化與 token hex／指紋 regression。完整 scheme 首次跑進既有 UI runner 後長時間沒有案例輸出而中止，不宣稱 UI suite 通過。

取得明確授權後，migration 009 已推送至 Supabase 測試專案。遠端 migration history 顯示 local／remote `001`～`009` 一致，後續 dry-run 回報已是最新狀態，linked `public` schema lint 無錯誤。push 收尾曾出現 migration catalog cache 的 2.5 秒連線逾時警告，但 history、dry-run 與 lint 均分別串行成功，因此沒有重複套用。

2026-08-06 真機已允許通知並成功把 sandbox APNs token 登記至 Supabase；W1 畫面只顯示不可逆的 SHA-256 前八碼指紋，未顯示或記錄完整 token。這關閉了真機 entitlement、通知授權、device token 取得與登記接縫，但尚未證明送達。

下一個最小切片新增 migration `202608060010_w1_push_delivery_claim.sql` 與 `send-w1-push` Edge Function。受信 sender 必須先以呼叫者 access token 取得已驗證 user ID，再原子 claim 該使用者建立的工作；client 不能 claim／complete 或直接更新工作。失敗會釋放 claim 供明確重試，成功後不可重送。Edge Function 只查詢另一位 active member 已登記的同環境裝置，固定送出「CoupleSpace 有新動態／打開 App 查看」與 event UUID／kind，不回傳或記錄完整 token、relationship、sender、訊息或照片內容。iOS 測試按鈕會保留本次執行記憶體中的 job ID 供失敗重試；這不是正式背景 delivery queue，也不宣稱跨 App 重啟保留 sender 工作。

- 本機 reset 已成功套用 `001`～`010`；十份 pgTAP 共 110 個案例全數通過，其中 010 覆蓋 client 不可 claim、service role 不能繞過直接 UPDATE、原子 claim、錯誤 sender 拒絕、失敗釋放重試、attempt 遞增、錯誤長度限制及成功後禁止再次 claim。
- `public` schema lint 與 Project Harness v0.2.1 通過；`send-w1-push` 已由本機 Supabase Edge Runtime 1.74.2 成功 bundle／serve。
- iPhone Simulator `build-for-testing` 通過；指定 iPhone 17 Pro Simulator 的 `CoupleSpaceTests` 28 個案例全數通過。
- Edge helper 的五個 Deno 測試已建立，但嘗試透過 npm 取得 Deno 2.1.4 時發生 registry `ETIMEDOUT`，因此本輪不宣稱該五項已執行通過。

取得明確授權後，migration 010 已推送至 Supabase 測試專案，`send-w1-push` version 1 亦已部署。遠端 migration history 顯示 local／remote `001`～`010` 一致，第二次 dry-run 回報 `Remote database is up to date`，linked `public` schema lint 無錯誤。Function 清單顯示 `ACTIVE` 且 `verify_jwt = true`；不含 authorization header 的 POST 回傳 HTTP 401。Apple APNs token-based key 已由使用者建立並將四個必要值保存於 Supabase Secrets；文件與 repository 不保存 `.p8` 內容。

2026-08-06 以 active 2/2 relationship 的 Simulator B 觸發泛化測試工作，背景中的真機 A 成功收到「CoupleSpace 有新動態／打開 App 查看」。這證明已部署 sender 能依 relationship 選擇另一位 active member、使用 sandbox APNs token 送達正確裝置，且通知不含私人訊息、照片、sender 或 relationship 內容。

後續以同一組 active 2/2 relationship 重複觸發兩筆新工作：真機 A 完全終止 App 後仍收到通知，點擊通知可開啟 CoupleSpace；真機 A 鎖定後亦於鎖定畫面收到相同泛化文案，沒有使用者名稱、關係代碼、訊息或照片內容，配對的 Apple Watch 同時正常鏡像該通知。這些結果關閉本輪 development sandbox 的背景、終止與鎖定畫面隱私驗證；Apple Watch 僅記錄系統鏡像行為，不代表已實作獨立 watchOS 推播。

推播 W1 切片在一支真實 iPhone＋Simulator 的 development sandbox 範圍已通過；兩支真實 iPhone 與 production／TestFlight 送達仍是未關閉風險。

### 個人封存匯出候選

W1 client 只在 relationship 已 `archived` 且目前使用者仍持有 personal archive 時開放匯出。它沿用既有 owner-only RLS 讀取自己的 `personal_archive_items`，並以 archived-photo Storage policy 逐張下載本人仍可讀的 JPEG；不使用 service-role 權限或 public URL。

候選交付格式是可直接檢查的資料夾：根目錄包含 `manifest.json`，照片放在 `photos/<client_uuid>.jpg`。manifest 使用 `schema_version = 1`，依 `created_at` 與 client UUID 決定固定順序，保留測試訊息正文並以 `photo_file` 對應照片；不使用原始照片檔名，也不包含 Email、Apple ID、APNs token 或 Supabase access token。系統 `fileExporter` 負責讓使用者選擇「檔案」位置。

匯出 regression 已驗證固定排序、manifest／JPEG 對應、缺少照片 fail-closed、photo entry 不得混入文字內容、重複照片拒絕、只清理專用殘留目錄、交付名稱不得沿用 staging 名稱，以及 64 張各 64 KiB 合成照片（合計 4 MiB）的逐張 staging／輸出 byte 一致性；殘留清理案例亦改為包含已部分寫入的 photos 子目錄。這個早期切片當時的完整 `CoupleSpaceTests` 為 44／44，加入下方容量預檢後的最新總數為 58／58。

2026-08-07 使用已 archived 且仍持有 personal archive 的真實 iPhone 執行「3. 匯出自己的個人封存」，系統「儲存到檔案」正常完成。人工核對 `manifest.json`、照片檔案、manifest／JPEG 對應、訊息文字及敏感欄位均無異常；未發現 Email、原始照片檔名或 token。這關閉 W1 資料夾候選的真機交付與小型封存內容核對，但不接受為最終產品格式。

目前 PoC 保留相同資料夾格式，但不再把所有 JPEG 同時保存在記憶體：client 逐張下載後立即寫入具完整檔案保護的專用暫存目錄，再由磁碟 manifest／photos 子 wrapper 重建一個不含來源名稱的根 `FileWrapper` 交給 `fileExporter`。匯出成功、失敗、登出與刪除封存時清理目前 staging；若 App 在準備途中被終止，下次匯出前只依專用前綴回收殘留目錄。真機複驗兩次確認：單純設定 `preferredFilename` 仍會保留來源 staging `filename`，系統交付時因此與 `/tmp` 內的來源同名；client 現已重建根 wrapper，regression 直接要求根 `filename == nil`、對外名稱正確且輸出內容完整。更新後真機可選擇新父資料夾並成功交付，且再次匯出仍可進入系統選擇器並成功儲存，確認同名碰撞與完成後清理已修正。完全斷網時會明確停在匯出準備失敗，恢復網路後重新整理並重試可正常交付，沒有殘留 staging 阻塞。這降低記憶體峰值並提供可重試的中斷清理，但尚未實作中斷點續傳，也沒有真機大型封存與低磁碟空間證據，因此不能宣稱大型容量安全。

migration `202608070013_w1_personal_archive_media_size.sql` 新增 owner-only archive item 的 `media_byte_size`，會回填可對應的既有封存，並在後續 `seal_personal_archive` 時複製已由照片 finalization 核對的 bytes。App 取得 manifest metadata 後，在建立 staging 與下載任何 JPEG 前，將 manifest bytes 加上所有已知照片 bytes，與暫存 volume 的可用空間比較；明確不足時顯示「裝置可用空間不足，未開始下載個人封存照片」。舊封存只要有任一照片缺少 bytes，就不以不完整估算阻擋既有匯出，仍由實際磁碟寫入錯誤保護。此候選不加入任意安全倍數、背景下載或中斷點續傳。migration 與 archived photo 契約已通過本機 140 個 pgTAP、public schema lint；iPhone 17 Pro Simulator 的完整 `CoupleSpaceTests` 58／58 通過。取得授權後 migration 已推送 Supabase 測試專案，遠端 history 顯示 local／remote `001`～`013` 一致，第二次 dry-run 回報 `Remote database is up to date`，linked `public` schema lint 無錯誤。更新後真機重新整理既有 archived relationship，個人封存項目數量、資料夾交付及 `manifest.json`／`photos` 內容均確認正常，證明回填沒有破壞既有封存的正常匯出路徑；真機實際低空間行為仍待驗證。

系統選擇器若以左上角逐層返回後按 X，真機不會立即回傳取消結果；下一次點擊匯出時才顯示上一輪「個人封存交付失敗」，再點一次仍可重新進入選擇器並成功儲存。此為 `fileExporter` 取消 callback 的延遲時序，沒有資料錯交或重試阻塞，但即時取消提示維持未通過，不把它記為正常完成路徑。

同次複驗亦發現 Simulator B 保留上一段 relationship 的 marker outbox。原本 fail-closed 規則正確阻止把舊項目混入目前 relationship，但沒有可恢復入口；W1 畫面現加入明確的「清除其他關係的待送測試標記」，只有整份 queue 都不屬於目前 relationship 才能清除，目前關係的待送項目仍必須重試。此規則已由 unit test 覆蓋；更新後 Simulator 冷啟動時 Outbox 已為「尚無待送標記」，因此本次沒有需要執行清除的舊項目。

### 核心雙向互動與雙向聊天活躍定義

2026-08-07 接受 PD-020，避免用自由聊天是否活躍掩蓋 Moment／共同約定的差異化核心：核心雙向互動只在同一 relationship 的兩位目前伴侶，對同一 Moment、同一題「我們的一題」或同一共同約定各有至少一次符合資格的文字、照片、Emoji 或回答參與時完成；同一 interaction object 只完成一次，完成時間取第二位伴侶首次使條件成立的時間。自由聊天則以半開週期 `[週起點, 下週起點)` 獨立判斷，雙方各至少一則訊息即計為一對，訊息數量不增加伴侶對計數。

W1 純規則使用 opaque content reference，而不是複製內容。完整文字、照片、Emoji 與回答仍保存在受 relationship RLS 保護的 Supabase 產品資料與私有 Storage，供跨裝置同步、重新安裝恢復、共同歷史、匯出與個人封存；分析資料只含 relationship、interaction／內容參照、表面、參與種類、participant 與時間。單方重複、不同 interaction object、重複內容參照及週期結束邊界均有 deterministic regression。雲端事件表／彙整尚未建立，也沒有新增 migration；產品資料與 Storage 的備份、還原與演練是獨立 release gate，分析事件不得被當成備份副本。

## Supabase 兩支真實 iPhone 最終 W1 閘門

此流程只關閉「兩支真實 iPhone、兩個 Apple 身分」的 development 證據，不取代 production／TestFlight 推播、實際低磁碟空間、大型封存或正式產品規格。不得再使用 Simulator 的成功結果代替其中任一裝置。

### 前提與紀錄邊界

1. 準備真實 iPhone A、B，兩台都安裝同一個目前 commit 的 Development build，並分別登入不同 Apple 身分。
2. 兩台都允許 CoupleSpace 通知，Supabase environment、App bundle identifier 與 APNs sandbox 環境一致。
3. 使用不含私人內容的測試文字與照片；只記錄裝置型號、iOS 版本、App build／commit、執行時間與畫面短 token，不保存完整 Email、access token、APNs token、invitation token 或照片內容。
4. 若沿用既有 relationship，先確認兩台顯示相同 relationship 短代碼、`active`、`2/2` 且 Outbox 全空；否則建立一段新的測試 relationship。

### A. 身分、配對與冷啟動

1. A、B 分別以 Apple 登入 Supabase；確認登入可用，且使用者短代碼不同。
2. 由 A 建立 invitation，B 接受；兩台重新整理後必須顯示同一 relationship 短代碼、`active`、`2/2`。
3. 兩台都強制結束 App，再重新啟動；不得重新登入，且 relationship 快照先可顯示，連網重新整理後仍收斂到相同 `active`、`2/2`。

2026-08-10 通過：iPhone 17 Pro Max（A）與 iPhone 14 Pro Max（B）均為 iOS 26.6，安裝相同 Development build `1.0 (1)`；來源以 commit `b1fca7b` 為基底，另含尚未提交的 iOS 26.0 deployment target 調整。兩台皆可完成 Supabase Apple 登入，使用者短代碼不同；A 建立 invitation、B 接受後，兩台確認為同一 relationship、`active`、`2/2`。雙方強制結束 App 並直接由主畫面重新啟動後，session 均保持登入，重新整理仍收斂到相同 relationship、`active`、`2/2`。未記錄完整 Apple ID、使用者代碼、invitation token 或 relationship 代碼。此結果關閉本節身分、配對與冷啟動證據，不推論後續雙向資料、弱網或推播已通過。

### B. 雙向資料與去重

1. A 寫入一筆 marker、一筆 W1 測試訊息及一張非私人照片；B 以前景 Realtime 或明確重新整理取得資料。
2. B 核對 marker／message／photo 短 token 與 A 相同；照片方向、比例與內容一致，沒有重複項目。
3. B 以另一組 marker、message、photo 回寫，A 完成同樣核對。
4. 兩台強制結束並重開，再次重新整理；雙方資料仍存在、最新順序一致，所有 Outbox 維持清空。

2026-08-10 通過：A 寫入新的 marker、W1 測試訊息與非私人測試照片後，三種 Outbox 均清空；B 明確重新整理後取得相同短 token。B 以另一組 marker、message、photo 回寫後，A 亦取得相同 token。雙向照片方向與比例正常，沒有重複項目。兩台強制結束並重開後，marker 與 message 會隨既有 RLS refresh 自動出現；photo 必須明確點選 Storage 重新整理才載入，載入後內容與 token 正確，Outbox 仍為空且沒有復活。此結果關閉本節雙向資料、去重與重啟持久性證據；照片冷啟動不自動讀取是目前 W1 技術畫面的已知 UX 邊界，不推論為資料遺失，也不代表正式 App 已接受人工重新整理。

### C. 頻繁弱網與跨啟動 Outbox

依序執行下列五輪，每輪使用新的短 token，且前一輪雙方收斂後才開始下一輪：

1. A 完全斷網，依序建立 marker、message、photo，確認三種 Outbox 都保留待送項目；保持斷網強制結束並重開 App，項目不得消失。
2. A 恢復網路並讓前景 recovery 自動處理，不按人工重試；B 核對三種資料各只出現一次、順序一致，A 的 Outbox 全部清空。
3. B 重複同一流程，讓 A 核對。
4. 再執行三輪：由具行動網路的裝置分別測一次 Wi-Fi→行動網路與行動網路→Wi-Fi，另一台至少測一次 Wi-Fi 短暫完全中斷與恢復。沒有行動網路的裝置須記為該切換情境不適用，不得以假設標為通過。若三次有限退避耗盡，項目必須保留，下一次前景或 unavailable→available 才可繼續，不得建立重複資料。
5. 任一輪若出現遺失、重複、錯序、舊 relationship 項目被送到目前 relationship，或成功後 Outbox 復活，即停止並記錄完整錯誤，不標示通過。

2026-08-10 五輪通過：A 完全斷網後建立 marker、message、photo，三種 Outbox 均顯示待送；保持斷網強制結束並直接重開 App 後，三種待送項目仍存在，relationship 可由使用者隔離的本機快照顯示。A 保持前景恢復網路且不按人工重試或重新整理後，unavailable→available recovery 自動清空三種 Outbox；B 明確重新整理後取得相同 token 與順序，三種資料都只新增一次。第二輪交換由 B 執行相同流程，跨啟動保存、自動清空及 A 端單次收斂結果亦相同。第三輪由 A 排入三種待送項目，恢復網路後立即由 Wi-Fi 切至行動網路；Outbox 最終自動清空，B 端三種資料各新增一次且 token、順序與照片均正確。B 沒有行動網路，因此 B 的行動網路切換情境記為不適用而非通過；第四輪改由 B 在 Wi-Fi 恢復、開始處理 Outbox 後短暫完全中斷約 5 秒再恢復，三種 Outbox 最終自動清空，A 端各新增一次且資料正確。第五輪由 A 在行動網路恢復、開始處理 Outbox 後切至 Wi-Fi，三種 Outbox 同樣自動清空，B 端各新增一次且 token、順序與照片均正確。此結果關閉本節五輪 development 前景／跨啟動證據，不代表真正背景傳送、無限重試或正式長時間退避已完成。

### D. Development 私人推播雙向送達

1. A 將 App 置於背景，由 B 排入一筆泛化 W1 測試推播；A 應收到不含 sender、relationship、訊息或照片內容的通知。
2. 將 A 的 App 完全終止後重測，再鎖定 A 重測；三種狀態都只能顯示相同泛化文案，點擊後由 App 重新讀取 RLS 資料。
3. 交換 A、B 角色，至少完成 B 的背景、終止與鎖定三種狀態。
4. 每一筆新工作只送達一次；若 Apple Watch 鏡像通知，只記錄為系統鏡像，不視為獨立 watchOS 功能。

2026-08-11 雙向三種狀態均通過：兩支真實 iPhone 都成功允許通知並登記 sandbox APNs token，畫面顯示的不可逆短指紋互不相同；完整 token 未記錄。A 分別在 App 置於背景、完全終止及裝置鎖定時，由 B 各排入一筆新的泛化 W1 測試推播；交換角色後，B 在相同三種狀態亦分別收到 A 排入的新工作。六筆工作都各只送達一次「CoupleSpace 有新動態／打開 App 查看」，通知未顯示 sender、relationship、訊息或照片內容；由通知開啟 App 後可正常讀取 relationship 資料。這關閉 development sandbox 的兩支真實 iPhone 雙向送達證據，不代表 production／TestFlight 已通過。

### 通過紀錄

- A、B 的裝置型號、iOS 版本、相同 App build／commit 與測試時間。
- A／B 使用不同 Apple 身分、相同 relationship、`2/2` 的匿名確認。
- 雙向 marker／message／photo、五輪弱網／跨啟動 Outbox 與雙向 development 推播的逐項結果。
- 任何失敗必須保留 Xcode／App 的完整錯誤碼與發生步驟；不得只以再次點擊成功覆蓋第一次失敗。

全部通過後，只能把「Supabase development 的兩支真實 iPhone」與「development 雙向推播」改為已完成。production／TestFlight、實際低磁碟、大型封存、中斷點續傳及未決正式規格仍保持未通過。

## W1 尚未關閉

- Supabase 路徑的兩支真實 iPhone、兩個 Apple 身分登入、配對、雙向 marker／message／photo、冷啟動及五輪弱網／跨啟動 Outbox 證據已通過；照片冷啟動後仍需明確重新整理才顯示，屬目前 W1 技術畫面的已知接縫，不代表資料遺失。
- 第三身分雲端拒絕已通過：遠端連線以不屬於目標 relationship 的 authenticated UUID 執行，relationship、memberships、shared items、personal archives 與 Storage objects 讀取皆為 0；marker、message、photo finalization 與解除配對 RPC 均回傳 `42501 relationship_not_accessible`。測後 relationship 仍為 active、probe rows 為 0，原有 5 筆照片 metadata／5 個 object 不變。這是受控遠端 RLS／RPC 證據，不等同第三個 Apple ID 的完整 UI 登入流程。
- 照片 upload／closing orphan reconciliation、月 30 張／累積 1 GB 配額拒絕與 orphan 清理已通過；PD-022 已關閉保存生命週期，不做時間型自動刪除，配額或降級只阻止新增。本機 Outbox 寫入前的精確 bytes 容量預檢已通過，頻繁弱網與真機低磁碟／容量壓力仍待驗證，大圖／方向與最後引用 GC 已通過。
- 推播 production／TestFlight 送達仍待實測；development sandbox 的兩支真實 iPhone 雙向接收者、背景／終止、鎖定畫面隱私已通過，既有 Watch 鏡像亦已通過但不視為獨立 watchOS 功能。
- 個人封存匯出的正式格式、容量、大型真機壓力、實際低磁碟空間與中斷後續傳；version 1 資料夾候選的真機交付、小型封存內容核對、磁碟 staging／殘留清理及容量預檢純規則已通過，migration 013 已部署 Supabase 測試專案。
- 正式訊息、照片畫質／正式額度、推播與背景重試的剩餘子決策；照片保存生命週期已由 PD-022 關閉，受管後端與共同資料系統紀錄已由 TD-001 關閉。
- 登入／前景一次性 outbox recovery 與三次有限短退避已通過本機規則及真機 A＋Simulator B 的背景返回、強制結束後重啟、短暫斷線自動送達、耗盡停止保留與下一次前景恢復送達；前景 unavailable→available 觸發已通過 59 個 Simulator tests，以及真機 A＋Simulator B 的自動清空與只送達一次驗證。正式長時間退避、production 網路監聽與真正背景重試仍未決定。

在上述證據完成前，G1 與 M0 維持未通過，不進入大量功能實作。
