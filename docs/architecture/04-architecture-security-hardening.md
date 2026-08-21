---
title: CoupleSpace 架構與資訊安全強化計畫
status: active
last_updated: 2026-08-21
---

# CoupleSpace 架構與資訊安全強化計畫

## 文件角色

本文件是 CoupleSpace 的架構與資訊安全 finding register、修正順序及驗收依據。它記錄 2026-08-20 唯讀靜態審核所確認的落差，讓 W14 開發中、W14 整合後或 TestFlight 前的獨立 hardening slice 能以同一組 ID、風險邊界及關閉證據工作。

本文件不取代：

- [系統架構](../ARCHITECTURE.md)定義的責任與依賴方向。
- [技術決策紀錄](../decisions/technical-decisions.md)中的 accepted／proposed 狀態。
- [W14 資料生命週期與基本匯出契約](03-w14-data-lifecycle-contract.md)的產品資料語意。
- [版本發布閘門](../../quality/release-gates.md)與[測試目錄](../../quality/test-catalog.md)的執行／證據 SSOT。

`status: active` 只表示本計畫正在追蹤；不代表任何 finding 已修正、部署或驗證。本文件本身不授權 migration／Function 部署、TestFlight、commit 或 push。

## 證據與狀態語意

### Evidence

- `confirmed-static`：目前 checkout 的程式、設定或 migration 可直接確認。
- `inference-needs-verification`：靜態證據顯示風險，但影響須由本機、archive、Simulator、真機或遠端受控測試確認。
- `verified-linked`：本輪已直接讀取並驗證 linked Supabase target；不外推為 production、其他 region 或正式 restore drill 證據。
- `unverified-external`：屬簽署後 artifact、Supabase linked／production、Apple 服務、CI secrets 或營運狀態，本輪沒有讀取或驗證。

### Delivery

- `backlog`：尚未開始；即使已有建議，也不可宣稱完成。
- `in_progress`：已選入明確切片，但仍未取得全部關閉證據。
- `fixed`：實作已完成，仍待適用的 runtime／artifact／遠端 gate。
- `verified`：程式、最低可靠層 regression、受影響完整 gate 與必要 artifact／runtime 證據均成立。
- `not_reproduced`：以可重現的正確環境證明原推論不成立；必須保留測試步驟與 artifact，不能由靜態意見直接指定。

### Severity

- `Critical`：已確認可造成跨身分私人資料暴露、不可逆資料損失或 production authority compromise。
- `High`：重要信任邊界、完整性、資源濫用或 Release blocker；適用項目未關閉前不得進 Gate C／D。
- `Medium`：需要排程修正或驗證的 privacy、defense-in-depth、架構或工具落差。
- `Low`：不直接阻擋發布的維護性風險。

Critical／High finding 在 Gate C／D 前必須為 `verified`，或以完整可重現證據記為 `not_reproduced`；不使用 `WAIVED` 視為發布通過。掃描無 finding、build 成功或歷史版本曾通過都不能單獨改成任一終態。

## 審核基線與限制

- 基線日期：2026-08-20。
- 基線工作樹：W14-02 Moment 軟刪除仍在未提交開發中；本文件不把 migration 041、runtime 或 `MOMENT-004` 寫成完成。
- 本輪沒有確認到匿名或第三人可直接跨 relationship 讀取私人內容的 Critical 漏洞。
- 本輪不是滲透測試，未建立簽署後 Release archive，未驗證 linked／production schema、Apple／APNs 設定、備份還原、真實裝置 container、Git history secrets 或完整依賴 CVE。
- 基本 checked-in pattern scan 未見明顯秘密；這不等於 secret history scan PASS。
- 路徑與 symbol 是主要證據；行號會隨 W14 工作樹變動，實作前必須重查目前 checkout。

## 應保留的現有優勢

- Supabase session、constraint、RLS、受控 RPC 與私有 Storage 是共同資料的 server-authoritative 邊界。
- Realtime 只作變更提示，client 仍經 RLS 重讀。
- Outbox 使用 user／relationship scope、stable UUID、FIFO 與冪等 server write。
- 推播收件者由 server 推導，event allowlist 與泛化 payload 不攜帶訊息正文、sender 名稱或照片。
- App Lock 驗證取消、失敗與無法使用時均維持遮蔽。
- pgTAP 已包含匿名、第三人及 relationship membership 負向案例；Gate A–D、test catalog、Harness 與雙真機清單已有明確證據語意。
- SwiftPM 已使用 `Package.resolved` 固定版本；client 只持有 publishable key，service-role／APNs secrets 由 server environment 讀取。

