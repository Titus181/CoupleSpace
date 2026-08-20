---
status: active
last_updated: 2026-08-20
---

# CoupleSpace 測試目錄

本表以行為風險為單位，不逐列複製每個 XCTest 或 pgTAP case。實際 case 名稱以連結的測試檔為準；數量會隨功能增加，不能把歷史數字當成目前通過證據。

## 自動化測試

| ID | 範圍 | 主要防範失敗 | 層級 | 實際位置 | 必要 gate |
| --- | --- | --- | --- | --- | --- |
| CFG-001 | W1–W2 環境與啟動 | 錯誤 runtime／Supabase 設定、測試參數污染正式啟動 | Unit／UI | `CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceTests/CoupleSpaceTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITestsLaunchTests.swift` | A、B、D |
| NAV-001 | W2 三分頁 | 預設頁面或「今天／對話／我們」順序退化 | Unit／UI | `CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITests.swift` | A、B、D |
| AUTH-001 | W1／W3 session | 過期 session 被視為登入、取消／失敗／登出狀態錯判 | Unit | `CoupleSpaceTests/CoupleSpaceTests.swift`、`CoupleSpaceTests/AppSkeletonTests.swift` | A、B、D |
| AUTH-002 | W3 Apple 登入 | 離線仍開啟 Apple sheet、nonce 或同帳號恢復錯誤 | Unit＋真機 | `CoupleSpaceTests/CoupleSpaceTests.swift`、`CoupleSpaceTests/AppSkeletonTests.swift`、`manual/two-iphone.md` | A、B、D |
| PAIR-001 | W1／W4 配對授權 | 第三人存取、重複 active relationship、無效邀請接受 | pgTAP／Unit | `supabase/tests/database/pairing_invitation.test.sql`、`pairing_decline.test.sql`、`pairing_cancel.test.sql`、`CoupleSpaceTests/AppSkeletonTests.swift` | A、B、D |
| PAIR-002 | W4 配對恢復 | 同時邀請、拒絕／失效後無法重試、錯誤取消關係 | pgTAP／UI＋真機 | 同上、`CoupleSpaceUITests/CoupleSpaceUITests.swift`、`manual/two-iphone.md` | A、B、D |
| PAIR-003 | G4A 短配對碼 | UUID 截短、短碼碰撞、舊 token 失效、正規化誤判、暴力猜測、輪替後舊碼仍可用或短碼建立錯誤 membership | pgTAP／Unit／UI＋真機 | `pairing_short_codes.test.sql`、`CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITests.swift`、`manual/two-iphone.md` | A、B、D |
| RLS-001 | W1–W9 私密資料邊界 | 非 relationship member 讀寫共同或個人資料 | pgTAP | `supabase/tests/database/*.test.sql` | A、B、D |
| SYNC-001 | W1 Realtime／排序 | 重讀未經 RLS、server timestamp 排序不穩定 | pgTAP／Unit＋真機 | `shared_items_realtime.test.sql`、`CoupleSpaceTests/CoupleSpaceTests.swift`、`manual/two-iphone.md` | A、B、D |
| OUTBOX-001 | W1 訊息／marker／照片 | 離線內容遺失、重複、錯序或錯 relationship 送出 | Unit＋真機 | `CoupleSpaceTests/CoupleSpaceTests.swift`、`manual/weak-network.md` | A、B、D |
| PHOTO-001 | W1 照片處理 | 大圖方向錯誤、GPS 遺留、容量不足仍寫入 | Unit | `CoupleSpaceTests/CoupleSpaceTests.swift` | A、B、D |
| PHOTO-002 | W1 Storage／配額 | 越權 object、quota 競態、orphan 未清理 | pgTAP／Unit | `private_photo_storage.test.sql`、`photo_quota_contract.test.sql`、`photo_orphan_cleanup.test.sql`、`CoupleSpaceTests/CoupleSpaceTests.swift` | A、B、D |
| PUSH-001 | W13 泛化推播契約與隱私 | 非白名單事件、來源偽造、錯誤收件者、payload／routing metadata 洩漏私密內容、claim timeout 舊 worker 完成新 lease | pgTAP／Unit／Function | `private_push_boundary.test.sql`、`push_delivery_claim.test.sql`、`CoupleSpaceTests/CoupleSpaceTests.swift`、`supabase/functions/send-w1-push/apns.test.ts` | A、B、D |
| ARCHIVE-001 | W1 封存／匯出 | 單方越權、照片缺失、容量與 staging 清理錯誤 | pgTAP／Unit＋真機 | `relationship_archive.test.sql`、`archived_photo_access.test.sql`、`CoupleSpaceTests/CoupleSpaceTests.swift`、`manual/deletion-and-unpairing.md` | A、B、D |
| DELETE-001 | W1／切片 7 刪除／解除配對 | 單方刪除影響另一方、GC／雙方結果不一致、正式入口繞過待送內容、begin 成功後誤回 active、重複封存、closing／archived 未收斂，或 Release 露出 W1 低階工具 | pgTAP／Unit／UI＋真機 | `personal_archive_deletion_queue.test.sql`、`CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITests.swift`、`manual/deletion-and-unpairing.md`、`manual/two-iphone.md` | A、B、D |
| MOMENT-001 | W5 Moment 建立 | 空白／過長內容、client ID 碰撞、非 active relationship 寫入 | pgTAP／Unit／UI | `moment_vertical_slice.test.sql`、`CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITests.swift` | A、B、D |
| MOMENT-002 | W5 照片 Moment UI | 展示照片攔截 composer、時間線顯示與建立者標示錯誤 | Unit／UI＋真機 | `CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITests.swift`、`manual/two-iphone.md` | A、B、D |
| MOMENT-003 | W10 聊天收藏為 Moment | 待送訊息可被收藏、重試重複建立、文字／照片來源斷裂，或無法由 Today／我們返回正確對話訊息 | pgTAP／Unit／UI＋真機 | `message_save_as_moment.test.sql`、`CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITests.swift`、`manual/two-iphone.md` | A、B、D |
| MOMENT-004 | W14-02 Moment 軟刪除／互動移除／30 天復原 | 非建立者刪整筆、移除他人互動、刪除後任一 surface／來源入口／direct photo 仍可見、回答移除後重新上鎖或洩漏正文、29／30 天與 closing 邊界依裝置時鐘、operation retry 重複套用、跨裝置或重啟後舊 cache 復活 | pgTAP／Unit／UI＋雙隔離 Simulator | `moment_deletion_lifecycle.test.sql`、`CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITests.swift` | A、B；雙 Simulator server／Realtime gate 須先部署 migrations 041–043；真機集中於 W14 最終整合切片 |
| TIMELINE-001 | W12 共同時間線 | Moment 未按裝置 calendar 穩定分組、同月順序錯誤、月份／日期快速跳轉未定位目前已載入內容、同日未定位最新 Moment，或內容類型分類錯誤／空結果無法返回全部 | Unit／UI＋真機 | `CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITests.swift`、`manual/two-iphone.md` | A、B、D |
| TIMELINE-002 | W12 Moment 長期分頁 | 相同建立時間游標遺漏／重複、載入舊頁後 Realtime 首頁重讀丟失歷史、頁面合併重複，或無更多內容仍持續載入 | Unit／UI＋真機 | `CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITests.swift`、`manual/two-iphone.md` | A、B、D |
| PHOTO-BROWSE-001 | W12 共同照片 | 非照片 Moment 混入、月份／照片方向顛倒、首次未定位最新內容、不可見照片被整頁下載、可見照片重複下載、詳情缺少建立者／日期，或無來源仍顯示返回動作／有來源卻返回錯誤對話 | Unit／UI＋真機 | `CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITests.swift`、`manual/two-iphone.md` | A、B、D |
| REVIEW-001 | W12 規則式每週回顧 | 本地七日邊界錯誤、納入未來或七日前內容、排序／類型計數錯誤、載入舊頁後摘要不更新、零筆狀態造成補進度壓力，或產生未核准的評分／比較／第二份摘要資料 | Unit／UI＋真機 | `CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITests.swift`、`manual/two-iphone.md` | A、B、D |
| INTERACT-001 | W6 Moment 回應 | 非伴侶回應、重試重複、回應長度或類型繞過 | pgTAP／Unit／UI | `moment_interactions.test.sql`、`CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITests.swift` | A、B、D |
| QUESTION-001 | W6 共同問答 | 第一份答案提前洩漏、共同揭曉不一致 | pgTAP／Unit／UI＋真機 | `moment_interactions.test.sql`、`CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITests.swift`、`manual/two-iphone.md` | A、B、D |
| STATUS-001 | W7 名稱與私人稱呼 | 私人稱呼被伴侶讀取、清除與 fallback 錯誤 | pgTAP／Unit／UI＋真機 | `together_now.test.sql`、`CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITests.swift`、`manual/two-iphone.md` | A、B、D |
| STATUS-002 | W7 此刻狀態 | 到期仍顯示、重建後未恢復、未選擇卻建立歷史 | pgTAP／Unit／UI＋真機 | 同上、`manual/upgrade-and-recovery.md` | A、B、D |
| CHAT-001 | W1／W8 基本文字聊天 | 內容長度、伺服器排序、第三人存取、未讀游標倒退或外洩；停留「今天／我們」、App Lock、background 或約定討論時誤把 main 文字／照片標為已讀；舊 read 或較晚回來的 badge response 覆蓋新未讀 | pgTAP／Unit／UI＋真機 | `text_message_contract.test.sql`、`basic_text_chat.test.sql`、`relationship_interaction_unread.test.sql`、migration `202608190039_bound_relationship_read_cursor.sql`、`CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITests.swift`、`manual/two-iphone.md`、`manual/w13-integration.md` | A、B、D |
| CHAT-002 | W9 可靠文字傳送 | 離線輸入靜默消失、待送／最近同步內容跨啟動遺失、錯 relationship、重複、錯序、無限重試或失敗狀態不可操作 | Unit／UI＋真機 | `CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITests.swift`、`manual/weak-network.md` | A、B、D |
| CHAT-003 | W10 聊天照片／混合 FIFO | 照片繞過既有私有 Storage／quota、離線檔案跨啟動遺失，或 text→photo→text 重送後漏送、重複、錯序 | pgTAP／Unit／UI＋真機 | `chat_photo_unread.test.sql`、`private_photo_storage.test.sql`、`photo_quota_contract.test.sql`、`CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITests.swift`、`manual/weak-network.md`、`manual/two-iphone.md` | A、B、D |
| CHAT-004 | W10 訊息 Emoji 回應 | 待送／本人訊息可被回應、非伴侶越權，或常用／自訂 Emoji 的 set／replace／remove 造成重複及兩台不同步 | pgTAP／Unit／UI＋真機 | `shared_item_reactions.test.sql`、`CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITests.swift`、`manual/two-iphone.md` | A、B、D |
| CHAT-005 | W12 聊天長期分頁 | 相同建立時間跨頁遺漏／重複、Realtime 最新頁重讀丟失舊頁、載入舊頁後捲動跳位，或 Moment 無法返回尚未載入的來源訊息 | Unit／UI＋真機 | `CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITests.swift`、`manual/two-iphone.md` | A、B、D |
| APPOINTMENT-001 | W11 基本共同約定／W12 過往入口 | 非伴侶讀寫、建立或編輯／取消 Outbox 在離線／重啟／ack 遺失後造成遺失、重複、錯序或重複刷新時間、來源訊息產生重複卡片、長按未確認便建立、取消後被較晚編輯復活、提醒晚於開始時間、未授權卻假裝已排程、編輯／取消／解除配對後留下舊提醒、通知洩漏標題／地點／註記或點擊開錯約定，或專屬討論文字／照片跨約定／主對話串線、未讀游標混用、舊約定 snapshot 的 read 跳到 scope-latest 並誤清較晚 lifecycle event、近期入口排序／未讀／取消保留錯誤或洩漏內容、過期／已取消約定未保留或排序錯誤、無法返回原討論、已取消討論仍可輸入、照片繞過私有 Storage／quota、closing 清除 scoped Outbox 造成 orphan、離線混合 FIFO 遺失／重複／錯序、重大時間變更／取消紀錄可被偽造／遺失／重複或一般文字編輯造成洗版，收藏後遺失約定來源、重複 Moment、無法返回原討論訊息，或解除配對封存遺失約定、來源、討論 scope、原建立者及重大事件關聯／洩漏另一 owner 封存 | pgTAP／Unit／UI＋真機 | `shared_appointments.test.sql`、`appointment_discussions.test.sql`、`appointment_discussion_photos.test.sql`、`recent_appointment_discussions.test.sql`、`appointment_discussion_moments.test.sql`、`appointment_archive_lifecycle.test.sql`、`appointment_interaction_read_boundary.test.sql`、migrations `202608190039_bound_relationship_read_cursor.sql`／`202608190040_bound_appointment_read_cursor.sql`、`CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITests.swift`、`manual/two-iphone.md`、`manual/weak-network.md`、`manual/deletion-and-unpairing.md`、`manual/w13-integration.md` | A、B、D |
| TODAY-001 | W9 離線 Today 顯示 | 離線冷啟動只顯示載入、Moment／照片／狀態消失、過期狀態重現、錯帳號或錯 relationship 快照外洩、重連後不校正 | Unit＋真機 | `CoupleSpaceTests/AppSkeletonTests.swift`、`manual/weak-network.md` | A、B、D |
| LOCK-001 | W13 App Lock | 未啟用時改變既有啟動、啟用／停用或偏好重啟恢復錯誤、進入 inactive／background 時未遮蔽私密畫面、驗證取消／失敗／無法驗證後顯示內容，或驗證流程改變登入／relationship／待送內容 | Unit／UI＋真機 | `CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITests.swift`、`manual/app-lock-and-background.md` | A、B、D |
| SESSION-CAPABILITY-PREFLIGHT | W13 Auth SDK／App mapping preflight | SDK revision 漂移、出現可信 inventory／target API 卻沿用舊結論、一般登出誤用 global、source probe 被當成正式遠端撤銷證據，或已移除的 `.others` UI 被恢復 | Unit／UI＋SDK source probe；隔離 Simulator 僅保留歷史 evidence | `CoupleSpaceTests/AppSkeletonTests.swift`、`CoupleSpaceUITests/CoupleSpaceUITests.swift`、`quality/scripts/verify-session-capability.sh`、`manual/session-capability.md`、`docs/architecture/02-w13-auth-session-capability.md` | A、B |
| SESSION-001 | **RETIRED**：原 W13 all-others revoke | Stable ID 不得刪除；2026-08-19 真機 FAIL 不得改寫成 PASS，正式候選只有在 remote revoke UI／runtime 確實移除時才能記 `NOT_APPLICABLE (REMOVED)` | 歷史 evidence only；不再是 blocking gate | `manual/session-capability.md`、`docs/architecture/02-w13-auth-session-capability.md`、PD-044 | — |
| W13-INTEGRATION-001 | **PASS（2026-08-20）**：G12 推播與裝置隱私整合關閉 | 同帳號多裝置 server SSOT 不一致、`.local` 登出誤傷另一台、重開恢復已登出狀態、重新登入要求配對或遺失資料、Auth 與 App Lock／APNs／未讀 badge／提醒／解除配對／資料生命週期混用、stop／logout／account switch／closing 後舊 async refresh 復活 cache／observer／reminder，或單點 PASS 掩蓋 W8–W11 回歸 | Full automated suite＋兩支真實 iPhone | `CoupleSpaceTests/CoupleSpaceTests.swift`、`CoupleSpaceTests/AppSkeletonTests.swift`、`manual/w13-integration.md`、`manual/app-lock-and-background.md`、`manual/push-privacy.md`、`manual/deletion-and-unpairing.md`、`manual/w8-w11-regression.md` | B、D |
| DR-001 | G15／G17 雲端災難復原 | 備份存在但無法還原、Database／Storage 不一致、刪除復活、RLS／Auth／設定缺失、雙主分叉、manifest 遭竄改或切換後要求重新配對 | Integration＋restore drill＋真機 | `manual/disaster-recovery.md`、`manual/upgrade-and-recovery.md`、`docs/architecture/01-disaster-recovery.md` | C、D |
| EVAL-001 | Agent 行為 | 未讀文件、越權遠端寫入、跳過測試或洩漏私人資料 | Agent Eval／Harness | `evals/README.md`、`.harness/` | B、D |

