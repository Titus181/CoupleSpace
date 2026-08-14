---
title: 第一版開發路線圖
status: active
last_updated: 2026-08-14
---

# 第一版開發路線圖

## 文件目的

本文件將 [iPhone 首版範圍](../product/04-iphone-mvp-scope.md) 轉換為依時間與依賴排序、可個別驗收的開發目標。第一版在此定義為：

> 可先由熟人圈完成短期 TestFlight 煙霧測試，再安全接續至 App Store 正式上市的 iPhone MVP。

本路線圖是目前的規劃基準，不代表尚待確認的技術方案已成為產品決策。若產品範圍或技術風險改變，應更新本文件並在 [產品決策紀錄](../decisions/product-decisions.md) 保留決策脈絡。

## 時程假設

- **起始日期：** 2026-08-04。
- **人力假設：** 一位全職開發者，產品與設計決策能及時提供。
- **封閉測試版：** 16 週，預計 2026-11-23 開始 TestFlight。
- **封閉驗證：** TestFlight 候選版完成後，以 3–7 天、最低開發者加一位朋友的兩帳號／兩真機煙霧測試為基準；可再加入熟人圈 1–3 對情侶驗證無口頭引導流程。
- **上市驗證：** 通過 release gate 後進入 App Store 正式供應，執行一個月繁中上市活動，再依伴侶對行為、品質、成本與回饋進行第一輪版本決策；實際日期取決於 gate 與 App Review，不作固定交付保證。
- **兼職換算：** 若每週投入約 20 小時，整體時程初估需延長至 26–30 週。
- **重新估算點：** W1 技術風險驗證完成後，依實測結果調整時程；上述日期不是保證交付日。

## 排程原則

- 先完成會影響整體資料模型的技術決策，再開始大量功能實作。
- 以可在兩支真實 iPhone 上驗收的垂直流程為單位，不先完成所有畫面再補同步能力。
- 優先完成 `配對 → Moment／共同約定 → 雙向互動／約定討論 → 對話 → 收藏 → 共同時間線` 的核心循環。
- 每個目標必須有明確完成條件；畫面存在但資料無法可靠跨裝置同步，不算完成。
- iPhone 核心流程完成前，不投入 Watch、macOS、visionOS、Widget、訂閱或 AI 功能。

## 開發目標與時間順序

| 時間 | 開發目標 | 完成條件 |
|---|---|---|
| W1，8/4–8/11 | **G1 技術決策與風險驗證（已完成）** | 兩支真實 iPhone、兩個 Apple 身分已完成 development 登入、配對、雙向資料、弱網／跨啟動 Outbox 與雙向推播實測；TD-001 已決定 Supabase 架構及共同資料的所有權、解除配對、刪除與匯出規則 |
| W2，8/10–8/16 | **G2 iPhone App 基礎骨架（已完成）** | 移除預設範例資料模型；建立「今天／對話／我們」三分頁、環境設定、領域模型與測試框架；iPhone target 可穩定建置與執行 |
| W3，8/17–8/23 | **G3 帳號與使用者身分（已完成）** | 使用者可登入、登出，重新啟動後可恢復登入；取消與失敗狀態明確；不建立重複帳號 |
| W4，8/24–8/30 | **G4 邀請與一對一配對（已完成）** | A 可邀請 B；B 接受後雙方看到同一段伴侶關係；一人只能有一個有效伴侶；邀請可拒絕、失效與重試 |
| W5，8/31–9/6 | **G5 第一個 Moment 垂直切片（已完成）** | 可建立心情、短句或照片 Moment；另一支手機能同步看到；Moment 自動進入共同時間線 |
| W6，9/7–9/13 | **G6 Moment 雙向互動（已完成）** | 支援 Emoji、短文字回應及固定題庫版「我們的一題」；雙方互動後形成完整 Moment |
| W7，9/14–9/20 | **G6A 名稱與此刻狀態垂直切片（已完成）** | 本人可設定伴侶可見顯示名稱及 owner-only 伴侶稱呼；雙方可跨裝置看到本人主動設定、具期限的固定或自訂狀態，過期結果一致；同一帳號重新登入後可恢復名稱、私人稱呼與尚未過期狀態；只有明確選擇才同時建立 Moment，不提供在線、最後上線、觀看紀錄或完整動態牆 |
| W8，9/21–9/27 | **G7 基本文字聊天（已完成）** | 一對一文字訊息可跨裝置同步；顯示訊息時間與未讀數；不顯示已讀狀態 |
| W9，9/28–10/4 | **G8 可靠傳送機制（已完成）** | 訊息具有傳送中、成功、失敗與重試狀態；離線重連後不遺失、不重複，順序可預期 |
| W10，10/5–10/11 | **G9 聊天首版完整範圍** | 支援聊天照片、Emoji 回應；長按訊息可收藏為 Moment，並能從 Moment 回到相關對話 |
| W11，10/12–10/18 | **G10 基本共同約定與專屬討論** | 可由長按訊息確認、輸入列「＋」、今天或共同日程建立同一筆基本共同約定；主對話卡片、近期列表、月曆、詳情與通知同步同一狀態且重試不重複；雙方可進入同一個專屬討論，活動後可挑選內容建立相關 Moment，且不建立第二套訊息系統 |
| W12，10/19–10/25 | **G11「我們」與基本回顧** | 共同時間線不只依序無限堆疊，須按月份分組並支援日期／月份快速跳轉及最小內容類型篩選；聊天與 Moment 的長期歷史使用穩定游標分頁，媒體依可見範圍漸進載入；使用正確顯示名稱／私人稱呼標示參與者與建立時間；可查看過往約定並返回相關討論；基本每週回顧採規則式彙整，不使用 AI |
| W13，10/26–11/1 | **G12 推播與裝置隱私** | 一般對話、約定討論與基本提醒送達正確使用者；鎖定畫面預設不顯示私密內容；Face ID／裝置密碼 App Lock 可用；可查看目前登入裝置並撤銷遺失或不再使用的其他裝置 session，且不影響 relationship 或既有內容 |
| W14，11/2–11/8 | **G13 資料生命週期** | 解除配對、帳號刪除、目前狀態、名稱／私人稱呼、共同約定與討論、共同資料處理及基本匯出均依核准規則運作；雙方結果一致且可稽核 |
| W15，11/9–11/15 | **G14 分析、監控與端到端測試** | 能以伴侶對追蹤配對、首次互動、Moment、共同約定、討論、聊天與回訪；不記錄私密訊息、狀態正文或私人稱呼；核心流程具自動化測試 |
| W16，11/16–11/22 | **G15 TestFlight 候選版** | 兩個新帳號能完成首版十一項完成條件；通過真機、弱網、離線、狀態過期、通知、約定提醒、清空本機狀態換機／重裝、舊裝置撤銷、刪除與隱私測試；Database 與 Storage 已完成一致版本 restore drill；沒有阻斷級問題 |
| G15 後 3–7 天 | **G16 熟人圈 TestFlight 煙霧測試** | 開發者與一位朋友以兩個帳號、兩支真實 iPhone 完成名稱／私人稱呼、目前狀態與過期、選擇性 Moment、其餘核心流程、弱網／離線、推播隱私、版本更新、資料恢復、匯出、刪除與解除配對；視需要加入 1–3 對熟人情侶無口頭引導驗證；沒有阻斷級問題 |
| G16 通過後 | **G17 正式上架與首月驗證** | TestFlight 使用者的顯示名稱、本人私人稱呼、尚未過期狀態及完整關係資料可無刪檔接續至 App Store 正式版；執行一個月繁中上市活動與 30 天 Plus Launch Pass，追蹤雙人啟用、雙向互動、W1／W4 留存、品質、成本及自願訂閱 |
| 上市活動滿一個月 | **G18 第一版決策點** | 依伴侶對行為、使用者回饋、可靠性、客服與成本證據，決定修正核心循環、擴大投放或安排下一版；此時重新評估 Widget、進階回顧與訂閱優先順序 |

