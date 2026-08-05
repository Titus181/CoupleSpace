---
title: W1 技術驗證紀錄
status: in_progress
last_updated: 2026-08-05
---

# W1 技術驗證紀錄

## 本週決策方式

W1 不先完成正式產品架構。先以最小真機 spike 驗證最大未知數，再依結果接受或否決候選方案。

目前第一候選為 Apple 原生 CloudKit Sharing；替代候選為具備伺服器端身分、關係範圍授權、Realtime、物件儲存與推播 worker 的受管後端。替代候選只保留為比較基準，尚未建立外部專案或加入 SDK。

## 候選方案狀態

| 閘門 | CloudKit Sharing 假設 | 驗證狀態 | 否決條件 |
| --- | --- | --- | --- |
| 身分與配對 | 使用 iCloud 帳號接受私人 `CKShare`，一個 share 對應一段伴侶關係 | 真機 A＋Simulator B、兩個 Apple ID 初步通過；兩支真機待驗證 | 無法穩定接受、恢復或限制為正確兩人 |
| 同步與聊天 | `CKSyncEngine` 同步 private/shared database；client UUID 形成穩定 record name；server timestamp 加 UUID 決定順序；本機 outbox 顯示傳送狀態 | 純規則測試已建立；共享標記雙向寫入與重啟恢復初步通過，離線與正式同步模型未驗證 | 離線重送造成遺失、重複、不可預期錯序，或 shared database 行為不足以可靠恢復 |
| 照片 | 顯示圖與縮圖先在裝置端重新編碼，再以 `CKAsset` 儲存；正式尺寸、品質、容量與保存期依實測決定 | 真機 A＋Simulator B、兩個 Apple ID 的雙向讀寫與重啟恢復初步通過；兩支真機、弱網與刪除待驗證 | 成本、速度、弱網恢復或刪除一致性不可接受 |
| 推播 | database subscription 只作變更提示；抓取並驗證 relationship/recipient 後才更新 App；使用者可見內容固定為泛化文案 | 資料最小化規則測試已建立；真機未驗證 | 錯發、鎖定畫面洩漏內容，或背景同步不足以支撐體驗 |
| 所有權與解除配對 | 雙方各自保留不可被對方剝奪的唯讀封存 | A1 政策已確認；Supabase 本機 RLS／封存測試與雲端 schema 部署通過，Auth、雲端雙身分行為及 Swift 整合待驗證 | 無法提供雙方可理解、可稽核且不依賴單方善意的保留、匯出、刪除結果 |
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

以 Supabase CLI 2.111.0 與 local stack 建立可重現 migration，先在本機驗證後再部署至專用雲端測試專案；尚未加入 Swift SDK。schema 只保存 relationship、membership、無內容 shared item 與 personal archive metadata，不含真實訊息、照片或帳號資料。

- `supabase db reset --local` 成功從 migration 重建資料庫。
- `supabase test db` 的 16 個 pgTAP 案例全部通過：兩位 member 可見、第三人拒絕、一人不可同時加入兩段未封存關係、active 可寫、closing 禁止新內容、單方封存不足以結束、雙方封存後才 archived、伺服器複製共同項目、個人封存只能本人讀取與刪除、刪除一方封存不影響另一方。
- `supabase db lint --local` 回報沒有 schema error。
- 第一次測試曾抓到 PL/pgSQL 變數與欄位同名造成的 ambiguous reference；重新命名、重建資料庫後通過，未以 retry 或放寬 policy 掩蓋。
- 遠端 dry-run 只列出 `202608050001_w1_relationship_archive_spike.sql`；取得明確授權後已套用至雲端測試專案。
- 遠端 migration 歷史顯示 local／remote 皆為 `202608050001`，再次 dry-run 回報資料庫已是最新狀態。
- `supabase db lint --linked` 對遠端 `extensions` 與 `public` schema 回報沒有 schema error。

此結果驗證本機 Postgres constraint、transaction、security-definer function 與 RLS 測試，以及相同 migration 可部署至雲端且通過 schema lint；尚未驗證雲端 Supabase Auth／Sign in with Apple、兩個身分的實際 RLS 行為、Swift SDK、Realtime、Storage、弱網、Push、服務中斷或計費。因此 Supabase 仍是 provisional 候選，不能標示為正式架構。

## W1 尚未關閉

- CloudKit Sharing 的兩支真實 iPhone、兩個 Apple ID 雙向證據。
- 以雲端 Supabase 測試專案與兩個測試身分驗證 Auth、RLS、Realtime、Storage，再進行 Swift SDK 最小整合；schema 部署已完成。
- 照片弱網、離線重試、大圖與方向組合、保存期限及刪除一致性實測。
- 推播接收者、背景同步與鎖定畫面隱私真機實測。
- 最終登入、同步、聊天、照片、推播與資料生命週期架構決策。

在上述證據完成前，G1 與 M0 維持未通過，不進入大量功能實作。
