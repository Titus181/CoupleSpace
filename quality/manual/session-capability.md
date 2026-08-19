# SESSION-CAPABILITY-PREFLIGHT／SESSION-001：Supabase Auth session capability

本文件保存 W13 Auth capability 的版本化證據與已退役 gate。依 [PD-044](../../docs/decisions/product-decisions.md#pd-044mvp-移除-session-inventory-與遠端撤銷只保留目前裝置登出)，iPhone MVP 只提供目前裝置的 `.local` 登出；不顯示 session／裝置 inventory，也不提供 `.others`、`.global` 或指定 session 的遠端撤銷。現行真機關閉流程改由 [W13-INTEGRATION-001](w13-integration.md) 驗證同帳號多裝置、local logout 隔離與重新登入恢復。

## 狀態

| ID | 狀態 | 發布語意 |
| --- | --- | --- |
| `SESSION-CAPABILITY-PREFLIGHT` | **PASS（歷史 API／Simulator evidence）** | 只證明 pinned SDK 的 scope／claim surface、沒有可信 inventory／target API，以及 probe 不讀私密內容；不支持 shipping `.others`。 |
| `SESSION-001` | **RETIRED；歷史結果 FAIL** | 原 PD-043 all-others 真機 gate。正式候選固定填 `NOT_APPLICABLE (REMOVED)`，並在備註引用本文件的歷史 FAIL；不得填 PASS。 |

## 目前產品不變量

- 同一 Supabase 帳號可以同時登入多台裝置；各裝置讀寫同一份受 RLS 保護的 server SSOT。
- 每台只登出自己的目前 session；A 的 `.local` 登出不應使同帳號 B 登出。
- 登出的裝置重新以同一帳號登入後，須恢復既有 relationship、共同歷史、約定、未讀狀態與本人個人封存，不要求重新配對。
- App Lock、APNs routing、本機提醒、cache、解除配對、資料刪除與 Apple 身分都不是 Auth session inventory 或遠端撤銷。
- `push_devices`、APNs token、Apple ID、裝置名稱、本機 install ID 或 user 自報名稱不得作為 session identity。
- 不修改 JWT expiry、rotation、reuse detection、single-session 或 production Auth policy 來縮短測試；縮短 expiry 不會建立可驗證的 revoke result。

## Deterministic preflight

在 repo root 執行：

```sh
quality/scripts/verify-session-capability.sh
```

此 script 只檢查 `supabase-swift 2.54.1` 的 source／App mapping，不連線 remote project，也不讀 project URL、publishable key、JWT、refresh token 或 raw `session_id`。目前可保留的結論只有：

- SDK 有 `local`／`global`／`others` 三種 scope；正式產品只採 `.local`。
- SDK／Admin public surface 沒有 list-sessions 或 target-session revoke API。
- `session_id` claim 在 pinned Swift 型別為 optional，且歷史 runtime JWT 曾觀察到不存在。
- Auth session 不能可靠映射為實體裝置；SDK 升級或 API surface 改變時須更新 capability record，不得自動恢復舊 UI。

## 2026-08-19 三 Simulator 歷史 preflight

這段是切片 7 已完成的隔離 client 證據，不需為 PD-044 重跑，也不能取代真機或支持正式 `.others`：

- iPhone 17 Pro Simulator A 與 iPhone 17 Pro Max Simulator B 以同一測試 user `S` 登入；iPhone 17 Simulator C 以 relationship 另一位 owner `P` 登入。三台 JWT 均沒有 optional `session_id`，因此 A／B 只是流程角色，不是可列出或指定的 session identity。
- 撤銷前 remote-only query 都讀到 active relationship 指紋 `1971C4CFD7A1`、members `2`、`shared_items` count `1`；A／B 的 `S` archive 為 `9FF517E636D8`，C 的 `P` archive 為 `48EA519E7187`，兩份 archive 都指向 `30BE04486C70` 且 item count `4`。所有值均為單向指紋或 count。
- A 送出 `.others` 後仍可 refresh／remote read，C 不受影響。B 的舊 JWT 曾在顯示 `exp` 2:28 PM 時於 1:32 PM 成功 remote read；B 未人工 refresh，於 2:26 PM 自動回到 Apple 登入，重開未恢復，重新驗證後 refresh／remote read 正常。
- 最終 A／B／C 的 relationship、shared count 與兩份 owner archive 均未改變，沒有 unpair、closing、archive delete、內容清空或重新配對。此結果只記為 `SESSION-CAPABILITY-PREFLIGHT` PASS；精確 refresh endpoint 未保存，不能推論 access JWT 提前失效或 all-others 真機可靠性。

## 2026-08-19 兩支真實 iPhone：SESSION-001 FAIL

依使用者完成的真機步驟，保留以下最小證據：

1. A、B 各自建立 baseline：**正確**。
2. A 送出 `.others` 後，A 不受影響：**正確**。
3. B 在既有 JWT 窗口執行受保護讀取：**成功**；當時 Access JWT expiry 仍是基線截圖所示的 **9:29 PM**。
4. B 手動觸發 refresh：**成功**；Access JWT expiry 更新為 **9:44 PM**，Auth session 仍存在，受保護資料基線未改變。

第 4 項證明 B 取得 refresh response，不是單純沿用尚未到期的 access JWT。因此原 PD-043 all-others 契約判定為 **FAIL**。以下欄位未由本輪提供，全部記為 `未記錄`，不得補猜：

- A `.others` request／completion 精確時間、HTTP status、request ID。
- B manual refresh start／completion 精確時間與 HTTP status。
- Auth audit log 的 `logout`／`token_revoked`／`token_refreshed`。
- A／B 可驗證的 raw 或 hashed `session_id`、是否為不同 server session family。
- App build、iOS 版本與 test-project alias。

這份 FAIL 證據只證明目前 App／project 組合不足以安全交付遠端撤銷；它不宣稱 Supabase `.others` 在所有情境永久無效，也不授權保存 token 或擴大調查到 production。

## Release record 寫法

- `SESSION-CAPABILITY-PREFLIGHT`：可引用既有 PASS；若 pinned SDK 或 Auth mapping 改變才重跑。
- `SESSION-001`：結果填 `NOT_APPLICABLE (REMOVED)`；備註填「PD-044 已移除正式 inventory／remote revoke；2026-08-19 歷史真機結果 FAIL，B manual refresh 後 expiry 9:44 PM」。
- `SESSION-001` 不再是 blocking gate；不得刪除 stable ID、改寫歷史 FAIL 或以 `NOT_APPLICABLE` 掩蓋仍存在的正式遠端撤銷入口。
- `W13-INTEGRATION-001` 已由同一最終候選的兩支真實 iPhone 通過 local logout／multi-device recovery、LOCK、PUSH、activity-badge、reminder、lifecycle、W8–W11 與適用自動化；G12／W13 已完成。這不改寫 `SESSION-001` 的歷史 FAIL 或候選版 `NOT_APPLICABLE (REMOVED)`。

驗證紀錄不得包含 access JWT、refresh token、raw `session_id`、Apple identifier、APNs token、project URL／key 或私人內容正文。