### G10 進行中證據（2026-08-14）

- 第一個共同約定垂直切片已建立 relationship-scoped `shared_appointments` 唯一資料來源，包含穩定 client UUID、標題、開始時間、選填地點／短註記、一次提醒、來源訊息、scheduled／cancelled 狀態與 Realtime 變更提示；RLS 只允許目前伴侶讀取，建立、編輯與取消只能經過 server 驗證 RPC。
- 同一 client UUID 重試不重複；同一來源訊息即使由兩支裝置使用不同 client UUID 建立，也只保留並回傳同一筆約定。取消保留原資料與來源脈絡，且不可由一般編輯重新變回 scheduled。
- 「今天」已接入最小建立表單與下一筆約定卡片，維持 Moment 建立入口在前、共同約定為次要協調區塊；本段本機證據不得取代兩支真機、弱網與通知驗證。
- 建立流程現已在遠端 RPC 前寫入 user＋relationship scoped 的持久 Appointment Outbox；失敗項目以待同步／可重試狀態保留，前景及網路恢復沿用 stable client UUID 重送，包含遠端成功但本機 acknowledgement 遺失時不重複建立。聊天室輸入列 `＋` 與長按已同步文字訊息會開啟同一表單；長按只預填原文並保留來源 ID，不分析日期或自動建立。
- 「我們」現可進入共同日程，分開顯示近期與過往／已取消約定，並可直接建立或開啟系統 graphical 基本月曆；月曆依使用者本地日期顯示當日 scheduled／cancelled 約定，並可進入同一筆詳情。已同步且仍 scheduled 的項目可編輯或取消，取消後保留原內容且不可由編輯復活。主對話以 appointment UUID 將約定卡片、一般訊息與重大狀態紀錄共同排序；已同步卡片可開啟同一筆詳情，編輯、取消及 Realtime 重讀會就地更新原卡片，不建立平行資料。編輯與取消現會先寫入 user＋relationship scoped 的持久 operation Outbox，再立即套用預期狀態並以單一 FIFO 傳送；離線、App 重啟或遠端成功但本機 acknowledgement 遺失時會沿用同一 operation UUID 恢復，取消後拒絕排入較晚的編輯。伺服器以 relationship-scoped operation receipt 真正辨認重送；舊 ack 即使晚於伴侶的新編輯抵達，也只能回讀目前狀態而不再次改寫。edit／cancel RPC 在同一 transaction 鎖住 relationship 與 appointment，避免解除配對交錯寫入；已取消、不存在或關係停止寫入等 terminal 結果會移出 queue 並繼續後續 FIFO，只有暫時性錯誤保留重試。開始時間變更與取消現由同一 transaction 建立不可由 client 偽造的永久紀錄，stable operation UUID 重送不重複；標題、地點、備註及提醒調整不產生紀錄。兩種重大紀錄會依 server time 顯示於主對話與正確的約定討論，並讓該討論成為近期活動，但不虛增未讀訊息。
- 每筆已同步約定現可由詳情進入 appointment UUID scoped 的專屬討論；資料仍寫入既有 `shared_items`、沿用相同訊息／Emoji／Realtime 管線，不建立第二套訊息資料。此切片提供文字、照片、Emoji、server timestamp、獨立未讀游標，以及與主對話／其他約定隔離的持久混合 FIFO Outbox 與 snapshot；stable message UUID 重試不重複或跨 scope 移動。照片復用 W1 私有 bucket、relationship-wide quota、W10 壓縮／預覽／反應與 lifecycle reconciliation，不建立第二套媒體管線。已取消約定仍可閱讀原討論但不顯示輸入列，server 也拒絕新文字或照片。「對話」頂部現提供最多五筆依訊息／照片／Reaction／重大狀態紀錄最新活動排序的近期約定討論入口，只顯示約定標題、活動時間與目前使用者未讀數，不回傳內容摘要；點擊會直接進入同一個專屬討論，分頁 badge 合併主對話與約定討論未讀。已同步的討論文字與照片現可沿用 W10 收藏 RPC 建立 Moment，Moment 持久保留 appointment UUID；收藏成功後會主動刷新共同時間線，收藏標記可由遠端或本機快照恢復。從「今天／我們」返回來源時，主聊天與約定討論 route 互斥，且同一約定的不同 message UUID 會重新定位並標示正確訊息。每台 iPhone 現會在使用者明確允許後，為已同步且仍 scheduled 的未來約定排一個本機提醒；固定 appointment UUID 會在重啟、改期與 Realtime 重讀時覆寫同一請求，取消、登出或解除配對會移除舊請求。鎖定畫面只顯示通用文字，不含標題、地點與註記；點擊會先刷新再開啟同一 appointment UUID 詳情。migrations 001–030 已由空本機資料庫套用，26 份 pgTAP 共 416 項與最新串行 iPhone unit 128 項全數通過；本提醒切片的測試建置、4 項 focused runtime cases 與 `git diff --check` 也取得 exit 0。完整約定／討論／重大紀錄解除配對封存關聯仍未完成，因此 G10 繼續維持進行中。

### G4 完成證據（2026-08-11）

