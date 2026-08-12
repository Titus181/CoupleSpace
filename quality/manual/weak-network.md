# NETWORK-001：弱網、離線與重連

## 前置條件

- 兩支已配對真實 iPhone，使用可回收測試內容。
- 明確記錄本版本哪些內容已承諾持久 Outbox；尚未實作的能力標記 `NOT_APPLICABLE`，不得宣稱通過。

## 步驟與預期

1. A、B 同時離線建立已支援離線的內容，強制結束再重開；待送資料仍存在。
2. A 由 Wi-Fi 切換行動網路，B 做短暫 Wi-Fi 中斷；恢復後自動或由明確重試送達。
3. 同一 stable client ID 重試不產生重複；多筆內容維持可預期 FIFO／server order。
4. App 在背景、前景恢復與冷啟動時不並行重送同一項目。
5. 舊 relationship、closing／archived relationship 的待送內容不會誤送到目前伴侶。
6. UI 清楚區分傳送中、失敗、已同步；本機待送內容不得標示為已備份。

## 通過證據

記錄每輪網路轉換、force-quit 時點、送達次數、順序與 Outbox 最終狀態。漏送、重複、錯序、無限重試或送錯 relationship 都阻擋發布。
