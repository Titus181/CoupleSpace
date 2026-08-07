---
title: 技術決策紀錄
status: active
last_updated: 2026-08-07
---

# 技術決策紀錄

本文件記錄會影響系統責任、資料所有權或後續實作方向的技術決策。`proposed` 項目只供審核，不得視為已接受架構；接受後才同步更新架構文件與開發路線圖。

## 決策狀態

- `accepted`：目前有效。
- `superseded`：已被後續決策取代。
- `proposed`：尚未確認，不應當成規格實作。

## 已確認決策

### TD-001：Supabase 作為 iPhone v1 共同資料的受管後端

- **狀態：** accepted
- **日期：** 2026-08-06
- **決策：** iPhone v1 使用 Supabase 作為使用者身分、伴侶關係、共同資料與資料生命週期的唯一遠端系統紀錄；不以 CloudKit Sharing 作為正式共同資料來源，也不建立 CloudKit／Supabase 雙寫。

#### 責任

- Sign in with Apple 取得的原生 credential 交由 Supabase Auth 建立及恢復 App session。
- Postgres constraint、RLS 與受控 RPC 執行一對一關係、共同資料授權、解除配對、雙份個人封存與獨立刪除不變量。
- Realtime 只作為變更提示；client 收到事件後必須重新經 RLS 讀取，不直接信任事件 payload。
- 私有照片存放於 Supabase Storage；App 先在裝置端重新編碼，再寫入具 relationship scope 的 metadata，不使用 public URL。
- 遠端寫入使用持久 client UUID outbox；伺服器執行冪等寫入並回傳時間，client 以穩定規則排序及明確呈現待送／失敗／成功狀態。
- Edge Function 只承擔需要服務端權限的非同步工作，例如最後引用照片的 Storage GC；App 不持有 service-role secret。

#### 已有證據

- 兩個不同 Apple 身分已通過原生登入、session 恢復與登出。
- 同一 relationship 的 pairing、`2/2` membership、雙向 RLS 寫入及雙向 Realtime 變更提示已通過真機 A＋Simulator B 實測。
- 私有 Storage 照片已通過雙向上傳、讀取與前景重啟恢復。
- 單筆及三筆 FIFO marker metadata outbox 已通過斷網、強制結束 App、恢復網路、明確重試、順序一致與資料庫冪等驗證。
- 三筆 FIFO photo outbox 已通過斷網 enqueue、強制結束 App、恢復網路、單次 drain、順序一致與跨裝置可見性驗證。
- 最近一次伺服器確認的 relationship 識別、狀態與成員數可依使用者保存為唯讀顯示快照；快照不得取代 session、RPC 或 RLS 授權。
- relationship closing、禁止新增、雙份 owner-isolated archive、獨立刪除及最後引用 Storage GC 已通過雲端實測。
- CloudKit Sharing 的 owner／participant 權限無法單獨保證 PD-011 要求的對等封存權，因此不符合正式共同資料來源的硬性條件。

#### 本決策不會一併定案

- 正式訊息、Moment、共同約定及其討論的完整資料模型。
- 照片容量、壓縮品質、保存期限、正式 upload queue、自動重試與清理政策；W1 多張持久 FIFO outbox 只作風險驗證。
- APNs device token、推播 worker、背景喚醒及鎖定畫面實測細節。
- 個人封存的正式匯出格式、交付方式與大型資料處理；W1 已有 version 1 JSON manifest＋UUID JPEG 資料夾候選，但尚未接受為最終產品契約。
- outbox 的自動排程、退避、網路監聽與正式訊息的長佇列上限。
- Firebase 作為事故備援或未來替代方案；v1 不為未採用的第二套後端預建 adapter。

#### 影響

- `ARCHITECTURE.md` 可將帳號、共同資料、同步與資料生命週期由 provisional 候選更新為上述責任邊界。
- W1 後續只需關閉 Supabase 路徑的剩餘風險，不再為 CloudKit Sharing 補做兩支真機的正式架構證據。
- G1 與 M0 仍不得標示通過，直到第三身分雲端拒絕、照片弱網／刪除一致性、推播隱私與必要的兩支真機證據完成。
- CloudKit Sharing PoC 保留為實驗紀錄；正式 App 不進行雙寫、資料遷移或 fallback，以避免衝突與不一致的所有權語意。

#### 替代方案

- **CloudKit Sharing only：否決。** 無法保證解除配對後 participant 在 owner 撤銷分享前取得不可被剝奪的個人封存。
- **CloudKit 與 Supabase 雙寫：否決。** 沒有產品需求需要兩套共同資料來源，會新增衝突、刪除、封存與事故恢復風險。
- **Firebase：保留但不進入 v1 spike。** 能力可行，但目前沒有足以抵銷重做已驗證 constraint、RLS、archive 與 Storage lifecycle 的證據。