- 正式 App 已在 Supabase session 恢復後重新經 RLS 讀取目前 active relationship；未完成 `2/2` 配對前顯示邀請與配對流程，完成後才進入「今天／對話／我們」。不同登入身分不沿用前一位使用者的 pairing presentation state，配對前仍可登出。
- A 可建立或取回一小時邀請碼並使用系統分享表傳給 B；B 可貼上完整邀請碼接受或明確拒絕。拒絕會使原 token 不可接受，A 重試時在同一段單人成員 relationship 輪替新 token；既有 server constraint 繼續保證每位使用者只有一個 active membership。
- 成功配對後雙方可在帳號設定核對相同 relationship UUID 前 8 碼；這只是識別複驗，不是新的邀請碼或 client-side 授權來源。
- 最終 iPhone Simulator target build、PairingModel affected tests、配對 UI regression 與完整 iPhone automated suite 均以 `xcodebuild` exit 0 通過。
- 重建本機 Supabase、依序套用 migrations 001–015 後，完整 database suite 的 14 files／156 tests 全部通過，涵蓋拒絕、取消空白單人邀請、舊 token 不可接受、同一 relationship 輪替新 token，以及所有既有 RLS／資料生命週期 regression。
- migrations 014／015 已部署 Supabase 測試專案；遠端 migration list 顯示 local／remote 001–015 一致，linked `public`／`extensions` schema lint 無錯誤。
- Debug build 的帳號設定已恢復明確標示的「W1 技術驗證工具」入口，復用既有訊息、照片、配對與解除關係 spike 做真機回歸；正式三分頁不提前承載 W7–W9／W13 產品介面。帳號設定與配對前的登出確認改用標準 alert，避免錨定式浮窗。
- 兩支真機同時各自建立邀請時，會形成兩段各一人的 active relationship，雙方因一人只能有一個 active membership 而無法接受另一份邀請。migration 015 與 App 已加入「取消我的邀請」恢復路徑：只允許建立者刪除未接受、單人成員且完全沒有共同資料／照片／封存／push job 的空白邀請關係；真機已完成其中一方取消後回到未配對、拒絕另一方邀請，以及邀請者在同一 relationship 輪替新 token。
- 兩支真機另以授權的測試專案單筆 `expires_at` 調整，控制式觸發與自然逾時相同的伺服器失效判斷；App 的「檢查並重試邀請」在原 relationship 內把 token 由 `614895a0…` 輪替為 `f4221447…`，並延後一小時。這是控制式過期證據，不宣稱實際等待一小時。B 接受新 token 後，雙方均進入三分頁並在帳號設定看到相同 relationship `632fd4c5…`。G4 完成。

### G5 完成證據（2026-08-11）

- 已建立最小 Moment domain：固定心情、最長 280 字短句與單張照片；Emoji／短文字回應及「我們的一題」仍留在 W6，不提前實作。
- 「今天」提供 Moment 建立入口並顯示最新一筆；「我們」以同一個 `MomentModel` 顯示共同時間線，不另建第二份本機時間線資料。
- migration 016 新增 relationship-scoped `moments`、伺服器驗證且可依 stable client UUID 冪等重試的建立 RPC、current-member RLS、active relationship 寫入限制、私有 Moment photo bucket 與 Realtime publication。照片先沿用 W1 已驗證的縮放、重新編碼及 metadata 移除處理；W8 才關閉正式持久 Outbox、離線重送與傳送狀態。
- 本機 Supabase 已由空資料庫依序套用 migrations 001–016；完整 15 files／174 pgTAP tests 與 local `extensions`／`public` schema lint 通過。新增的 18 cases 涵蓋心情／短句／照片、文字正規化與長度、同 identity 重試去重、內容碰撞、Storage owner／bytes 核對、第三人隔離及 closing 拒絕新增。
- iPhone Simulator target build 與包含 unit／UI tests 的 `build-for-testing` 通過；已安裝並以 `--ui-testing` 啟動 Simulator App，目視確認「今天」空狀態與「留下 Moment」入口。早期 runtime 嘗試曾出現 LLDB `DebuggerVersionStore.StoreError`／`no debugger version` 且沒有即時輸出；隔離 DerivedData、清除殘留 test process 並關閉平行 clone 後，確認該警告不阻止 `xctest`。完整 suite 另揭露一般 UI tests 會沿用 launch matrix 留下的橫向狀態，現於每個一般 UI case 的 `setUpWithError` 明確回到直向；launch tests 仍保留直向／橫向與明／暗四組覆蓋。
- migration 016 已部署 Supabase 測試專案；remote migration 001–016 一致，linked `extensions`／`public` schema lint 無錯誤。兩支真實 iPhone 已完成雙向心情、短句、照片同步、共同時間線順序／去重及強制結束後恢復。最終以全新 DerivedData 串行執行完整 iPhone scheme，73 個 unit tests 與 11 次 UI executions 全數通過，0 failure、0 skip，並產生完整 `.xcresult`；G5 正式完成。
- 首次雙機驗證確認同步後，同時發現最新照片的 `Image` hit-test 區域會攔截上方「留下 Moment」按鈕。修正只停用 W5 純展示照片的 hit testing，未改資料層；新增預載照片的 UI regression，Simulator 以實際照片重現修正前無反應，修正後同位置點擊可再次開啟 composer。修正版部署兩支真機後，雙方均可正常再次開啟建立介面。
- 真機共同時間線另發現 Moment 雖已保存 `creator_user_id`，畫面只顯示內容與時間，久後無法辨識由誰留下。現直接以登入 session UUID 比對既有建立者欄位，在雙方各自視角顯示「你留下的」或「對方留下的」，不新增暱稱／頭像或暴露帳號識別碼。修正版部署後，兩支真實 iPhone 已確認同一筆 Moment 在建立者端顯示「你留下的」、另一端顯示「對方留下的」，且「今天」與「我們」標示一致；建立者判斷 regression 已納入本輪 73 個 unit tests。

### G6 完成證據（2026-08-12）