修正不得削弱以上邊界，也不得用 client UI 限制取代 server enforcement。

## Finding register

| ID | Evidence | Severity | Delivery | Release impact | 摘要 |
| --- | --- | --- | --- | --- | --- |
| `HARD-SEC-001` | `mitigated-local`＋`verified-linked` | High | `fixed` | linked 已驗證；dead-man／freshness monitor 前不可完全關閉 | service-only RPC／lease worker、migration 044、Function version 6 與 Vault-backed scheduler 已在 linked target 驗證；production 與獨立失聯監控仍待後續 gate。 |
| `HARD-SEC-002` | `confirmed-static` | High | `backlog` | Gate C 前 | `shared_items` 仍有 authenticated direct INSERT surface，可繞過 canonical RPC 的部分 server-owned 語意。 |
| `HARD-SEC-003` | `confirmed-static`＋`inference-needs-verification` | High | `backlog` | Gate C／D 前 | Storage upload 在 finalize quota 前可形成未受相同額度限制的 orphan objects。 |
| `HARD-REL-001` | `confirmed-static` | High | `backlog` | Gate C blocker | Repo 未見 `PrivacyInfo.xcprivacy`；required-reason API 尚未完成清冊與 archive 驗證。 |
| `HARD-REL-002` | `confirmed-static`＋`unverified-external` | High | `backlog` | Gate C blocker | Release 設定仍共用 development APNs／CloudKit entitlement，並保留 PoC、debug RPC 與 UI-test bypass surface。 |
| `HARD-PRIV-001` | `confirmed-static` | Medium | `backlog` | Gate B／C | 對話、Moment、約定及 Outbox／snapshot 私密欄位存於 UserDefaults，尚無統一 at-rest／backup policy。 |
| `HARD-PUSH-001` | `confirmed-static`＋`inference-needs-verification` | Medium | `backlog` | Gate C | SQL 有 push unregister RPC，但 local logout 路徑未見解除 current-device routing；terminal APNs token 亦未見 prune。 |
| `HARD-LOCK-001` | `confirmed-static`＋`inference-needs-verification` | Medium | `backlog` | Gate C | App Lock overlay 下層內容未依 `isLocked` 明確退出 accessibility tree。 |
| `HARD-ARCH-001` | `confirmed-static` | Medium | `backlog` | Gate B | `RootTabView` 同時負責 View、composition、test fixture、RPC、badge 與 lifecycle orchestration。 |
| `HARD-ARCH-002` | `confirmed-static` | Medium | `backlog` | Gate B／C | Application／G1 混有 Supabase、LocalAuthentication、CloudKit 及正式 runtime platform adapter。 |
| `HARD-ARCH-003` | `confirmed-static` | Medium | `backlog` | W14 Gate B | Relationship lifecycle 仍以 String 傳遞；未知 server state 可能被舊 client 當成一般 paired 狀態，W14 lifecycle 變更時提高優先級。 |
| `HARD-ARCH-004` | `confirmed-static` | Medium | `backlog` | W14 export Gate B | W1 export PoC 將 SwiftUI `FileDocument` 帶入 Data／Application contract，不應直接延伸成正式 export v1。 |
| `HARD-ARCH-005` | `confirmed-static` | Low | `backlog` | W14-09 後 | 大檔、集中測試與四份 lifecycle gate 重複提高修改風險。 |
| `HARD-TOOL-001` | `confirmed-static` | Medium | `backlog` | Gate B／C | 未見 checked-in CI、architecture boundary、SAST、secret history、dependency vulnerability 或完整 Edge Function gate。 |

## Server authority 與 Storage

### HARD-SEC-001：全域 Storage GC ambient authority（本機與 linked 已修正，營運監控待驗證）

**目前證據**