Gate A／B／D 定義見 [版本發布閘門](release-gates.md)。`CHAT-001` 只代表 W8 基本聊天；W9 的正式持久 Outbox、離線重送、可靠重試與傳送狀態由 `CHAT-002` 獨立關閉。`CHAT-002`、`TODAY-001` 與兩支真實 iPhone 的 `NETWORK-001` 已於 2026-08-13 通過，G8／W9 已完成。`CHAT-003`、`CHAT-004`、`MOMENT-003` 的本機自動化、Dev migrations 020–022 與兩支真實 iPhone 核心流程已於 2026-08-13 通過；該輪未執行近 quota 拒絕／orphan 與上傳成功但 ack 遺失故障注入，所以歷史結果只屬部分完成。2026-08-20 同一最終 W13 候選已依整合清單重跑 W9／W10／W11 active regression，使用者回報全部正常；本輪 W13 引用範圍記為 PASS，但兩個 W10 故障注入的逐項 artifact／metadata 為 `未記錄`，不能用本句回溯改寫 2026-08-13 的部分結果或獨立宣稱完整 TestFlight Gate D。`APPOINTMENT-001` 的 migrations 023–031、27 份 pgTAP／441 項、131 個串行 iPhone unit tests、focused UI／archive audit、linked schema lint，以及四輪兩支真實 iPhone 的核心、弱網、提醒與 owner-only 封存驗收已於 2026-08-17 通過；G10／W11 已完成。