- 正式 Moment domain 與卡片已加入六個固定 Emoji、最多 80 字短文字回應，以及固定四題、每份最多 280 字的「我們的一題」。一般 Moment 只由非建立者伴侶留一筆回應；題目由發起者先答，第二位回答前不顯示第一份內容，完成後雙方在同一張卡片共同揭曉。
- migration 017 新增 `moment_responses`、`moment_question_answers`、固定題庫、Question Moment 欄位、Security Definer RPC、relationship RLS 與 Realtime publication。答案揭曉由 RLS 執行，不只靠 SwiftUI 隱藏；第三人、直接 DML、自己回應自己、非 active `2/2` relationship、內容越界及 client identity 碰撞均拒絕。
- 回應、回答與題目建立的失敗重試會在內容不變時沿用 stable client UUID；正式持久 Outbox、背景傳送、長時間退避、推播與分析事件仍依後續目標處理，未提前納入 W6。
- 本機 Supabase 已由空資料庫依序套用 migrations 001–017；完整 16 files／201 pgTAP tests 與 local `extensions`／`public` schema lint 通過。
- 以全新 DerivedData 串行執行完整 iPhone scheme，76 個 unit tests、11 個一般 UI tests 及四組 launch matrix 共 91 次 test executions 全數通過，0 failure、0 skip；`.xcresult` 摘要記錄 88 個測試定義，動態 launch 參數展開後為 91 次執行。Xcode 26.5 仍輸出既有 LLDB `DebuggerVersionStore.StoreError`／`no debugger version` 警告，但 runner 完整進入 `xctest`、產生結果並以 exit 0 結束。
- migration 017 已部署 Supabase 測試專案；remote migration 001–017 一致，linked `extensions`／`public` schema lint 無錯誤，再次 dry-run 顯示無待部署 migration。
- 兩支真實 iPhone 已通過雙向 Emoji／短文字回應、第一份答案在伴侶回答前不可見、第二份回答後雙方共同揭曉、Realtime 收斂及強制結束後恢復；G6 與 M1 正式完成。

### G6A 完成證據（2026-08-12）

- `現在的我們` 已加入「今天」頂部：本人狀態卡可編輯，伴侶卡只讀；帳號設定可維護本人顯示名稱與 owner-only 私人伴侶稱呼。固定狀態、自訂 40 字短句、1 小時／4 小時／建立者當地今晚／手動清除均有 domain 規則；單純更新不建立歷史或推播，只有明確開啟「也留成 Moment」才建立獨立 Moment。
- migration 018 新增帳號層 `user_profiles`、owner-only `relationship_partner_aliases` 與每位成員單筆 `current_relationship_statuses`。名稱與狀態只能由本人 RPC 寫入；active partner 可讀顯示名稱與未過期狀態，私人稱呼、第三人及 closing relationship 均由 RLS 隔離。狀態過期使用 server time；狀態＋Moment 在同一 transaction 內完成，stable client UUID 重試不重複，後續狀態更新不改寫既有 Moment。
- 本機 Supabase 已由空資料庫依序套用 migrations 001–018；完整 17 files／232 pgTAP tests 與 local `extensions`／`public` schema lint 通過。
- W7 關閉前以全新 DerivedData 串行重跑完整 iPhone scheme：83 個 unit tests、15 個一般 UI tests及四組 launch matrix 共 102 次 test executions 全數通過，0 failure、0 skip；`.xcresult` 記錄 99 個測試定義，動態 launch 參數展開後為 102 次執行。Xcode 26.5 仍輸出既有 LLDB `DebuggerVersionStore.StoreError`／`no debugger version` 警告，但 runner 完整進入 `xctest`、產生結果並以 exit 0 結束。
- migration 018 已部署 Supabase 測試專案；remote migration 001–018 一致，再次 dry-run 顯示無待部署 migration，linked `extensions`／`public` schema lint 無錯誤。部署後 CLI 的本機 migration catalog 快取曾因 `pg-delta` 2.5 秒連線逾時輸出警告，但遠端 migration list、第二次 dry-run 與 linked lint 均直接確認 migration 已成功落地。相同 development build 已成功安裝並啟動於兩支 iOS 26.6 測試 iPhone，既有 App data 保留。
- 首輪雙機人工驗證通過名稱可見性、私人稱呼 owner-only、雙向狀態、Realtime、選擇性 Moment、狀態修改不改寫 Moment、清除與強制結束恢復。驗證同時發現既有 Moment／回應／回答仍使用固定「你／對方」文案，不會隨名稱更新；修正改為依參與者 user UUID 動態解析目前顯示名稱與私人稱呼，未設定時使用「我／伴侶」，不修改歷史資料本身。修正版安裝兩支真機後，修改本人名稱、修改私人伴侶稱呼、owner-only 差異與清空後 fallback 四項複驗均通過。帳號設定另為兩個名稱各提供獨立、立即儲存的清除按鈕，清除其中一項不改動另一項；聚焦 UI regression 完成儲存、舊歷史換名、逐項清除與 fallback 全流程，1/1 通過，最新版部署兩支真機後兩個清除操作亦完成人工確認。
- 自動化另覆蓋狀態到期後由本機排程清除，以及重新建立 model 後由遠端恢復名稱、私人稱呼與未過期狀態；`AppSkeletonTests` 22/22 通過。名稱／此刻狀態的伴侶訪談與可點擊原型由產品研究另行處理，不列入開發 roadmap，也不阻擋 G6A 工程完成。
- 兩支 iOS 26.6 真實 iPhone 先同步顯示一小時狀態，再由授權的測試專案單筆更新將仍未過期的 `expires_at` 縮短為伺服器時間後 30 秒；兩支 App 均在不重開、不手動重整下，依 Realtime 收到的新期限自行排程並於到期後回到「尚未設定」。直接把期限改到過去會使資料立即被 RLS 隱藏、無法等效驗證 Realtime 排程，因此不列為完成證據。
- 兩支真機分別以各自原 Apple 帳號逐一登出及重新登入，另一支保持登入。雙方重新登入後帳號識別碼前綴、原 relationship、本人顯示名稱、owner-only 私人伴侶稱呼與手動清除狀態均由遠端 SSOT 恢復，不需重新配對；G6A／W7 正式完成。

### G7 完成證據（2026-08-12）

