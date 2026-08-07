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
- Supabase Auth、pairing／RLS、Realtime 變更提示、私有 Storage、marker FIFO outbox、向後相容的多張照片持久 FIFO outbox 及資料生命週期已完成 W1 最小 spike；純文字訊息契約與 FIFO outbox 已完成 migration 008 雲端部署及真機 A＋Simulator B 雙裝置實測，封存正文則僅有本機 pgTAP 證據。三張照片 queue 已通過同組裝置的斷網、跨啟動、FIFO 重送與跨裝置順序驗證。migration 011 與 client reconciliation 已關閉「Storage upload 成功、metadata 因 closing 被拒絕」可能留下 orphan object／永久卡住 outbox 的競態：已存在的 sealed metadata 視為送達，缺少 metadata 才由原上傳者清除物件；migration 已部署測試專案，真機 A 離線待送＋Simulator B 觸發 closing 的跨裝置時序亦已通過。私人推播 migrations 009／010 與 `send-w1-push` Edge Function 已部署測試專案，APNs secrets 已設定且真機 sandbox token 登記成功；sender 以原子 claim／complete 處理只含 routing metadata 的工作，固定送出泛化 payload。Simulator B 已成功把通知送達背景、終止及鎖定狀態的真機 A，鎖定畫面與 Apple Watch 鏡像通知皆只顯示正確泛化文案。個人封存匯出已加入 owner-only RLS 讀取、version 1 JSON manifest、UUID JPEG 檔名與系統資料夾 exporter，並通過真機「儲存到檔案」與內容核對；它仍一次把所有照片載入記憶體，因此大型封存仍屬技術閘門。兩支真實 iPhone 與照片容量／保存政策亦尚未關閉。
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
- 通知預設只帶最小路由資訊；鎖定畫面不得預設揭露內容。
- 分析只記錄產品驗證所需事件，不記錄訊息文字或照片內容。
- Log、crash report、測試 fixture 與 Eval 不得包含真實私人資料或 secrets。
- 匯出、刪除與解除配對必須共享同一套已核准的資料生命週期規則。

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
