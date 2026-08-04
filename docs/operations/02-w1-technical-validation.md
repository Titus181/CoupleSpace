---
title: W1 技術驗證紀錄
status: in_progress
last_updated: 2026-08-04
---

# W1 技術驗證紀錄

## 本週決策方式

W1 不先完成正式產品架構。先以最小真機 spike 驗證最大未知數，再依結果接受或否決候選方案。

目前第一候選為 Apple 原生 CloudKit Sharing；替代候選為具備伺服器端身分、關係範圍授權、Realtime、物件儲存與推播 worker 的受管後端。替代候選只保留為比較基準，尚未建立外部專案或加入 SDK。

## 候選方案狀態

| 閘門 | CloudKit Sharing 假設 | 驗證狀態 | 否決條件 |
| --- | --- | --- | --- |
| 身分與配對 | 使用 iCloud 帳號接受私人 `CKShare`，一個 share 對應一段伴侶關係 | 待兩 Apple ID 真機驗證 | 無法穩定接受、恢復或限制為正確兩人 |
| 同步與聊天 | `CKSyncEngine` 同步 private/shared database；client UUID 形成穩定 record name；server timestamp 加 UUID 決定順序；本機 outbox 顯示傳送狀態 | 純規則測試已建立；遠端同步未驗證 | 離線重送造成遺失、重複、不可預期錯序，或 shared database 行為不足以可靠恢復 |
| 照片 | 原檔與縮圖先在裝置端移除 metadata、壓縮，再以 `CKAsset` 儲存；正式尺寸、品質、容量與保存期依實測決定 | 尚未驗證 | 成本、速度、弱網恢復或刪除一致性不可接受 |
| 推播 | database subscription 只作變更提示；抓取並驗證 relationship/recipient 後才更新 App；使用者可見內容固定為泛化文案 | 資料最小化規則測試已建立；真機未驗證 | 錯發、鎖定畫面洩漏內容，或背景同步不足以支撐體驗 |
| 所有權與解除配對 | 建立分享者是 owner；另一方是 participant | 已知有結構性風險 | 無法提供雙方可理解、可稽核且不依賴單方善意的保留、匯出、刪除結果 |
| 有意義雙向互動 | 同一 relationship、同一 interaction object 內，兩個目前伴侶各至少有一次符合資格的 contribution；只記 ID、種類與時間，不記內容 | 純規則測試已建立 | 事件無法區分單方重複操作與真正雙方參與，或需要記錄私密內容 |

## CloudKit Sharing PoC

### 自動化範圍

- `MessageIdentity` 以 client UUID 產生穩定 record name，同一次重試不得建立第二筆訊息。
- delivery reducer 明確區分 queued、sending、sent、failed 與嘗試次數。
- 已有 server timestamp 時，以 server timestamp 排序；同時間以 UUID 穩定打破平手。
- 通知顯示文案不含訊息、照片或 Moment 內容。
- 有意義雙向互動必須包含預期的兩位不同參與者。

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

## W1 尚未關閉

- CloudKit Sharing 的跨 Apple ID 雙向真機證據。
- owner/participant 非對稱模型是否符合共同資料生命週期；若不符合，改做受管後端最小 spike。
- 照片上傳、縮圖、弱網與刪除實測。
- 推播接收者、背景同步與鎖定畫面隱私真機實測。
- 最終登入、同步、聊天、照片、推播與資料生命週期架構決策。

在上述證據完成前，G1 與 M0 維持未通過，不進入大量功能實作。
