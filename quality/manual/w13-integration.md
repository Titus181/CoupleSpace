# W13-INTEGRATION-001：G12 推播與裝置隱私整合關閉

本清單只編排 W13 目前已接受的控制與既有人工 gate，不取代各清單的詳細步驟。同一個候選 build 已在最後行為變更後完成適用自動化、兩支真實 iPhone 驗收及 W8–W11 回歸，因此本候選可把 G12／W13 標示完成。Simulator 仍只能作 preflight。

依 PD-044，`SESSION-001` 已退役：正式產品不提供 session／裝置 inventory 或遠端撤銷；該 stable ID 在 release record 記為 `NOT_APPLICABLE (REMOVED)`，歷史 FAIL 保留於 [session capability record](session-capability.md)。

## 不變量

- 一般「登出」只處理目前裝置的 local session；同帳號其他裝置不應被登出。
- 同一帳號可在多台裝置登入並讀寫同一份 server SSOT；本機 App Lock、通知權限、提醒、cache 與 APNs routing 仍各裝置獨立。
- 正式帳號設定不得顯示「登出其他所有登入」、session／裝置清單或指定撤銷；也不得呼叫 `.others`／`.global`。
- `push_devices`、APNs token、Apple ID、裝置名稱或 install ID 都不是 Auth session identity；local logout、App Lock、APNs token cleanup、解除配對與資料刪除是不同控制。
- Local logout 不得更新 relationship／membership、共同內容、本人或伴侶的個人封存、deletion tombstone 或 server-authoritative 未讀資料。
- 本候選版的 remote push 固定使用泛化、不含私密內容的 payload。任何文字內容 preview 必須等 W13 完成後另案接受與驗收。

## 0. 候選版與環境

1. 兩台可以先各自從目前裝置登出，再以同一個可清理的測試帳號重新登入，建立不受先前 `.others` 嘗試影響的候選版基線。這是新的 local Auth 狀態，不是證明舊遠端撤銷成功。
2. 記錄 commit、App version／build、Xcode、iPhone A／B 與 iOS、Supabase test-project 代號、migration history 及開始時間；不記 raw UUID、JWT、refresh token、Apple identifier 或 APNs token。安裝本候選 build 前，test project 必須已依序套用 migration 038、039 與 040；缺 038 時兩參數 push registration 可能命中舊 overload 歧義，缺 039 時 message-bound read RPC 不存在，缺 040 時約定 lifecycle 的 server-owned read boundary 與 bounded RPC 不存在。2026-08-20 已確認 linked test target `CoupleSpace-W1-Dev` 的 local／remote history 同為 001–040；此遠端環境前置條件已滿足，但不代表下列真機 gate 已通過。
3. 確認 paired／unpaired／closing／archived 的正式畫面都只有目前裝置登出，沒有 inventory／remote-revoke UI；shared Run scheme 的 `--session-capability-probe` 預設關閉，Release 不出現 probe，受控 DEBUG probe 也沒有 `.others` action。
4. 依最後行為變更判斷是否已有可靠且仍適用的自動化證據；不可無理由重跑已通過且依賴未變的 gate。仍受變更影響者執行 `quality/scripts/run-full-automated-suite.sh --reset-local-database`，確認空資料庫依序套用 migrations 001–040，並記錄 pgTAP、schema lint、Edge Function、iPhone executions／failure／skip、SDK capability probe、Harness 與 diff hygiene。
5. 任一適用 failure、skip、版本不符、正式 remote-revoke 入口殘留或無法確認 test project 均為 `FAIL`／`BLOCKED`，不得開始最終真機整合。

## 1. 同帳號兩支真實 iPhone：multi-device／local logout

以 A、B 表示兩支真實 iPhone，兩台使用同一測試 Supabase user `S`：