`PAIR-003` 的 migration 032、本機空資料庫重建、28 份 pgTAP／460 項、local schema lint、163 個 iPhone 測試定義／166 次 executions、5 個 APNs tests、Harness v0.2.1 與 diff hygiene 已通過，0 failure、0 skip；linked migration 032 已於 2026-08-17 部署，遠端歷史一致且 linked schema lint 無錯誤。兩支真實 iPhone 已完成五輪短碼接受、格式正規化、完整分享文字、拒絕／取消／輪替、同時邀請、弱網／重啟、舊碼失效、十分鐘限流視窗與受控過期後重建；G4A 已完成。

`LOCK-001` 的 App Lock lifecycle、取消／失敗／無法驗證遮蔽、啟用／停用、偏好恢復與未啟用啟動已由 unit／UI regression 覆蓋；Simulator build、Harness 與 diff hygiene 通過。2026-08-18 已由人類在真實 iPhone 確認 Face ID／裝置密碼、冷啟動、背景返回、App switcher snapshot、鎖屏檢查，以及 session／relationship／Outbox 不變；未來完整測試仍須重跑 `manual/app-lock-and-background.md`。

2026-08-20 Slice 8 最後行為變更後的本機證據：focused unit 191／191、約定討論 focused UI 1／1；最終 `quality/scripts/run-full-automated-suite.sh --reset-local-database` exit 0，包含 migrations 001–040 clean replay、31 files／533 pgTAP、local schema lint（僅 migration 034 既有 unused `recipient_id` warning）、APNs 7／7、完整 iPhone 236 個測試定義／239 次 executions（0 failure、0 skip）、session scope guard、Harness v0.2.1 與 diff hygiene。完整 artifact 為 `/tmp/CoupleSpace-release-evidence.l8E2mW/CoupleSpace.xcresult`。linked test target `CoupleSpace-W1-Dev` 已只部署原先 pending 的 migration 040，local／remote history 同為 001–040，second dry-run up to date，linked lint exit 0（僅 migration 034 既有 warning），remote schema／ACL／anonymous authorization smoke 均 PASS。三台 Simulator 已使用同一 hash prefix `b05d650a` 候選保留 production Auth／active relationship；5C 文字 preflight 在「今天」與「我們」確認未讀至少維持 10 秒及背景／前景保留，真正開 main conversation 後才清 0，同帳號另一台同步清 0。artifacts：`/private/tmp/CoupleSpace-w13-prod-hidden-today.xcresult`、`/private/tmp/CoupleSpace-w13-prod-hidden-us.xcresult`、`/private/tmp/CoupleSpace-w13-prod-open-clear-2.xcresult`、`/private/tmp/CoupleSpace-w13-prod-same-account-clear.xcresult`。其後同一最終候選已由兩支真實 iPhone 通過同帳號 local logout、切回兩位 relationship owner、LOCK／PUSH／5C／W8、約定／討論／提醒、W9／W10／W11 active regression 與 lifecycle 六段整合流程；`W13-INTEGRATION-001` 為 **PASS**，G12／W13 已完成。真機型號、iOS 與 APNs environment 均為 `未記錄`；不因此宣稱 TestFlight Gate D、DR、UPGRADE 或 production APNs 完成。