- 正式「對話」分頁已由空狀態替換為基本一對一文字聊天：最多 4,000 字、本人／伴侶左右區分、每則訊息時間、送出後遠端重讀、Realtime 收斂，以及底部分頁未讀數；介面不提供已讀標記、已讀時間或伴侶觀看狀態。
- 正式 data service 直接重用 migration 008 的 `shared_items` message contract 與 `write_shared_message` stable client UUID 冪等邊界，不建立第二份聊天表。migration 019 只新增 owner-only `conversation_read_states` 與 unread／mark-read RPC；游標以伺服器 `created_at + client_id` 決定順序，只前進不倒退，伴侶與第三人不可讀取。
- 本機 Supabase 已由空資料庫依序套用 migrations 001–019；完整 18 files／251 pgTAP tests 與 local `extensions`／`public` schema lint 通過。新增 cases 涵蓋雙方未讀計數、部分／完整已讀、游標不倒退、第三人拒絕、owner-only RLS 與同帳號跨裝置 Realtime publication。
- W8 關閉前以全新 DerivedData 串行重跑完整 iPhone scheme：`.xcresult` 記錄 99 個測試定義、動態 launch matrix 展開後 102 次 executions，0 failure、0 skip；聊天與核心導覽聚焦 UI cases 亦包含在本輪成功結果。傳送中／成功／失敗的產品狀態、正式持久 Outbox、離線重連、可靠重試與順序恢復保留給 W9，未以 W8 證據提前宣稱完成。
- migration 019 已部署 Supabase 測試專案；remote migration history 顯示 local／remote 001–019 一致，第二次 linked dry-run 回報 up-to-date，linked `extensions`／`public` schema lint 無錯誤。首次 push 在明確顯示套用 019 後卡在 CLI 收尾，獨立 migration history 已確認交易完成，未重送 migration；停止該收尾程序後的 dry-run 與 lint 均正常完成。
- 首輪雙機聊天驗證通過雙向文字、Realtime、未讀數、訊息時間、無已讀標記與強制結束恢復；同時發現輸入框取得焦點後系統鍵盤遮住底部分頁，畫面沒有自然的收鍵盤方式。修正讓聊天列表支援向下拖曳及點擊訊息區收起鍵盤，不額外加入鍵盤工具列按鈕；聚焦 UI regression 覆蓋輸入中點訊息收鍵盤後切回「今天」。
- 雙機複驗已確認點擊訊息區與向下拖曳均可收起鍵盤，且底部三個分頁恢復切換；G7 基本文字聊天的資料、同步、未讀、時間、無已讀標記、恢復與鍵盤互動 gate 均通過。W7 的真機過期與重新登入 gate 已另行完成，不以 W8 證據替代；G7／W8 正式完成。
- W9 首個體感切片先處理按下傳送後約 0.5 秒才顯示訊息：改為立即加入本機訊息，短暫同步成功時不增加狀態文案，失敗保留「傳送失敗」與重試入口。現已把該流程接入 TD-002 的正式文字訊息持久 Outbox：寫入成功後才顯示、依 user＋relationship scope 保存、單一 FIFO drain、stable UUID 冪等重送，並在冷啟動／登入、回到前景與前景離線→連線時採立即、1 秒、4 秒、最多三次的有限恢復；登出或畫面結束後停止後續 drain。
- W9 affected unit tests 已覆蓋跨 store recreation、scope 隔離、FIFO、有限退避、同一 drain 期間連續訊息，以及「遠端已收件但本機 acknowledgement 失敗」後重送不重複；失敗訊息 UI regression 通過。全新 DerivedData 的完整 iPhone scheme 記錄 104 個測試定義、動態 launch matrix 展開後 107 次 executions，0 failure、0 skip；完整本機 gate 的 18 files／251 pgTAP、schema lint、5 個 APNs tests、Harness 與 diff hygiene 亦通過。此階段兩支真實 iPhone 的離線建立、force-quit、重連、順序與唯一送達尚待執行，因此當時 G8／W9 保持開發中。
- 首輪雙真機弱網驗收發現三項阻斷：FIFO 隊首失敗後尾端仍顯示傳送中；恢復網路雖能自動送出，但對方需重啟 App 才重讀；離線啟動會恢復帳號設定 modal。修正現把所有被失敗隊首阻塞的訊息一致標示為可重試，Realtime refresh 不再丟棄讀取中抵達的事件，前景／網路恢復會重建 subscription、drain 後再重讀；已登入、已配對者離線冷啟動則只以 user-scoped 唯讀 relationship snapshot 回到三分頁主畫面，顯示離線提示並重設帳號設定 sheet，寫入仍須通過遠端授權。修正版的離線啟動、三分頁與帳號設定聚焦 UI regressions 已通過；全新完整本機 gate 記錄 107 個測試定義、動態 launch matrix 展開後 110 次 executions，0 failure、0 skip，18 files／251 pgTAP、schema lint、5 個 APNs tests、Harness 與 diff hygiene 亦通過。此階段兩支真機的修正版弱網複驗尚待執行，因此當時 G8／W9 保持開發中。
- 「今天」離線冷啟動現會先顯示同一 user＋relationship 上次成功讀取的 Moment、Moment 照片、雙方稱呼與目前狀態，不再等待遠端失敗後才留下空白或載入畫面；狀態快照仍會依目前時間排除已過期內容。回到前景或前景離線→連線會平行刷新 Moment、現在的我們與聊天，並由 Supabase RLS 結果校正。快照在成功登出、遠端確認沒有 active relationship 或 relationship identity 改變時清除；本切片只提供離線唯讀顯示，不加入離線建立或修改 Moment／狀態。
- 次輪雙真機影片確認三分頁、離線提示與不恢復帳號設定已生效，但另揭露離線按傳送後輸入清空且未進 Outbox、既有聊天被誤畫成全新空白，以及 pairing／Moment／狀態串行網路等待阻塞聊天初始化。修正現把完整登入 user UUID 直接交給 user＋relationship scoped 本機聊天 store，輸入框只在 enqueue 成功後清空；最近 200 則已同步文字作為裝置顯示快照，與待送 Outbox 合併後再由遠端 RLS 校正，成功登出或遠端確認 relationship 失效／改變時清除。Pairing 先恢復唯讀快照、主畫面的三個模型平行啟動。影片情境的離線傳送 UI regression、快照容量／scope、遠端失敗仍顯示歷史及配對快照優先恢復 unit tests 已通過；2026-08-13 全新完整本機 gate 記錄 110 個測試定義、113 次 executions、0 failure、0 skip，18 files／251 pgTAP、schema lint、5 個 APNs tests、Harness 與 diff hygiene 亦通過。此階段兩支真機尚待複驗，因此當時 G8／W9 保持開發中。
- 最終雙真機複驗確認：有快照後離線強制結束並重開，`今天／對話／我們` 三分頁均保留歷史畫面；接收方 App 保持開啟時，另一支手機新增 Moment 與文字訊息會即時顯示；接收方離線期間新增的 Moment 與文字訊息，恢復網路後會自動補齊，不需重啟 App。最終 commit `6c0f4e3` 的完整 Gate B 於 2026-08-13 通過：`.xcresult` 記錄 113 個測試定義、動態 launch matrix 展開後 116 次通過，0 failure、0 skip；18 files／251 pgTAP、local schema lint、5 個 APNs tests、Harness v0.2.1 與 diff hygiene 亦通過。離線輸入、跨啟動 Outbox、FIFO、stable UUID 去重、有限重試、Realtime 重連、對話／Today 唯讀快照及 RLS 校正完成兩支真機閉環；G8／W9 正式完成。聊天照片、訊息 Emoji 回應及收藏為 Moment 仍屬 W10。
- 真機回報直式截圖在 Moment 卡片的固定 220pt `scaledToFill` 圖框中遭上下裁切；圖片顯示改為依原始長寬比自動決定高度的 `scaledToFit`，不裁切直式、橫式或方形照片。
- Moment 回應保留六個單鍵快速 Emoji，最右側新增 `+`；點擊後直接升起 App 內建的分類 Emoji 網格，點一個即送出並關閉，不再要求聚焦文字欄位或切換系統鍵盤。自訂 Emoji 沿用既有短回應同步契約；清單由 App 版本維護，新版 Unicode Emoji 需隨版本補充。
- Emoji 面板真機回報選擇後仍約等待 0.5 秒；原因是 client 先等待建立 RPC，再重抓完整 Moment 時間線，完成後才關閉面板。修正改為點擊即關閉面板並樂觀加入該 Emoji，伺服器回覆後只校正單筆回應，不再進行第二次完整讀取；失敗則撤回暫存回應並恢復既有錯誤提示。

