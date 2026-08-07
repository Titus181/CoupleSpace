---
title: CoupleSpace Architecture
status: provisional
last_updated: 2026-08-07
---

# CoupleSpace Architecture

## 系統目的

CoupleSpace 提供一對一伴侶私密互動空間。iPhone MVP 聚焦配對、Moment、基本共同約定與其專屬討論、聊天、收藏、共同時間線、通知隱私與資料生命週期。

Watch、macOS、visionOS、Widget、訂閱、公開社群與 AI 關係分析不是目前核心。詳細範圍以 `product/04-iphone-mvp-scope.md` 為準。

## 目前狀態

- TD-001 已接受 Supabase 作為 iPhone v1 使用者身分、伴侶關係、共同資料與資料生命週期的唯一遠端系統紀錄；正式 App 不使用 CloudKit／Supabase 雙寫。
- `CoupleSpace/` 目前仍是 W1 技術驗證畫面；預設 SwiftData `Item` 型別保留但未接入 App，尚未形成產品領域架構。
- `CoupleSpaceTests/` 已涵蓋設定、登入 session、nonce、冪等／FIFO outbox、排序、照片政策、解除配對與通知隱私等純規則；`CoupleSpaceUITests/` 仍只有 Xcode 範例測試。
- `CoupleSpace Watch App Watch App/` 是獨立的初始 Watch 畫面，不是 iPhone MVP 必要流程。
- Supabase Auth、pairing／RLS、Realtime 變更提示、私有 Storage、marker FIFO outbox、向後相容的多張照片持久 FIFO outbox 及資料生命週期已完成 W1 最小 spike；純文字訊息契約與 FIFO outbox 已完成 migration 008 雲端部署及真機 A＋Simulator B 雙裝置實測，封存正文則僅有本機 pgTAP 證據。三張照片 queue 已通過同組裝置的斷網、跨啟動、FIFO 重送與跨裝置順序驗證。App 登入完成或由背景回到前景時，會先更新遠端狀態，再以單一 coordinator 依 marker、message、photo 順序立即嘗試一次目前 active relationship 的待送 queue；closing、archived、其他 relationship 與同時重入均不自動送出。真機 A＋Simulator B 已通過背景返回及強制結束後重啟兩條自動 drain 流程，三種 queue 均送達、清空、跨裝置可見且沒有重複；這仍只是 foreground recovery 候選，不包含網路監聽、退避或背景排程。migration 011 與 client reconciliation 已關閉「Storage upload 成功、metadata 因 closing 被拒絕」可能留下 orphan object／永久卡住 outbox 的競態：已存在的 sealed metadata 視為送達，缺少 metadata 才由原上傳者清除物件；migration 已部署測試專案，真機 A 離線待送＋Simulator B 觸發 closing 的跨裝置時序亦已通過。migration 012 現建立 W1 Free 照片配額候選：App 不可直接建立 photo metadata，Security Definer RPC 會鎖住 relationship、核對私有 Storage object 的 owner 與 bytes，再以 UTC 月曆月 30 張及每段關係 1,000,000,000 bytes 執行原子確認；配額拒絕後 client 會刪除剛上傳的 orphan，網路或清理失敗則保留 outbox。這是 PD-021 的 TestFlight 研究起點，不是正式 entitlement、週期或上市上限；migration 已部署 Supabase 測試專案，真機 A＋Simulator B 的近同時上傳已確認兩個不同 token 均落盤、雙方收斂至同一張最新照片且 Outbox 清空，配額拒絕及其 orphan 清理仍待遠端實測。私人推播 migrations 009／010 與 `send-w1-push` Edge Function 已部署 Supabase 測試專案，APNs secrets 已設定且真機 sandbox token 登記成功；sender 以原子 claim／complete 處理只含 routing metadata 的工作，固定送出泛化 payload。Simulator B 已成功把通知送達背景、終止及鎖定狀態的真機 A，鎖定畫面與 Apple Watch 鏡像通知皆只顯示正確泛化文案。個人封存匯出已加入 owner-only RLS 讀取、version 1 JSON manifest、UUID JPEG 檔名與系統資料夾 exporter，並通過真機「儲存到檔案」與內容核對；目前照片改為逐張下載至受保護暫存目錄，`fileExporter` 以磁碟子項目重建不含 staging filename 的根 `FileWrapper`，完成、失敗與下次匯出前會清理專用暫存。大型封存真機壓力、磁碟空間與中斷後續傳仍屬技術閘門。兩支真實 iPhone 與照片容量／保存政策亦尚未關閉。
- W1 畫面會依 Supabase user UUID 保存最近一次由伺服器確認的 relationship UUID、status 與 member count，供斷網冷啟動顯示；這份唯讀快照不作為共同資料寫入授權，所有操作仍須通過 Supabase session、RPC 與 RLS。
- CloudKit Sharing PoC 保留為實驗紀錄，不再是 v1 共同資料候選。

## 目標責任邊界

以下是責任與依賴原則，不預先強制資料夾或 framework 數量；G1 決策後再選擇最小可行實作：