## 目前必須保留的人工證據

| ID | 風險 | 清單 |
| --- | --- | --- |
| DEVICE-001 | 雙帳號、跨裝置同步與恢復 | `manual/two-iphone.md` |
| NETWORK-001 | 弱網、離線、重連、去重與順序 | `manual/weak-network.md` |
| PUSH-002 | 真實 APNs、背景／終止／鎖定畫面隱私 | `manual/push-privacy.md` |
| UPGRADE-001 | TestFlight／正式版升級、換機、重裝與資料延續 | `manual/upgrade-and-recovery.md` |
| DR-001 | Database／Storage／設定／刪除 journal 一致還原與異區冷重建 | `manual/disaster-recovery.md` |
| LIFECYCLE-001 | 匯出、刪除、解除配對與雙方一致性 | `manual/deletion-and-unpairing.md` |
| LOCK-001 | App Lock、背景切換與重新啟動 | `manual/app-lock-and-background.md` |
| W13-INTEGRATION-001 | W13 同帳號多裝置／local logout／恢復、App Lock／push／badge／reminder／lifecycle 與 W8–W11 整合 | `manual/w13-integration.md` |

`SESSION-CAPABILITY-PREFLIGHT` 是版本化 SDK／App mapping 檢查，不是目前人工 gate；三 Simulator 只保留歷史 API／no-inventory evidence，只有 pinned SDK 或 Auth mapping 改變才重跑。

