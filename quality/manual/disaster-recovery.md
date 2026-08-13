# DR-001：雲端災難復原與異區冷重建

## 前置條件

- 使用 production-like 或經核准的隔離環境；不得直接對 production 執行破壞性 restore。
- 準備兩個測試使用者、第三個非 relationship 使用者、兩支真實 iPhone，以及包含聊天、照片、Moment、回答、約定、討論、名稱、狀態、個人封存、刪除與解除配對的可核對資料集。
- 指定 recovery point、Database artifact、Storage manifest、deletion journal sequence、schema version 與預期 counts／checksums。
- 記錄最後成功 Database／Storage／journal 時間；credentials、私人內容與真實 object path 不得進入 release record、截圖或 log。

## D3 同站還原

1. 將 service mode 設為 `read_only`，停止 migration、GC、刪除 worker 與非必要寫入。
2. 選擇錯誤事件之前的 PITR recovery point，記錄選擇理由及預估資料缺口。
3. 還原 Database，依 manifest 核對 Storage object version，不假設 database restore 會恢復實際檔案。
4. 重播 recovery point 之後的 deletion tombstone。
5. 通過下方完整性及真機檢查後，依 `recovery → normal` 分階段恢復。

## D4 異區冷重建

1. 在另一 region／核准替代環境建立全新 project，不讓舊主站與新站同時接受 production 寫入。
2. 從 Git 鎖定版本部署 extensions、schema、RLS、RPC，再還原 Database artifact。
3. 依 manifest 恢復被引用的 Storage object，逐一核對 bytes／checksum。
4. 重建 Auth／Sign in with Apple callback、Realtime publication、Storage policy、Functions 與必要設定；輪替所有可能受影響的 secrets。
   - 核對原 Supabase Auth user identity、Apple identity mapping 與 relationship／membership 對應未改變；舊 session 全部視為失效，裝置清單只由新主站有效 session 重建。
5. 重播 deletion journal，確認 sequence 連續且已刪除／解除配對／GC 資料不會恢復可見。
   - 核對一般裝置 session 撤銷及本次 D4 session 全面失效都沒有建立 deletion tombstone。
6. 驗證 signed service manifest 拒絕無效簽章、過期、錯 environment 及 version rollback，並可切換 `read_only／recovery／normal`。
7. 完成全部自動化與真機核對後才開放寫入；舊站恢復後保持 forensic／read-only，不自動 failback。

## 完整性核對

- schema／migration／backup workflow version 相符。
- 主要資料表 counts、min／max server timestamp、stable UUID 唯一性相符。
- relationship、membership、active／archived 及 owner-only archive 沒有孤兒或錯配。
- 每一個 photo reference 均有相符 object、bytes 與 checksum；多餘 object 不被公開。
- Moment、回答揭露、約定、討論、收藏與主對話引用可返回正確來源。
- 第三個使用者無法讀寫 relationship、archive、Storage object 或 RPC。
- deletion journal 無缺段；被刪內容、解除配對及 GC object 不復活。
- 通知、log、監控、artifact 與 release record 不含私人內容或 secrets。

## 真機恢復

1. iPhone A 保留舊 build 與待送項目；iPhone B 清除本機狀態。
2. iPhone B 以原測試帳號重新驗證，不操作舊機、不重新配對，恢復 relationship 與完整歷史。
3. 核對數量、正文、照片、server time、排序、引用、名稱、狀態及 owner-only archive。
4. `recovery` 期間只允許核准的唯讀／待送行為；不具持久 Outbox 的寫入入口必須停用。畫面顯示服務狀態、內容截至時間與待送數量，不得顯示「所有內容已同步」。
5. 恢復 `normal` 後 drain iPhone A 的舊 Outbox，確認只送達一次、順序正確且不跨 relationship。
6. 伺服器確認最新狀態且 Outbox 清空後，才核對「所有內容已同步」；再執行 App 刪除後重裝回歸，不得要求重新配對或手動備份。

## 必記證據

- incident／drill ID、commit、build、schema、source／target region。
- recovery point、三類 artifact identity、實際資料缺口。
- 各階段開始／完成時間與實測 RPO／RTO。
- counts、checksum、reference、RLS、tombstone 與真機結果。
- mismatch、人工介入、成本、暫時環境清理結果與後續修正。

任一 artifact 缺失、checksum mismatch、RLS 越權、刪除復活、引用斷裂、靜默遺失／重複／錯序或重新配對需求均為 `FAIL`。因權限、裝置、供應商或環境無法執行為 `BLOCKED`；兩者都阻擋相關 release gate。