| 責任 | 內容 |
| --- | --- |
| App composition | 啟動、dependency wiring、環境與平台入口 |
| Presentation | SwiftUI 畫面、navigation、顯示狀態與使用者意圖 |
| Application | 配對、Moment、共同約定、約定討論、聊天、收藏、時間線與資料生命週期 use cases |
| Domain | 不依賴 UI／儲存框架的規則、狀態轉換與 value types |
| Data／Services | Supabase Auth、Postgres／RLS／RPC、Realtime 變更提示、私有 Storage、持久 outbox、通知與分析 adapter |
| Platform | Face ID、background、push、Apple framework integration |

## 依賴方向

- Presentation 可以依賴 Application／Domain，不直接承擔同步、授權或重試規則。
- Application 組合 Domain 與抽象 service contracts，不依賴具體 SwiftUI 畫面。
- Domain 不依賴 SwiftUI、SwiftData、CloudKit、通知或分析 SDK。
- Data／Platform 實作上層所需 contracts；外部 payload 不直接成為 Domain model。
- Watch 不成為 iPhone 核心 Domain／Application 的必要依賴。
- 不為尚未出現的第二個實作預建抽象；只有在可測試邊界或平台替換確有需要時才引入 protocol。

## 核心資料流

```text
使用者操作
→ Presentation
→ Application use case
→ Domain 規則與授權判斷
→ Data／Platform adapter
→ 本機 outbox 或 Supabase 受管服務
→ 明確的成功／失敗／重試狀態
→ Presentation
```

任何遠端寫入都必須由 Supabase session 與伺服器端伴侶關係範圍驗證。Realtime 事件只作變更提示，client 必須重新經 RLS 讀取；同步事件與重試使用穩定 client UUID，避免重複建立訊息或 Moment。正式產品資料模型由後續垂直切片依已驗證的不變量最小化建立。

## 敏感資料邊界

- 私密訊息、照片、Moment 內容與伴侶關係屬敏感資料。
- 完整內容由受 relationship RLS 保護的 Supabase 產品資料與私有 Storage 保存，作為跨裝置同步、重新安裝恢復、共同歷史、匯出與個人封存的來源；分析資料不是備份來源。
- 通知預設只帶最小路由資訊；鎖定畫面不得預設揭露內容。
- 分析只記錄產品驗證所需的 relationship、interaction／內容參照、表面與參與種類、participant 與時間，不複製訊息文字、照片、Emoji 值或回答內容。
- 產品資料庫與 Storage 的雲端災難復原須有獨立備份、還原與演練 gate，不以分析事件或裝置快取替代。
- Log、crash report、測試 fixture 與 Eval 不得包含真實私人資料或 secrets。
- 匯出、刪除與解除配對必須共享同一套已核准的資料生命週期規則。

## 雲端可靠性與成本營運

- Supabase 維持唯一遠端系統紀錄；不為供應商事故或成本焦慮預建 CloudKit／Supabase 雙寫。替代方案必須先有真實瓶頸與遷移證據。
- 資料庫備份與 Storage object 保護是兩個獨立控制；正式上市前須分別定義復原方式並演練，不能把資料庫備份視為照片備份。
- Realtime 只提示變更，client 經 RLS 重讀；離線操作留在持久 outbox，避免短暫事故造成資料遺失或重複送出。
- 照片依 PD-019 在裝置端產生適合共同回顧的版本，不保存相機原檔。確切 display／thumbnail 規格須由畫質、載入、Storage 與 egress 實測決定。
- 每週監控 p95 latency、錯誤率、DB／連線、Realtime、outbox age、Storage、origin／cached egress，以及每個活躍伴侶對的直接成本。
- 不對外承諾固定人工事故回覆或復原時間；以自動警報、狀態頁、降級模式、runbook、憑證復原與定期 restore drill 降低單人營運風險。

完整客服、版本公告、成本情境與上市 gate 見[上市、客服與版本發布營運](operations/03-launch-support-and-release.md)。

## 測試接縫

- Domain／Application 規則應可在不啟動 Simulator 或遠端服務下測試。
- Data／Platform adapters 使用受控測試環境或 deterministic fakes 驗證錯誤、離線與重試。
- UI tests 以可注入的測試啟動狀態執行，避免依賴 production 帳號或資料。
- Apple ID、推播、背景、Face ID 與真實跨裝置同步保留真機驗證，不偽裝成純 unit coverage。

## 架構不變量

1. 一位使用者最多只有一個有效伴侶關係。
2. 任何共同資料讀寫都必須驗證正確的伴侶範圍。
3. 訊息、共同約定與 Moment 的重試不能造成重複資料；排序規則必須可預期。
4. 通知與分析預設採資料最小化，不洩漏私密內容。
5. 刪除、匯出與解除配對依同一份明確規則執行。
6. iPhone 核心流程不依賴 Watch 或非 MVP 平台。
7. 未通過 G1 實測的外部技術選擇維持 provisional，不寫成既定事實。

其中第 1–5 項由 Supabase constraint、RLS、RPC、私有 Storage 與受控 Edge Function 執行伺服器端 enforcement；精確產品資料模型仍須在後續垂直切片中補充，並轉成 unit／integration／real-device regression gates。