## 關鍵里程碑

### M0：技術方案可行（W1）

2026-08-11 已通過。兩個不同 Apple 身分在兩支真實 iPhone 完成 Supabase 登入、配對、雙向資料、五輪弱網／跨啟動 Outbox 與 development sandbox 雙向推播；共同資料的所有權、解除配對、刪除與匯出規則已由 TD-001 及相關決策確立。production／TestFlight 推播、大型封存、實際低磁碟與中斷續傳屬 G13／G15 release gates，不回頭阻擋 W2。

### M1：核心價值可在兩支手機展示（W6）

2026-08-12 已通過。兩支真實 iPhone 已完成一般 Moment 的雙向 Emoji／短文字回應與固定題庫「我們的一題」；第一份答案在伴侶回答前由 RLS 隱藏，第二份送出後雙方共同揭曉，Realtime 與強制結束後恢復結果一致。

兩位使用者可完成：

`建立 Moment → 伴侶看見 → 回應 → 進入共同時間線`

這是第一個產品價值閘門。若互動不夠清楚或無法在一分鐘內完成，優先修正核心體驗，不直接擴張功能。

### M2：完整首版循環成立（W12）

兩位使用者可從 Moment 延伸至自由聊天，也可從共同約定進入專屬討論；重要訊息可收藏為 Moment，並能在共同時間線找回內容及返回相關約定或對話。

### M3：隱私與資料處理可驗證（W14）

通知不洩漏私密內容，App Lock、解除配對、刪除與匯出能在真實雙人資料情境下正確完成。

### M4：可進入熟人圈 TestFlight 煙霧測試（W16）

