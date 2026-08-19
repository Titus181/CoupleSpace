# W8–W11 完整改版回歸

這份清單編排 W8–W11 曾實際執行的測試，供大改版、TestFlight candidate 或聊天／共同約定高風險變更後重跑。它不取代個別測試本體；詳細步驟與證據欄位仍以連結的 catalog／manual 文件為準。

## 0. 測試版本與前置條件

- 記錄 commit、App version／build、backend、migration history、兩台 iOS 版本與測試時間。
- 使用兩支真實 iPhone、兩個不同測試 Apple 身分及可丟棄 relationship；不得使用真實私人內容。
- 自動化與人工測試都必須晚於最後一個行為變更。Build 或歷史 PASS 不能代替本次 runtime 結果。
- 先執行 `quality/scripts/run-full-automated-suite.sh --reset-local-database`；記錄 pgTAP、APNs、iPhone executions／failures／skips、Harness 與 diff hygiene 結果。
- 任一 failure、skip、BLOCKED、資料錯交、遺失、重複、錯序或隱私外洩都阻擋發布。

## 1. W8 基本文字聊天（CHAT-001）

1. A、B 各傳一則 4,000 字以內的文字；本機立即顯示，另一台 Realtime 收到且只出現一次。
2. 核對雙方順序、伺服器時間與未讀數；自己的訊息不增加自己的未讀。
3. B 進入對話後，只清除 B 已載入範圍的未讀；游標不得倒退，A 看不到 B 的已讀狀態或已讀時間。
4. 點擊訊息區及向下拖曳都能收起鍵盤，底部「今天／對話／我們」仍可切換。
5. 兩台強制結束後重開，文字、時間、relationship 與未讀狀態仍一致。

自動化責任與實際檔案見 `quality/test-catalog.md` 的 `CHAT-001`；雙機共通步驟見 `quality/manual/two-iphone.md`。

## 2. W9 可靠傳送與離線快照（CHAT-002／TODAY-001／NETWORK-001）

完整執行 `quality/manual/weak-network.md` 的一般步驟 1–11，並特別確認曾發生過的回歸：

- enqueue 失敗時輸入框不得清空；pending／failed 訊息跨 App 重啟仍存在。
- FIFO 第一筆失敗時，後續項目不得永久停在「傳送中」或超車；有限重試耗盡後可明確手動重試。
- Realtime refresh 執行中收到的新事件不得遺失；恢復網路後接收方不需重啟 App。
- 有快照後離線冷啟動仍顯示「今天／對話／我們」、最近 200 則聊天與 Today 歷史，不得跳出帳號設定或顯示成全新空白。
- 同一 stable client UUID 在 acknowledgement 遺失後重送仍只建立一則；登出、換帳號或 relationship 改變後不得顯示或誤送舊資料。

## 3. W10 聊天照片、Emoji 與收藏（CHAT-003／CHAT-004／MOMENT-003）

完整執行：

- `quality/manual/two-iphone.md` 的「W10 加驗」1–6。
- `quality/manual/weak-network.md` 的「W10 加驗」1–4。

每次完整 release gate 都要重新執行兩個尚不能由既有證據取代的故障注入：接近 quota 的拒絕後不得留下可讀 orphan object；Storage 上傳成功但 acknowledgement 遺失時，以同一 stable client ID 重送不得產生第二則訊息或第二份 object。未能注入時必須記為 `BLOCKED`，不可沿用 2026-08-13 的部分完成結果。

## 4. W11 共同約定與專屬討論（APPOINTMENT-001）

1. 由長按來源訊息、輸入列「＋」、Today／共同日程建立約定；同一 client／operation ID 重送不建立第二張卡片。
2. A、B 核對主對話卡片、近期列表、月曆、詳情與專屬討論指向同一 appointment；專屬討論文字、照片、Emoji、收藏 Moment 與來源返回不得串到主對話或另一筆約定。
3. 修改標題／地點／備註／提醒不得產生重大事件；修改開始時間與取消則各產生一筆不可偽造、不可重複的永久紀錄，主對話與正確專屬討論都可見。
4. 取消後卡片與討論歷史保留，但不得再新增內容、編輯回 scheduled，或由較晚送達的舊操作復活。
5. 完整執行 `quality/manual/weak-network.md` 的「W11 加驗」：離線改期／取消、force-quit、FIFO、lost acknowledgement 與提醒排程。
6. 離線重開時，已同步約定快照先出現，再立即疊加本機待送修改；不得先顯示空白或舊時間。進入約定詳情／編輯頁後，離線提示不得遮擋或攔截返回／取消控制。
7. 完整執行 `quality/manual/two-iphone.md` 的「W11 加驗」與提醒驗證：每台只排一次通用通知，不含標題／地點／註記，點擊開啟正確約定；改期、取消、登出或解除配對後移除舊提醒。
8. 最後才執行 `quality/manual/deletion-and-unpairing.md` 的 W11 封存驗證；A 刪除自己的封存後，B 的約定、專屬討論、照片與重大事件關聯仍須完整。

## 5. 結果保存

- 複製 `quality/release-record-template.md` 到 `quality/releases/`，逐項記錄 `PASS／FAIL／BLOCKED／NOT_APPLICABLE` 與理由。
- `.xcresult`、截圖、通知畫面與裝置 log 不直接提交含私人內容的原始檔；只記錄去識別後的統計、時間、環境及安全 artifact 位置。
- 若本輪再次發現產品缺陷，先在最低可靠層級加入 regression，再更新 `quality/regression-history.md` 與相應 catalog ID。

## 2026-08-20 final W13 candidate 結果

- 結果：`PASS`（W13 引用範圍）。
- W8：使用者在同一最終候選的 LOCK／PUSH／5C／W8 合併流程中回報正常。
- W9／W10／W11：使用者依 W13 整合清單完成 active relationship regression 並回報正常；兩個 W10 故障注入的逐項 artifact／metadata 為 `未記錄`，本結果不得用來回溯改寫 2026-08-13 的部分完成紀錄或獨立宣稱完整 TestFlight Gate D。
- W11 lifecycle／archive cleanup：依本清單順序延後至最後 destructive lifecycle，使用者回報正常。
- iPhone 機型／iOS、精確網路條件、stable ID 前綴與完成時間：`未記錄`。
- 本結果提供 `W13-INTEGRATION-001` closure credit；不宣稱 TestFlight Gate D、DR／UPGRADE 或全產品 release-ready。