`SESSION-001` 是 retired stable ID，不在「目前必須保留的人工證據」內；歷史真機結果為 FAIL，候選版依 PD-044 記 `NOT_APPLICABLE (REMOVED)`，詳見 `manual/session-capability.md`。

W8–W11 的跨 catalog 完整改版順序見 `manual/w8-w11-regression.md`；它只編排既有責任，不建立新的 PASS 狀態。

## 已知未關閉範圍

- Production／TestFlight push 不能由 development sandbox 證據取代。
- 大型真機封存、實際低磁碟與中斷續傳尚需對應 release gate。
- `DR-001` 尚未完成；Database／Storage／設定／刪除 journal restore drill 必須使用同一 recovery point，並實測 signed manifest、異區冷重建、RLS、checksum 與清空本機狀態真機恢復，不能用單純「備份已開啟」代替。
- W9 的本機自動化不得取代兩支真實 iPhone 的離線、force-quit、重連、去重與 FIFO 證據。
- W10 的本機自動化不得取代兩支真實 iPhone 對 mixed FIFO、reaction 即時同步、來源跳轉與私有照片讀取的證據。
- `SESSION-CAPABILITY-PREFLIGHT`：SDK source probe 確認 pinned 2.54.1 只有 `local`／`global`／`others` scope，沒有可信 inventory／target API，runtime JWT 的 optional `session_id` 曾缺失；三 Simulator 的 remote-only probe 不讀正文／raw ID／本機 cache，保留為 API 與資料不變的歷史 PASS。它不支持 shipping `.others`。2026-08-19 的真機 `SESSION-001` 中，A 送出 `.others` 後 B manual refresh 成功、expiry 更新為 9:44 PM，Auth／資料仍存在，故原契約結果為 **FAIL**；其後 PD-044 移除正式 inventory／remote revoke。`SESSION-001` 已退役，不再是 blocking gate，候選版只可記 `NOT_APPLICABLE (REMOVED)`，不能改寫歷史結果。