- W14-03 checked-in handler 只接受與 `STORAGE_GC_SCHEDULER_BEARER` constant-time 相符的 bearer；hosted server client 另由 `SUPABASE_SERVICE_ROLE_KEY` 建立。anonymous、缺 header 與一般 end-user JWT 均在進入 purge／claim 前拒絕，不再呼叫 `auth.getUser` 把任一登入者升權。
- worker 只經 `purge_expired_moments`、`claim_storage_gc_jobs`、`fail_storage_gc_job`、`complete_storage_gc_job` RPC；queue／media graph／audit／tombstone 對 authenticated 與 service role 均無直接 table grant。
- claim 使用 `SKIP LOCKED`、opaque object identity、五分鐘 lease、最後引用與同 path object ID 重驗；Storage failure、lease expiry與 completion retry 保留 body-free audit／terminal receipt，不保存 provider 原始錯誤或在 response／log 暴露 path。
- focused Function tests 8／8、W14-03 pgTAP 80／80 與本機完整 pgTAP 33 files／751 tests 已 fresh PASS；完整自動化入口也已納入 GC Function test。
- linked target `CoupleSpace-W1-Dev` 已套用 migration 044；第二次 dry-run 為 up to date，linked `public` schema error lint 為空，四個 worker RPC 只允許 `service_role`，queue／media graph／audit／tombstone tables 對 anonymous 與 authenticated 均無直接讀寫權。
- `process-storage-gc` 已部署為 ACTIVE version 6 且 `verify_jwt = true`；缺 header 與一般 client JWT 的遠端 smoke 均為 HTTP 401。scheduler job `w14-moment-purge-storage-gc-v1` 每小時第 17 分執行，credential 只由 Vault／Function secret 提供，cron command 未嵌入明文且 pg_net timeout 為 60 秒。
- 2026-08-21 00:17 UTC 的自然 cron run 成功，pg_net 實際回 HTTP 200、未 timeout／error，`purged／queued／claimed／completed／failed` 五個 counts 均為 0；這只證明 linked 空佇列授權與呼叫鏈，不外推為 production、有工作量時的並行刪除或正式 restore replay。

**剩餘關閉動作**

- 建立獨立 dead-man／freshness monitor 與失敗通知；scheduler 本身及 pg_net 六小時 response retention 不能取代失聯告警。
- 在不傷及真實資料的受控 linked fixture 驗證兩個並行 invocation 不重複刪除；目前 deterministic local fault-injection 已成立，但空佇列 HTTP 200 不能外推此點。
- 建立 legacy service-role JWT 的 rotation runbook；`STORAGE_GC_SCHEDULER_BEARER` 目前仍是高權限 legacy JWT，相容性分離不代表權限縮小。
- production 排程仍須獨立核准並遵守 TD-003；本機 server-time／fault-injection與 linked dev PASS 不能取代 production 或正式 restore replay。

**關閉證據**

- anonymous 與一般 authenticated user 均不能觸發 worker。
- 只有核准的 scheduler／service identity 可成功處理已由 server 建立的 queue。
- 兩個並行 worker 不重複刪除／dequeue；lease timeout、部分失敗與 retry cap 有 deterministic tests。
- Function tests 被完整自動化入口執行。

### HARD-SEC-002：`shared_items` direct INSERT surface

**目前證據**

- `supabase/migrations/202608050001_w1_relationship_archive_spike.sql` 對 authenticated grant `select, insert`。
- `supabase/migrations/202608070012_w1_photo_quota.sql` 仍保留 active member 的 direct non-photo INSERT policy。
- canonical message／appointment discussion RPC 另執行 trim、長度、server timestamp、appointment status 與冪等規則；直接 INSERT 並不天然擁有完全相同語意。
- 目前沒有證據顯示 relationship RLS 可被跨越；主要風險是惡意／遭入侵的 relationship member 破壞排序、未讀、取消約定討論或 normalization 等共同資料完整性。

**修正方向**

- 以 forward migration 撤銷 authenticated 對 `shared_items` 的 INSERT。
- 移除 direct INSERT policy；marker、message、photo finalize 與 appointment discussion 只走對應受控 RPC。
- 核對舊版 App／migration compatibility，避免直接撤權造成已發布 client 無法寫入。

**關閉證據**

- authenticated member direct INSERT（未來時間、空白正文、cancelled appointment scope）以 `42501` 或等價拒絕。
- canonical RPC 的正常、冪等、response-lost retry 與舊版相容路徑仍通過。
- anonymous、第三人 C 與 partner malicious-member 負向 pgTAP 納入 catalog。

### HARD-SEC-003：未 finalize upload 與 orphan 成本邊界

**目前證據**