1. **乾淨登入：** A、B 各自在候選版完成 Apple 登入。確認兩台顯示相同帳號識別與同一 active relationship，不要求重新配對。
2. **Server SSOT 基線：** 兩台各自回前景並刷新，核對 relationship／active membership、共同 history fixture、共同約定及 `S` 本人個人封存。只記去識別 identity、count 與 PASS／FAIL；兩台必須一致。
3. **呈現基線：** 記錄兩台各 scope 的 server-authoritative 未讀、對話 badge、App icon badge，以及 CoupleSpace pending local reminder 的去識別 identifier／count。清楚區分 server 值與各裝置本機值。
4. **跨裝置收斂：** 在 A 建立一筆不含私人內容的測試內容，等待 server ack；B 經 Realtime 或前景 refresh 後須看到同一 server identity，不能重複、錯序或要求重新登入。B 的回應／讀取狀態也須在 A 收斂。
5. **A local logout：** 由 A 使用正式「登出」並確認。A 必須進入 Apple 登入；強制結束再重開仍不得恢復舊 local authenticated state。此操作不得顯示或宣稱 B 已登出。
6. **B 不受影響：** B 保持登入，可 refresh、讀取並寫入同一 relationship；共同資料、本人個人封存、未讀／badge 契約不因 A logout 被清空或改寫。
7. **控制分離：** 依 [PUSH-002 本機提醒段落](push-privacy.md#w13-切片-5共同約定本機提醒badge-回歸)核對 A logout 的本機 cleanup；B 的 Auth 與本機提醒不受影響。APNs routing record 是否仍存在不能作為 A 或 B Auth 有效性的證據。
8. **A 重新登入恢復：** A 以同一 `S` 完成 Apple 登入；不得重新配對。刷新後須恢復第 2 步的 relationship、共同 history、約定與本人個人封存，並看見第 4／6 步的新 server 內容；未讀／badge 由 server truth 收斂，本機提醒依既有規則重新 reconciliation。
9. **交換角色：** 對 B 重複第 5–8 步，確認 local logout 行為不依賴特定裝置或先後順序。
10. **資料生命週期核對：** 全程不得出現 unpair、closing、archived、archive create／delete、內容刪除、deletion tombstone 或新的 relationship；兩台重新登入後仍是同一帳號與同一授權資料。

## 2. 兩個 relationship 身分：W13 控制整合

完成同帳號測試後，使用既有安全的 local logout／Apple login 流程，讓 A 使用 relationship owner `S`、B 使用另一位 owner `P`。先確認兩台是同一 active relationship 的兩位 owner，再依序執行：

1. [LOCK-001](app-lock-and-background.md)：啟用／停用、冷啟動、inactive／background、App switcher、取消／失敗；不得改變 Auth、relationship 或 Outbox。
2. [PUSH-002](push-privacy.md)：先執行「步驟與預期」的遠端推播驗收；一般對話、約定討論與約定 lifecycle 在前景、背景、終止及鎖定畫面送達正確收件者，維持泛化 payload，不洩漏私密內容。本文件後半的本機提醒段落依下列第 4、6 步拆分，避免提早進入 closing。
3. **切片 4 activity／badge：** 依 `quality/test-catalog.md` 的 `CHAT-001`、`PUSH-001` 與 `relationship_interaction_unread.test.sql` 執行下列順序；每一步都記錄 server-authoritative 各 scope／total、對話 badge、App icon badge 與時間，不得只看單一 UI 數字。
   1. 先把 main chat 與各約定 scope 收斂為 0，確認 B 停留在「今天」；A 送一則文字，B 的 main／total／兩種 badge 應只增加 1，等待至少 10 秒、手動 refresh 及背景回前景後仍不得自行歸零。
   2. B 仍停留在「今天」時，A 再送一張完成上傳且已 server ack 的照片；同一組值再增加 1 並保持。只有 completed photo 可計數，上傳中、失敗或同 operation 重試不得重複增加。
   3. 將 B 切到「我們」，以新的文字與照片重複前兩步；未實際顯示 main conversation 時不得呼叫 mark-read。B 自己建立的內容不計入自己的未讀。
   4. 建立一筆舊 main unread，讓 B 進入對話後立刻切回「今天」或「我們」，同時由 A 再送新內容；先前已讀請求完成後，新內容仍須保持未讀，不能出現 `+1 → 0`。
   5. B 選在對話分頁但由 App Lock 遮蔽、App 在 inactive／background，或已推入約定討論時，由 A 送 main 內容；main unread 不得被背景畫面誤清。解鎖或回前景後若仍停在「今天／我們／約定討論」也不得清除。
   6. B 真正打開 main conversation 後，main scope 才收斂為 0；任何約定 discussion／lifecycle scope 必須維持原值。再由 A 對指定約定送文字、照片及 create／effective update／cancel，各唯一增加 1；開 main chat 不得清除，只有開啟正確約定詳情／討論才可清該 scope，其他約定不受影響。討論文字／照片以 migration 039 的 visible message identity 為界；約定 create／effective update／cancel 則必須使用 migration 040 隨約定 snapshot 回傳的 `interaction_boundary_source_identity`，不能以 scope-latest、client time 或 App 當下重新推測的 operation 代替。
   7. 建立一個尚有 lifecycle unread 的約定舊 snapshot，讓 B 開啟該舊詳情；在舊 read request 完成前，由 A 再做 effective update 或 cancel。舊 request 最多只能前進至畫面實際呈現、且經 server 重新驗證的 source identity，較晚的 lifecycle event 必須保持未讀。B 刷新並實際看到新 snapshot 後再次進入，才可清除新 boundary；跨 relationship／跨 appointment、未 applied operation、偽造 source 或倒退 boundary 都不得越界清除。
   8. 重送相同 source identity／operation ID 不得加倍；讀完所有 scope 後，server total、對話 badge 與 App icon badge 最終一致收斂為 0。本機 reminder 不參與此計數，local logout／重新登入也不得製造或清除 server activity。
4. **切片 5 reminder privacy（active 部分）：** 執行 [PUSH-002 的 W13 切片 5 段落](push-privacy.md#w13-切片-5共同約定本機提醒badge-回歸)第 1–3、5–7 步，驗證建立／改期／重開／取消／拒絕權限、badge 不變，以及在途 background refresh 不會在 logout／scope switch 後復活 cache／observer／reminder。第 4 步含 closing，保留到下列最後的 lifecycle 階段；第 7 步的 closing 分支也在最後 lifecycle 階段完成。
5. **W8–W11 regression（active 部分）：** 在 relationship 仍為 active 時執行 [W8–W11 回歸](w8-w11-regression.md)的 W8–W10 與 W11 第 1–6 步，以及 W11 第 7 步中不會登出、解除配對或封存的 two-iPhone／提醒案例。W11 第 7 步的登出／解除配對 cleanup 與第 8 步封存加驗保留到下一步；不得以本次 Auth 或 push 單點結果取代聊天、弱網、照片、來源與共同約定的既有 gate。
6. **切片 6 lifecycle（最後執行）：** 在專用可清理的 active fixture，先建立待 cleanup 的 reminder／W11 約定資料，再一併執行 reminder 第 4 步、W11 第 7 步延後的登出／解除配對 cleanup、W11 第 8 步封存加驗與完整 [LIFECYCLE-001](deletion-and-unpairing.md)。核對 closing／archived、雙 owner 個人封存、提醒／cache／Outbox／badge；local logout／重新登入本身不得觸發任何 lifecycle transition。此步具破壞性，不能先做而使前述 active-relationship gates 無法執行。

## 候選與 preflight 證據

- iPhone 17 Simulator（iOS 26.5）的 unit bundle `/private/tmp/CoupleSpace-slice8-unit-lock-boundary-final.xcresult`：191／191 passed、0 failure、0 skip。範圍包含 rendered appointment boundary、model stop 後拒絕 stale refresh／cache／observer、in-flight reminder reconcile teardown、background refresh 在 logout／account switch／relationship switch／closing 後不排程，以及 local logout 等待 authenticated content teardown。
- 同一 Simulator 的 focused UI `/private/tmp/CoupleSpace-slice8-appointment-ui-focused-2.xcresult`：`testConversationOpensRecentlyUpdatedAppointmentDiscussion()` 1／1 passed、0 failure、0 skip；只證明該 fixture 的約定討論入口與返回後未讀呈現，不是完整 UI suite。
- 最終 `quality/scripts/run-full-automated-suite.sh --reset-local-database` 已以 exit 0 完成：本機依序重放 migrations 001–040，31 files／533 pgTAP PASS；`supabase db lint --local` PASS，只保留 migration 034 既有的 unused `recipient_id` warning；APNs 7／7；iPhone 17 Pro Simulator（iOS 26.5）完整 scheme 236 個測試定義／239 次 executions、0 failure、0 skip；session scope guard、Harness v0.2.1 與 diff hygiene 均 PASS。完整 artifact：`/tmp/CoupleSpace-release-evidence.l8E2mW/CoupleSpace.xcresult`。
- linked test target `CoupleSpace-W1-Dev` 已只部署原先 pending 的 migration 040；部署後 local／remote migration history 同為 001–040，第二次 dry-run 回報 remote 已是最新。linked `public`／`extensions` schema lint exit 0，只保留 migration 034 既有 unused `recipient_id` warning；遠端 schema／ACL 核對及匿名呼叫 smoke 均通過，確認 migration 040 欄位與三參數 SECURITY DEFINER RPC 存在、PUBLIC execute 已撤銷，匿名請求由授權邊界拒絕而非 missing function／overload ambiguity。
- iPhone 17、iPhone 17 Pro 與 iPhone 17 Pro Max 三台 Simulator 已安裝同一候選 App（hash prefix `b05d650a`），三台均保留既有 Auth，並顯示同一個兩位 owner 的 active relationship。這只證明候選安裝與 production-auth fixture preflight，不能證明真實 APNs、Face ID、鎖定畫面、App icon badge 實機行為或本機通知送達。
- production-auth 5C 文字 preflight 已在三 Simulator 通過：接收端分別停留「今天」與「我們」時，main／App icon 未讀正數至少持續 10 秒，切到背景再回前景仍保留；只有真正打開 main conversation 後才清為 0，同帳號另一台前景同步後亦清為 0。artifacts：`/private/tmp/CoupleSpace-w13-prod-hidden-today.xcresult`、`/private/tmp/CoupleSpace-w13-prod-hidden-us.xcresult`、`/private/tmp/CoupleSpace-w13-prod-open-clear-2.xcresult`、`/private/tmp/CoupleSpace-w13-prod-same-account-clear.xcresult`。此 preflight 只涵蓋文字路徑，不取代 5C 的照片、race、App Lock、約定 discussion／lifecycle 與兩支真實 iPhone 驗收。
- migration 040 的 linked test 前置條件與三 Simulator preflight 已完成；其後同一最終候選已完成下列兩支真實 iPhone 整合。先前版本的真機 5A／5B 結果仍不充當本候選證據；final gate 只採用 2026-08-20 的本候選人工結果。`SESSION-001` 仍只記 `NOT_APPLICABLE (REMOVED)`。

## 2026-08-20 final candidate 真機結果

- 證據型態：使用者依本清單完成同一候選版的人工作業後，明確回報下列六段皆「正常」；未補造 screenshot、裝置資訊或逐步 log。
- iPhone A／iOS：`未記錄`
- iPhone B／iOS：`未記錄`
- APNs environment：`未記錄`
- 精確完成時間：`未記錄`
- **同帳號 local logout：PASS。** 兩台同帳號基線、任一台 local logout 隔離、強制重開、重新登入恢復與交換裝置均正常。
- **切回兩位 relationship owner：PASS。** 兩台回到同一 active relationship 的兩位 owner，整合前置正常。
- **LOCK／PUSH／5C／W8：PASS。** App Lock、真實推播、未讀／badge 與 W8 合併流程正常；對應 `LOCK-001`、`PUSH-002` 及 W13 引用的 `DEVICE-001` 範圍。
- **約定、討論與提醒：PASS。** 約定 lifecycle、討論 unread boundary、泛化提醒與 cleanup 流程正常。
- **W9／W10／W11 active regression：PASS。** active relationship 下的弱網／重試、照片／互動及共同約定回歸正常；對應 W13 引用的 `NETWORK-001` 範圍。
- **Lifecycle 最後執行：PASS。** destructive lifecycle 依序最後執行且正常；對應 `LIFECYCLE-001`。
- 結論：`W13-INTEGRATION-001` 為 `PASS`；EVAL-004／EVAL-008 在 W13 候選關閉語意下為 `PASS`，G12／W13 可標示完成。這不宣稱 TestFlight Gate D、DR／UPGRADE 或全產品 release-ready。

## 判定與證據

- `PASS`：正式 inventory／remote-revoke UI 已移除；同帳號 A／B 的 server SSOT 一致、任一台 local logout 不影響另一台、強制重開不恢復已登出的 local session、重新登入不需配對且資料完整；LOCK／PUSH／activity-badge／reminder／lifecycle／W8–W11 與適用自動化全數通過。
- `FAIL`：正式版仍可呼叫遠端撤銷、local logout 誤登出另一台、登出裝置重開恢復舊 local session、重新登入遺失授權資料／要求配對、relationship 或封存改變、錯誤收件者、私密內容外洩、badge／提醒契約退化，或任何 control 被混作另一 control。
- `BLOCKED`：沒有兩支真實 iPhone、同帳號與 relationship 雙身分、可清理 test project、APNs／Face ID 環境或任一必要 fixture。Simulator、歷史版本或已退役 `SESSION-001` 都不能解除 BLOCKED。

結果已填入 `quality/releases/1.0-1.md`：`SESSION-001` 維持 `NOT_APPLICABLE (REMOVED)` 並引用歷史 FAIL；`W13-INTEGRATION-001` 與所有 W13 引用 gate 已填 `PASS`，G12／W13 標示完成。此結論只關閉 W13 候選，不取代 TestFlight Gate D、DR／UPGRADE 或其他全產品 release gate。