符合 [iPhone 首版完成定義](../product/04-iphone-mvp-scope.md#首版完成定義)，且不存在會造成資料外洩、資料遺失、錯發訊息或無法解除配對的阻斷問題。煙霧測試還必須證明 TestFlight 建立的顯示名稱、本人私人稱呼、尚未過期狀態、relationship、聊天、照片、Moment、共同約定、討論、時間線及封存可由正式 release build 接續與遠端恢復，才能進入公開上市。

## W1 技術閘門（已完成）

2026-08-11，G1／M0 依原始完成條件正式通過：Supabase 責任邊界與資料生命週期已接受，兩支真實 iPhone／兩個 Apple 身分完成 development 登入、配對、雙向資料、五輪弱網／跨啟動 Outbox 與雙向推播。production／TestFlight、大型封存、實際低磁碟與中斷續傳移至 G13／G15 release gates；它們不再形成 W1→W2 的循環依賴。

### 完成前累積紀錄

以下長段保留 2026-08-10 以前的逐步驗證脈絡；其中 `in_progress` 與「G1／M0 尚未通過」是當時快照，已由上方 2026-08-11 完成結論取代。

目前狀態為 `in_progress`。TD-001 已接受 Supabase 作為 iPhone v1 使用者身分、伴侶關係、共同資料與資料生命週期的唯一遠端系統紀錄，CloudKit Sharing 不進入正式共同資料架構。Supabase 已由兩個 Apple 身分完成 Auth、pairing、active relationship RLS 雙向寫入、Realtime 雙向事件、私有 Storage 照片雙向讀寫、closing 後拒絕共同寫入、雙份 personal archive、archived photo 讀取、owner-only 獨立刪除與最後引用 Storage GC；遠端測試專案另以第三 authenticated UUID 證明共同資料不可見，marker、message、photo finalization 與解除配對 RPC 均拒絕。單筆與三筆 FIFO marker metadata outbox 均已完成斷網、App 重啟、恢復網路重送及雙裝置一致性實測；照片持久 outbox 已完成真機 A＋Simulator B 的單張與三張斷網、跨啟動、恢復網路單次 FIFO drain、順序一致及跨裝置可見性實測。斷網冷啟動的 relationship 顯示已加入依使用者隔離的唯讀快照；大圖縮放、EXIF 方向正規化與 GPS metadata 移除亦已加入實際 JPEG regression，合計通過 `build-for-testing`、26 個 Simulator runtime tests、真機離線冷啟動及高解析直向照片跨裝置回歸。文字訊息契約、FIFO outbox 與封存正文保留已完成 migration 008 雲端部署、81 個 pgTAP、23 個 Simulator tests，以及真機 A＋Simulator B 的在線同步、三筆離線跨啟動 FIFO、恢復網路重送與去重實測。W1 client 現另加入登入／前景恢復後的一次性 outbox recovery：先更新關係，再只依序處理目前 active relationship 的 marker、message、photo，並拒絕 closing、archived、舊關係與並行重入；純規則與完整 `CoupleSpaceTests` 48／48 通過，真機 A＋Simulator B 的背景返回及強制結束後重啟兩條自動 drain 流程也已完整通過，三種內容均送達、清空、跨裝置可見且無重複。前景 unavailable→available 監聽候選已完成本機實作、測試及真機 A＋Simulator B 跨裝置驗證；正式長時間退避、production 網路監聽與背景排程仍未決定。私人推播 migrations 009／010 與 `send-w1-push` version 1 已部署 Supabase 測試專案，限制 token 不可直接讀取、由 active 2/2 relationship 推導另一位收件者，並固定使用不含私人內容的工作與 payload；APNs secrets 已設定且真機 sandbox token 已成功登記。遠端 Function 為 ACTIVE、JWT 驗證開啟且未授權請求回傳 401；Simulator B 已把正確泛化通知送達背景、終止及鎖定狀態的真機 A，Apple Watch 亦正常鏡像相同泛化通知。個人封存匯出已建立 version 1 JSON manifest＋UUID JPEG 資料夾候選，真機「儲存到檔案」、manifest／照片對應及敏感欄位核對均正常；照片現已逐張寫入受保護磁碟 staging，完成／失敗與下次匯出前會清理。真機複驗發現交付名稱與 staging 同名碰撞後已重建無來源名稱的根 wrapper，兩次新位置交付與重試均成功；明確清理其他 relationship 測試 marker 的恢復路徑亦已加入。2026-08-07 本機另完成 message／marker 各 100 筆、photo 32 筆的持久 FIFO drain，以及 64 張各 64 KiB 合成照片的磁碟 staging／輸出與部分 staging 清理 regression；PD-020 的核心雙向互動／每週雙向聊天規則與私密內容不進分析編碼 regression 亦已加入。這些只是結構壓力與純規則樣本，不是正式容量或雲端分析證據。系統選擇器以返回後按 X 取消時，提示 callback 會延至下一次匯出，列為非阻斷 UI 時序限制。照片 closing 競態的 migration 011 與 client orphan reconciliation 已通過本機 125 個 pgTAP、schema lint，migration 011 已部署 Supabase 測試專案，真機 A 離線待送＋Simulator B 觸發 closing 的跨裝置時序亦已通過。PD-022 已接受照片不按時間自動到期，並沿用 active relationship、owner-only 個人封存、明確刪除與最後引用 GC 的既有生命週期，因此不需新增 migration。兩支真實 iPhone、照片頻繁弱網、長佇列與大型封存真機壓力，以及正式訊息仍未完成，因此 G1 與 M0 尚未通過。詳細證據記錄於 [W1 技術驗證紀錄](02-w1-technical-validation.md)，接受脈絡記錄於 [技術決策紀錄](../decisions/technical-decisions.md)。

前景 outbox recovery 已進一步加入有限次短退避：登入／回到前景時立即嘗試，若仍有同一 active relationship 的待送項目，依序等待 1 秒與 4 秒再試，合計最多三次；之後停止並保留 Outbox。真機 A＋Simulator B 已完成短暫斷線後不按人工重試即自動送達、持續斷線至三次耗盡後保留待送項目，以及恢復網路後由下一次前景事件送達且對方只收到一次的驗證。W1 client 現另以 `NWPathMonitor` 觀察前景中的 unavailable→available，才觸發同一 coordinator；初次啟動已連線、重複 available、轉為離線或持續離線均不觸發。完整 `CoupleSpaceTests` 59／59 通過；真機 A 在 App 保持前景時離線建立待送 marker，恢復網路後 Outbox 自動清空，Simulator B 只收到一次。這不包含背景 task、長時間退避或無限輪詢。

照片持久 Outbox 現另在寫入重新編碼 JPEG 前，檢查其所在 volume 的已知可用空間；若明確少於本次 JPEG bytes，會在建立本機檔案與 queue metadata 前拒絕並顯示空間不足。容量無法取得時仍沿用既有原子寫入錯誤保護，不加入任意安全倍數或新的商業配額。完整 `CoupleSpaceTests` 61／61 通過，涵蓋剛好足夠、少一 byte、容量未知，以及拒絕後不留下檔案／queue；2026-08-10 真機 A 的正常上傳路徑亦完成回歸，Simulator B 可讀取該照片且 Outbox 清空。這不代表真機低磁碟或容量壓力已通過。

以下實作細節尚未決定，不得在規劃中默認某一實作方式：

1. 正式訊息資料模型、長佇列真機壓力、正式自動排程、長時間退避、production 網路監聽與背景重試；message／marker 各 100 筆的本機 FIFO regression，以及登入／前景恢復的一次性 immediate retry 與三次有限短退避真機流程均已通過。前景離線→連線觸發已完成本機候選與真機跨裝置驗證；正式長時間重試與背景執行仍未定案。
2. 照片正式 upload outbox、縮圖、壓縮、正式容量與高壓情境下的刪除一致性；保存生命週期已由 PD-022 關閉，本機 Outbox 寫入前的精確 bytes 容量預檢已完成，但真機低磁碟壓力仍待驗證。
3. 個人封存匯出的正式格式、容量與中斷後續傳；W1 資料夾候選已改為逐張下載至磁碟 staging，64 張／4 MiB 合成樣本與部分 staging 清理通過本機測試。migration 013 另把照片 byte size 複製進個人封存，讓 App 在下載前比較 manifest＋照片總大小與暫存 volume 可用空間；140 個 pgTAP、58 個 Simulator tests、本機與 linked `public` schema lint 通過，migration 已部署 Supabase 測試專案，既有 archived relationship 的真機正常匯出路徑亦完成複驗。大型真機壓力、實際低磁碟空間與中斷點續傳仍待驗證，也不代表最終產品格式。
4. 推播 production／TestFlight 送達仍待 G15 實測；兩支真實 iPhone 的 development sandbox 雙向接收者、背景／終止／鎖定與敏感內容隱藏已通過。

PD-020 已關閉「有意義雙向互動」的定義與資料最小化方向：同一 Moment、同一題或同一共同約定內的雙方參與構成核心指標，自由聊天另以每週雙向聊天活躍衡量；完整內容保存在受 RLS 保護的產品資料與私有 Storage，分析事件只保存內容參照與必要 metadata。雲端事件彙整及產品資料／Storage 備份還原仍須在相應垂直切片與 release gate 驗證，不在 W1 建立第二份私密內容資料。PD-021 的 Free 照片研究額度 migration 012 已部署 Supabase 測試專案：伺服器核對 object owner／bytes 並以 relationship lock 執行 UTC 月曆月 30 張與累積 1,000,000,000 bytes，App 不可直接繞過 photo metadata finalization；139 個 pgTAP 與 55 個 Simulator tests 通過，client regression 另要求配額拒絕時先清除遠端 object、成功後才移除本機 Outbox，清理失敗或未知原因則保留待重試。真機 A＋Simulator B 的近同時雙上傳已確認兩筆均建立且雙方收斂至同一張最新照片；另以可回收 fixture 分別建立本月 30 張與累積 999,999,999 bytes 邊界，第 31 張及跨越 1 GB 的照片都正確顯示對應上限、未建立 metadata、清空 Outbox 並刪除新 Storage object。兩組 fixture 清理後遠端均回復原有 5 筆 metadata／5 個 object／1,164,373 bytes；週期與額度仍只是 TestFlight 研究假設。

技術方案至少需以兩支真實裝置與兩個不同 Apple ID 完成小型驗證，不能只依文件或單機模擬結果判斷可行。

## 第一版範圍控制

### 本路線圖包含

- iPhone 帳號、邀請與一對一配對。
- 本人顯示名稱、owner-only 伴侶稱呼，以及主動設定且具期限的此刻狀態。
- Moment、回應、固定題庫版「我們的一題」。
- 文字與照片聊天、Emoji 回應、未讀數及離線重試。
- 基本共同約定、近期與月曆瀏覽、專屬討論、基本提醒及活動後建立相關 Moment。
- 將聊天訊息收藏為 Moment。
- 按月份分組、可依日期／月份快速跳轉及使用最小內容類型篩選的共同時間線，以及最小規則式每週回顧。
- 私密推播、App Lock、匯出、刪除與解除配對。
- 支援產品驗證所需的最小分析與品質監控。

### 本路線圖不包含

- Apple Watch 核心功能。
- macOS 或 visionOS 功能適配。
- Home Screen Widget。
- StoreKit、正式訂閱價格、付費牆與「支持開發者」真實收款。
- AI 回顧、AI 關係分析或伴侶評分。
- 進階搜尋、月度或年度回顧。
- 完整共享行事曆、外部日曆雙向同步、重複行程、多人邀請、多組日曆、投票、任務指派與子討論串。
- 通話、群組、位置、貼圖商城與已讀狀態。
- 在線／離線、最後上線、狀態觀看紀錄與完整即時動態牆。

上述功能若要提前加入，必須先說明其驗證目的、對時程的影響，以及要交換掉的既有第一版目標。

## 並行驗證工作

開發期間同步執行 [成功指標與驗證計畫](../product/06-metrics-and-validation.md)：

- W1–W4：訪談 10 對種子客群情侶，伴侶分開訪談。
- W1–W3：以可點擊原型驗證 `建立 Moment → 邀請 → 回應／共同揭曉 → 對話 → 收藏 → 時間線`。
- W1–W3：同步驗證 `建立共同約定 → 專屬討論 → 活動後建立 Moment → 返回原約定`，確認資訊集中但不分散日常對話。
- 名稱／稱呼與此刻狀態的伴侶分開訪談及可點擊原型由產品研究另行規劃，不作為 G6A 開發排程或工程完成 gate。
- W4 前：確認第一個 Moment 的預設內容與邀請文案，避免在配對流程中臨時決策。
- G16：以兩帳號、兩支真實 iPhone 執行 3–7 天熟人圈 TestFlight 煙霧測試，不把此階段當作公開獲客或長期留存研究。
- G17：正式上架後執行一個月繁中上市活動，以伴侶對追蹤雙人啟用、雙向互動、W1／W4 留存、Plus Launch Pass 使用、品質、成本與自願訂閱。

研究結果可調整文案、操作與優先順序；若要改變已確認的產品邊界，需先更新產品決策紀錄。

## 時程調整規則

- G1 技術驗證延後時，後續日期整體順延，不以省略資料安全工作追回進度。
- 任一目標未滿足完成條件，不因畫面可展示就標示為完成。
- 若時程不足，先簡化呈現方式，例如固定題庫、規則式每週回顧；不得刪除首版完成定義中的核心流程而不更新產品決策。
- 遇到資料錯發、資料遺失、通知洩漏或解除配對結果不一致時，停止新增功能，先處理可靠性與安全問題。

## G17 正式上市 gate

四語公開上市不納入 16 週 TestFlight 候選版的固定承諾；G16 煙霧測試通過、準備進入 G17 正式上架前，至少完成：

- 以繁中 canonical copy 維護 `zh-Hant`、`zh-Hans`、`en`、`ja`，完成關鍵流程、複數、截斷、日期與權限文案 QA。
- 四語 App Store metadata、版本說明與基本幫助內容；首輪付費投放與持續市場內容只做繁中。
- App 內單一「幫助與意見」入口、可查詢的案件欄位、隱私同意與不承諾回覆時間的確認文案。
- 依 TD-003 與[一人營運災難復原規格](../architecture/01-disaster-recovery.md)完成 production PITR、供應商外加密 Database／Storage 備份、recovery manifest、deletion journal、dead-man alert、signed service manifest、獨立狀態頁、降級模式與 emergency operations kit。
- 在另一 region／核准替代環境完成 D4 冷重建 drill；Database、Storage、設定與刪除 journal 對準同一 recovery point，通過 counts、checksum、reference integrity、RLS、第三人隔離及清空本機狀態真機恢復。初始 6 小時 RPO／8 小時 RTO 只作內部候選，須記錄實測且不得先轉成公開 SLA。
- 適合共同回顧的照片顯示版／縮圖規格與真機畫質、流量、容量驗證；不宣稱原始畫質備份。
- App Store 版本說明、App 內更新中心、重大事故狀態頁三層公告流程，以及 phased release／回滾檢查表。

若 TestFlight build 提供「支持開發者」流程，只能使用 StoreKit／Sandbox 驗證，不向測試者實際收款。G18 上市首月決策後若決定在 App Store 正式供應版本啟用，必須與訂閱及其他 StoreKit 工作共同排序，並完成當時適用的商品價格、審查說明、交易、取消、失敗與退款驗證。

詳細規格見[上市、客服與版本發布營運](03-launch-support-and-release.md)。

## 災難復原交付順序

本工作不改變 W10–W14 核心產品切片的內容，但屬 G15／G17 阻擋 gate，不得因功能排程延誤而省略：

1. **G15 前 production-like 基礎：** 外部 encrypted DB／Storage backup、manifest、freshness alert、synthetic restore、App `read_only／recovery` 行為及一致版本 restore drill。
2. **G16 煙霧測試期間：** 使用 TestFlight 真實升級、換機／重裝、Outbox 與事故 mode 驗證操作文案及不需重新配對；不對測試者宣稱尚未演練的 RPO／RTO。
3. **G17 公開前 production 關閉：** paid production／PITR、不可變外部副本、deletion journal、signed manifest、另一 region 冷重建、status page、break-glass 及 release evidence 全部通過。
4. **公開後營運：** 每月 synthetic restore、每季 production-backup 隔離 restore；schema、Storage、Auth、encryption、delete／unpair、backup 或 endpoint 有變更的正式版本重跑受影響 drill。
