---
title: CoupleSpace Architecture
status: provisional
last_updated: 2026-08-04
---

# CoupleSpace Architecture

## 系統目的

CoupleSpace 提供一對一伴侶私密互動空間。iPhone MVP 聚焦配對、Moment、聊天、收藏、共同時間線、通知隱私與資料生命週期。

Watch、macOS、visionOS、Widget、訂閱、公開社群與 AI 關係分析不是目前核心。詳細範圍以 `product/04-iphone-mvp-scope.md` 為準。

## 目前狀態

- `CoupleSpace/` 已以 W1 CloudKit Sharing spike 作為啟動畫面；預設 SwiftData `Item` 型別仍保留但未接入 App，尚未形成產品領域架構。
- `CoupleSpaceTests/` 與 `CoupleSpaceUITests/` 目前只有 Xcode 範例測試。
- `CoupleSpace Watch App Watch App/` 是獨立的初始 Watch 畫面，不是 iPhone MVP 必要流程。
- 帳號、跨 Apple ID 分享、即時聊天、照片、推播與資料所有權仍屬 G1 技術閘門，不得在此假定實作方案。

## 目標責任邊界

以下是責任與依賴原則，不預先強制資料夾或 framework 數量；G1 決策後再選擇最小可行實作：

| 責任 | 內容 |
| --- | --- |
| App composition | 啟動、dependency wiring、環境與平台入口 |
| Presentation | SwiftUI 畫面、navigation、顯示狀態與使用者意圖 |
| Application | 配對、Moment、聊天、收藏、時間線與資料生命週期 use cases |
| Domain | 不依賴 UI／儲存框架的規則、狀態轉換與 value types |
| Data／Services | 儲存、同步、帳號、通知、照片、分析與其 adapter |
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
→ 本機或核准的遠端服務
→ 明確的成功／失敗／重試狀態
→ Presentation
```

任何遠端寫入都必須帶有可驗證的使用者與伴侶關係範圍。同步事件與重試需要穩定識別，避免重複建立訊息或 Moment；正式模型由 G1 實測後決定。

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
3. 訊息與 Moment 的重試不能造成重複資料；排序規則必須可預期。
4. 通知與分析預設採資料最小化，不洩漏私密內容。
5. 刪除、匯出與解除配對依同一份明確規則執行。
6. iPhone 核心流程不依賴 Watch 或非 MVP 平台。
7. 未通過 G1 實測的外部技術選擇維持 provisional，不寫成既定事實。

其中第 1–5 項的精確資料模型與伺服器 enforcement，必須在 G1 決策後補充並轉成 unit／integration／real-device regression gates。