- W1／Moment buckets 為 private，已有 5 MiB 單檔限制、owner、relationship path 與 active membership policy。
- relationship 月／總量 quota 在 finalize RPC 驗證；upload policy 本身沒有相同 object-count／reservation 邊界。
- orphan cleanup 目前主要依 uploader 主動清理，未見 server-side TTL sweep 與 outstanding-upload limit。

**修正方向**

- 最低安全結果是限制每位 user／relationship 的 outstanding uploads／速率，並建立 TTL orphan sweeper、失敗佇列、容量／egress alert 及安全的 cleanup evidence。
- 先以受控 fixture 量測 object-count／成本與 closing 競態；若既有 upload policy 無法可靠承載最低結果，再採 server-issued 短效 reservation，綁定 user、relationship、content/client ID、預期 path、bytes 與 expiry。

**關閉證據**

- 超出核准的 outstanding／速率限制被拒絕；若採 reservation，路徑、bytes 與 expiry 也必須由 server 驗證。
- 未 finalize fixture 在 TTL 後由核准 worker 清除，已 finalize／仍被引用 object 不受影響。
- concurrency、response lost、closing、最後引用與 GC tests 通過；成本告警有可重放 synthetic evidence。

## Release artifact 與 debug／PoC 隔離

### HARD-REL-001：Privacy manifest 與 required-reason API

**目前證據**

- Repo 未見 `PrivacyInfo.xcprivacy`。
- first-party code 使用 UserDefaults；volume available-capacity 等 API 亦須在實作時依當期 Apple 規則完成清冊。
- 這表示缺少 manifest／理由盤點，不代表本輪已建立 archive 並得到 App Store 拒絕結果。

**修正方向**

- 盤點 first-party 與每個 embedded dependency 的 privacy manifest、required-reason API、collected data 與 tracking 宣告。
- 新增 target membership 正確的 `PrivacyInfo.xcprivacy`，只填實際、可證明的 approved reason。
- 在每次依賴或 local-persistence API 改動時重跑 archive privacy report。

**關閉證據**

- 簽署前 Release archive 內存在正確 manifest，Xcode privacy report 無未解釋 first-party／dependency finding。
- Archive／App Store validation 與實際 API 清冊一致；文件保存版本、commit、dependency revision 與結果。

### HARD-REL-002：Release capability、PoC、debug RPC 與 test bypass

**目前證據**

- `CoupleSpace.xcodeproj/project.pbxproj` 的 Debug／Release 都指向 `CoupleSpace/CoupleSpace.entitlements`。
- 該 entitlement 含 development APNs 與 CloudKit；`Config/CoupleSpace-Info.plist` 仍有 `CKSharingSupported = true`。
- `CoupleSpace/G1/CloudKitSharingPoC.swift` 的 AppDelegate 會指定 CloudKit share scene delegate，並可接受 CKShare metadata。
- `CoupleSpace/App/AppLaunchOptions.swift`、`CoupleSpaceApp.swift` 與 `RootTabView.swift` 在正式 target 編譯 UI-test bypass／fixture branches。
- migration 035 的 `mark_all_relationship_interactions_read` 明列 debug-only，卻 grant 給所有 authenticated users。它只修改 caller 所屬 relationship cursor，未證明跨 relationship 越權。
- 尚未檢查簽署後 archive，不能只由 project 設定宣稱所有 symbol／capability 最終一定存在。

**修正方向**

- 分離 Debug／Release entitlements 與 build setting；Release 移除 CloudKit container/service、`CKSharingSupported` 與 CloudKit scene handler。
- 將 Push AppDelegate 與 production-used platform types 移出 PoC 檔；PoC 留在 Debug-only target／conditional compilation。
- 非 Debug configuration 的 auth／pairing bypass 必須 fail closed；fixture 搬到 `TestSupport/UITestScenarioFactory`。
- production migration 撤銷／移除 debug RPC，client Release contract 不再包含呼叫入口。

**關閉證據**

- 建立 Release archive 並檢查 signed entitlements、Info.plist、source／symbol 與啟動路徑。
- Release 不含 CloudKit capability／share handler、W1 低階工具、debug RPC client 或可生效的 UI-test bypass。
- Development APNs 與 production／TestFlight APNs environment 由各自 configuration 明確驗證。
- Debug UI tests 仍可由隔離的 TestSupport 執行，完整 iPhone suite 不退化。

## 裝置私密資料與通知生命週期

### HARD-PRIV-001：私密 local persistence protection

**目前證據**

- `ConversationOutboxStore`／`ConversationSnapshotStore` 將未同步或最近同步的聊天正文寫入 UserDefaults。
- `TodaySnapshotStore` 將 Moment／TogetherNow snapshot 寫入 UserDefaults。
- `SharedAppointmentOutboxStore`／`SharedAppointmentSnapshotStore` 保存 title、location、note 與 reminder metadata。
- 部分照片檔已使用 `.completeFileProtection` 或 `.completeFileProtectionUntilFirstUserAuthentication`，是應保留的基礎。
- App Lock 是 UI access gate，不應被描述成 UserDefaults／備份內容的加密保證；本輪沒有證明資料已外洩。

**修正方向**

- 先定義 local data classification：credential、pending private body、recreatable cache、media、preference。
- 私密正文改為 atomic file-backed store，明確設定 Data Protection class、backup exclusion、scope cleanup 與 upgrade migration。
- 需要背景 reconciliation 的 Outbox 與只在解鎖時使用的 cache 可採不同 protection class；不得為了最強 class 破壞已接受的可靠傳送。
- 只有威脅模型需要 App Lock 同時承諾額外 at-rest isolation 時，才評估 Keychain `ThisDeviceOnly` key 的 envelope encryption。

**關閉證據**

- 真機驗證 file attributes、鎖定／首次解鎖行為、backup inclusion、登出／換帳號／closing cleanup 與舊格式 migration。
- 離線冷啟動、Outbox retry、背景／前景恢復與低磁碟 failure 不退化。
- 測試 fixture 與 artifacts 不含真實私人內容。

### HARD-PUSH-001：logout 與 APNs routing cleanup

**目前證據**

- migration 009 已提供 `unregister_push_device`。
- client 註冊 current token，但 local signout 路徑未見對應 unregister；`send-w1-push` 亦未見對 APNs terminal token response 的 prune。
- 「登出後一定仍收到通知」仍是推論，須由 server row 與實際裝置路由驗證；現有 payload 泛化且不含正文，降低但不消除互動時間／badge 洩漏。

**修正方向**

- local signout 前 unregister current installation token；離線失敗時保存不含 token log 的 cleanup tombstone 並安全重試。
- 登入／換帳號重新綁定 installation；terminal APNs response 由 server worker 清除 stale row。
- 不把 `push_devices` 當成 Auth session／device inventory。

**關閉證據**

- 雙帳號／雙真機證明 current-device logout 只解除該 installation routing，不影響另一台仍登入裝置。
- 離線 logout、重登、token rotation、APNs terminal response 與重試不造成錯人、重複或永久 stale routing。

### HARD-LOCK-001：App Lock accessibility isolation

**目前證據**

- 鎖定 overlay 下方仍保留主內容；目前 `.accessibilityHidden` 沒有明確綁定 `isLocked`。
- 視覺遮蔽與 App switcher snapshot 已有真機基線，但 VoiceOver／Accessibility Inspector 是否能讀取或啟動底層控制仍未驗證。

**修正方向與關閉證據**

- 鎖定時對底層加上 accessibility exclusion 與 hit-testing isolation；解鎖後恢復正常焦點。
- 真機執行 VoiceOver swipe、focus、activation、background／foreground、驗證取消／失敗與裝置密碼 fallback。
- 未重現時記錄 OS、裝置、build、操作與 Accessibility Inspector／影片證據，不以靜態推論宣稱漏洞。

## 架構 hardening

### HARD-ARCH-001：收斂 composition root

`RootTabView` 目前直接 import／持有 Supabase client、建立多個 concrete service／model、建立大量 UI fixtures、直接呼叫 `relationship_unread_counts` RPC、設定 badge 並協調 model／network／push／scene lifecycle。這與「Presentation 不直接承擔同步、授權或重試」的既有方向有落差，但不等同現成安全漏洞。

最小順序：

1. 先搬移 UI fixture 到 Debug-only `TestSupport/UITestScenarioFactory`，不改 production behavior。
2. 把 unread DTO／RPC 移入 Data contract，由 Application model 管理 unread／badge state。
3. 由 `App/Composition` 建立 authenticated feature models；Root view 只接收 models 與 user intents。
4. 清理既有例外後加入 legacy allowlist boundary check，只阻止新增違規。

關閉需要 affected／full suite 通過，且 boundary check 證明 Presentation 不新增 `.rpc(` 或 Supabase concrete service construction。

### HARD-ARCH-002：Application／Platform／G1 邊界

- `PairingModel` import Supabase 並提供 concrete convenience initializer。
- `AppLockModel` 內含 `LAContext` platform implementation。
- `G1/` 同時容納歷史 PoC 與 production-used Auth、Push、AppDelegate、Supabase factory／photo processor，讓 Release ownership 不清楚。

先把 service contracts／application errors 放入 Application 邊界，Data／Platform 實作；將 production-used types 從 G1 PoC 搬至正式目錄。不得同時重寫已通過雙真機驗證的 Auth、Push 或 Outbox 行為，也不需要導入 DI framework。

### HARD-ARCH-003：typed lifecycle 與 unknown fail closed

Relationship status 目前由 String 從 Data 傳到 Application；Application 只特判已知 terminal states，未知值可能落入一般 paired／waiting 分支。目前 database constraint 限制既有值，因此這是 W14 schema 演進風險，不是已重現的越權。

在新增 lifecycle state 或正式 account-delete runtime 前：

- Domain 建立 `RelationshipLifecyclePhase`。
- Data 對 unknown raw value 回傳明確錯誤／安全 terminal presentation，不得當成 active。
- Application 使用 exhaustive switch。
- 新舊 client、unknown state、closing／archived 與 stale cache 加入 fail-closed regression。

### HARD-ARCH-004：正式 export v1 的平台中立 contract

W1 `PersonalArchiveExportPoC` 將 SwiftUI `FileDocument` 帶入 Data port 與 Application published state。W14-01 已接受 export v1 schema，但尚未完成 runtime；正式切片不得把 PoC UI type 當成 canonical export contract。

Data／Application 應回傳平台中立、versioned export package/result；Platform／Presentation 才負責 `FileDocument`、分享表、staging URL 與交付 UI。關閉證據須包含 contract tests、reference／checksum integrity、容量／中斷／清理與真機交付，而不只是一個可匯出的 SwiftUI type。

### HARD-ARCH-005：大檔、集中測試與 lifecycle 重複

`RootTabView.swift`、`MomentViews.swift`、`SupabaseMomentService.swift` 與 `AppSkeletonTests.swift` 已集中多個責任；Moment、Conversation、SharedAppointment、TogetherNow models 另有相似 generation／active work／waiter lifecycle state machine。

這項延後到 W14-09 全綠後：先按 feature／catalog ID 做機械式 file／test split，不改公開行為；再以既有 lifecycle regression 保護，逐一遷移到小型 `@MainActor` lifecycle gate。只有 boundary 仍持續失守時才評估 Swift Package modules。

## Tooling 與自動 enforcement

### HARD-TOOL-001：從人工規則轉成可阻擋 gate

**目前證據**

- 未見 checked-in `.github`／其他 CI workflow。
- `quality/scripts/run-full-automated-suite.sh` 已跑 pgTAP、schema lint、APNs helper、完整 iPhone scheme、Auth guard、Harness 與 diff hygiene，但未跑 architecture boundary、secret history、dependency vulnerability、Swift SAST、Release artifact 或全部 Edge Function tests。
- Deno Functions 使用浮動 major imports，未見 committed lockfile／import map；SwiftPM 則已有精確 resolution。
- gitleaks、Semgrep／CodeQL、OSV／Dependabot 等候選工具尚未成為 repo gate；不得把本文件中的建議寫成已安裝或 PASS。

**最小導入順序**

1. Boundary script 採 legacy allowlist，只阻擋新增的 Domain／Application／Presentation 違規。
2. 所有 Edge Functions 執行 test／lint，Deno dependencies pin 到已測版本並以 frozen lock 驗證。
3. PR 加入 secret scan、SwiftPM／Deno dependency scan、`xcodebuild analyze`，再評估支援 Swift 的 CodeQL／SAST。
4. 增加 warning-only strict-concurrency build 與 legacy baseline，先攔截新增 warning；這不承諾立即遷移 Swift 6。
5. macOS runner 執行 iPhone scheme；可使用 Supabase／Docker 的 runner 做 clean reset、pgTAP 與 schema lint。
6. Nightly 輪替完整 integration／UI matrix、ASan／TSan、migration replay、orphan／concurrency／idempotency tests。
7. Artifact 與結果保存版本、commit、tool version、exit、failure／skip；掃描警告不能只靠重跑消失。

## W14 與後續修正順序

### Checkpoint 1：W14 開發中

- 不把無關的大型重構混入目前 dirty 的 W14-02。
- 只有 finding 與當前切片是同一 trust boundary、會讓新行為不安全或會阻擋該切片時，才在同一 W14 slice 做最小修正。
- `HARD-ARCH-003` 必須在新增 lifecycle state／正式 account delete 前關閉。
- 任一 W14 slice 最後行為變更後仍依其 catalog ID 跑 focused tests、clean local reset／完整 suite、架構 diff review 與 security diff review；部署 migration 仍需獨立授權。

### Checkpoint 2：W14-02 或 W14-09 穩定後的 server／runtime hardening slice

下列是 server／runtime remediation 的優先順序；Release-only、push／lock 真機及 tooling blocker 保留在 Checkpoint 3，也可在相同邊界已穩定時提早獨立處理：

1. `HARD-SEC-001` 全域 GC worker authorization／concurrency。
2. `HARD-SEC-002` direct INSERT revoke 與 malicious-member tests。
3. `HARD-SEC-003` upload controls／orphan lifecycle（量測需要時才加入 reservation）。
4. `HARD-PRIV-001` local protected store 與 migration。
5. `HARD-ARCH-001`／`002` composition、test fixture 與 Platform ownership。
6. `HARD-ARCH-005` file／test split 與 lifecycle helper。

若上述修改會碰 migration 041 或尚未關閉的 Moment deletion state，等 W14-02 Gate B 綠燈後再開始，不以減少檔案數為理由擴張當前切片。

### Checkpoint 3：TestFlight Gate C 前

- 所有適用 Critical／High finding 必須為 `verified`，或以完整可重現證據記為 `not_reproduced`。
- `HARD-REL-001`／`002`、`HARD-PUSH-001`、`HARD-LOCK-001` 完成 Release archive／真機證據。
- 執行 milestone full-repository security assessment、Supabase linked ACL／advisor、完整 dependency／secret scan 與 OWASP MASVS 對照；掃描只是輸入，不取代修正與 runtime evidence。
- 同一候選完成既有 Gate C 的 clean database、upgrade、兩真機、APNs、App Lock、刪除／解除配對與 DR 項目。

## 融入 Gate A–D

| 階段 | 架構審核 | 資安檢測 | 必留證據 |
| --- | --- | --- | --- |
| Gate A：行為變更 | 記錄受影響 layer、dependency direction、`HARD-*` 與 catalog ID | 寫出資產、攻擊者、trust boundary、server enforcement；敏感路徑至少加入 anon／user C／malicious member／stale lifecycle 中適用的一種負向案例 | affected tests、affected build、diff、未解 finding |
| Gate B：切片／合併 | `code-reviewer` 檢查 composition、state ownership、async lifecycle、重試／冪等；最終 diff 再做 correctness review | Auth、RLS/RPC、Storage、Edge Function、push、local private store、export／delete、entitlement 變更執行 security diff review；跑 secret／dependency／SAST 等已採用 gate | 完整 suite、Harness、review findings、tool versions、failure／skip |
| Nightly／定期 | 固定 Xcode／Simulator runtime，clean migration replay 與完整 integration/UI matrix | SAST／dependency scan、全部 Edge tests、ASan／TSan、orphan／concurrency／stale-token tests | 可追蹤 CI artifacts；失敗不得長期忽略 |
| Gate C：TestFlight | Release archive、實際 entitlements／Info.plist、無 PoC／debug／test bypass | Privacy report、milestone deep scan、App Lock accessibility、local data protection、logout routing、兩真機／升級／恢復 | versioned release record；High 全部 `verified` 或具完整證據的 `not_reproduced` |
| Gate D：公開發布 | commit／build／schema／App Store version 可追溯 | production ACL／APNs、secrets rotation、DR restore、監控／回復方案 | production-like evidence；不得以 `WAIVED` 取代 Critical／High |

### Security-sensitive path triggers

下列任一路徑變更，Gate B 預設需要 architecture＋security diff review：

- `supabase/migrations/`、`supabase/functions/`、Storage policy、RLS、RPC、grant／revoke。
- Auth、pairing、relationship lifecycle、Outbox、local cache／snapshot、push、App Lock。
- export、delete、unpair、account delete、archive、tombstone、GC、DR。
- entitlements、Info.plist、build configuration、secrets、dependencies、logging／analytics。

## Skills 與 plugin routing

| 能力 | 使用時機 | 邊界 |
| --- | --- | --- |
| `andrej-karpathy-skills` | 每個實作切片開始，先收斂假設、最小範圍與驗收 | 不取代架構／資安專項 review |
| `code-reviewer` | 每個 coherent slice 完成後 | correctness、security、performance、maintainability 初審 |
| `/review-bugbot` | 合併前的最終 diff | 找一般邏輯與 regression，不取代 threat review |
| `/review-security` | 任何 security-sensitive path trigger | diff-oriented；不取代整庫、remote 或真機驗證 |
| `create-rule` | boundary／security trigger 已穩定後 | 先固化少量可執行規則，不把建議清單全寫成不可維護規則 |
| `create-skill` | hardening 流程重跑至少一次後 | 可建立 `couplespace-architecture-security-gate`，封裝 SSOT 讀取、風險分類、命令與輸出格式 |
| Codex Security plugin | milestone／TestFlight 前整庫 deep scan | 目前未安裝、未執行；採用前先驗證輸出品質與權限，不能因 plugin PASS 關閉 finding |

專案專用 skill 的預期步驟：

1. 讀取 `AGENTS.md`、`docs/ARCHITECTURE.md`、W14 contract、test catalog 與 release gates。
2. 將 diff 映射到 layer、asset、trust boundary、`HARD-*` 與 catalog ID。
3. 檢查 forbidden imports／RPC construction、Release debug surface、RLS／grant／search path、Storage、local persistence、payload／log privacy。
4. 依風險跑 affected gate 或完整 Gate B。
5. 分開輸出 confirmed facts、inferences、unknowns、blocking findings 與必要人工 gate。
6. 不自行部署、commit、push 或使用真實私人資料。

## Definition of done 與維護規則

一個 finding 只有同時滿足下列條件才能改為 `verified`：

1. 實作與 migration／configuration 已存在且 review 完成。
2. 最低可靠層 regression 能在修正前重現或證明原邊界，修正後通過。
3. 受影響的完整 automated gate 在最後行為變更後通過。
4. 需要 archive、Simulator、真機、linked／production 或營運證據者，已在正確環境通過。
5. Release record 記錄 commit、build、tool／OS／device、executions、failure、skip 與安全 artifact 位置。
6. finding register 更新 delivery，並在對應 finding 下新增以下關閉紀錄；未知欄位寫 `未記錄`，不可留白或推測。

開始修正時，先在 finding register 將 delivery 改為 `in_progress`，並在對應 remediation slice 真正建立測試位置後，才於 `quality/test-catalog.md` 分配不重複 runtime ID。不得預先填虛構測試、commit、部署或 PASS。

### 關閉紀錄格式

每個 `fixed`、`verified` 或 `not_reproduced` finding 都必須在其詳細段落末尾附上：

- Delivery：`未記錄`
- Closed／verified at：`未記錄`
- Remediation slice／catalog IDs：`未記錄`
- Commit／build／schema：`未記錄`
- Verification environment：`未記錄`
- Evidence／artifact：`未記錄`
- Residual risk／follow-up：`未記錄`

## 官方參考

- Apple：[Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)、[Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)、[Encrypting your app's files](https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files)、[Diagnosing memory, thread, and crash issues early](https://developer.apple.com/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early)
- Supabase：[Database Advisors](https://supabase.com/docs/guides/database/database-advisors)、[Database testing overview](https://supabase.com/docs/guides/local-development/testing/overview)、[Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- OWASP：[Mobile Application Security Verification Standard](https://mas.owasp.org/MASVS/)
- GitHub：[CodeQL for compiled languages](https://docs.github.com/en/code-security/concepts/code-scanning/codeql/codeql-for-compiled-languages)、[Push protection](https://docs.github.com/en/code-security/how-tos/secure-your-secrets/prevent-future-leaks/enable-push-protection)
- OpenAI：[Deep security scan](https://learn.chatgpt.com/use-cases/deep-security-scan)、[Scan code changes for security](https://learn.chatgpt.com/use-cases/scan-code-changes-for-security)、[Save workflows as skills](https://learn.chatgpt.com/use-cases/reusable-codex-skills)
