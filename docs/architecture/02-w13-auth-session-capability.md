---
title: W13 Supabase Auth session capability record
status: active
last_updated: 2026-08-19
---

# W13 Auth session capability record

## 結論（2026-08-19）

CoupleSpace 目前鎖定的 `supabase-swift 2.54.1` 可讓已登入 client 安全取得**目前** Supabase Auth session 的 user UUID、local expiry 與已驗證 JWT claims，並可執行 `local`、`global` 或 `others` scope 的 sign-out。SDK 型別有 optional `session_id` claim；但本次受控 Simulator A runtime probe 回報其目前 JWT **沒有** `session_id`。因此 client 不能保證取得可用的 current-session identity，更不能讓 client 列出該帳號的所有 session／裝置或以 `session_id` 指定撤銷其中一個 session。

SDK source 證明 `.others` API surface 存在，受控 Simulator 也曾提供 preflight 證據；但 2026-08-19 的兩支真實 iPhone `SESSION-001` 中，A 呼叫 `.others` 後 B 仍成功 manual refresh，Access JWT expiry 更新為 9:44 PM，Auth session 與基線資料保留。因此 preflight 不足以支持可交付的遠端安全承諾。[PD-044](../decisions/product-decisions.md#pd-044mvp-移除-session-inventory-與遠端撤銷只保留目前裝置登出) 已取代 PD-043：MVP 只保留目前裝置的 `.local` 登出，允許同帳號多裝置使用同一 server SSOT，不提供 inventory 或任何遠端 revoke。不得用 `push_devices`、APNs token、Apple ID、`UIDevice.name`、本機 install ID 或 user 自報 device name 補造缺口。

| 問題 | 結論 | 證據／限制 |
| --- | --- | --- |
| Client 可取得的目前 session identity | **不可保證** | `Session.user.id` 與 local expiry 可取得；`auth.getClaims()` 的 `session_id` 是 optional。受控 Simulator A 已觀察到缺少此 claim，因此沒有可安全顯示的 stable session identity。`sub` 只識別帳號，不識別 session。 |
| Client 可列出所有 session／裝置欄位 | **不可做** | SDK 的 public Auth surface 沒有 list-sessions API；目前 `Session` 僅是本機 current session 的 token、expiry 與 user。 |
| Admin API 可列出所有 session／裝置欄位 | **不可做（本產品邊界內）** | 2.54.1 Admin surface 可管理 users，`admin.signOut(jwt:scope:)` 也只依一個 access JWT 與 scope 操作；沒有以 `session_id` list／revoke 的 API。它需 secret key，client、App bundle、Edge Function 記錄與測試輸出都不得持有或回傳該 key。 |
| Session 與實體裝置一對一對應 | **不可做** | Auth session 是 token login，不是裝置 inventory；公開 session fields 沒有可信 device model、OS、push token、device name 或 install identity。一支裝置可有多個 session；同一 session 也不是實體裝置所有權的證明。 |
| 撤銷指定其他 session | **不可做** | `SignOutScope` 只有 `local`、`global`、`others`，沒有 target `session_id` 參數。 |
| 只撤銷所有其他 session | **SDK API 存在；產品已移除** | `.others` 的 Simulator preflight 曾成功，但真機 `SESSION-001` 中 B 在 A 呼叫後仍取得新的 JWT expiry；無法可靠承諾 refresh 已撤銷。正式 UI 不呼叫或顯示此能力。 |
| 目前裝置登出 | **可做；MVP 採用** | `.local` 只清除呼叫端目前 session；仍須在最終候選驗證同帳號另一台不受影響，以及登出裝置重新登入後由 server SSOT 恢復。 |

## 已驗證的 API 契約

本記錄以官方文件、鎖定的 SDK 原始碼及無私密來源 probe 交叉檢查。執行：

```sh
quality/scripts/verify-session-capability.sh
```

此 probe 不使用網路、不讀取任何 project URL／publishable key／JWT／refresh token，也不寫入 Auth 設定。它驗證 `Package.resolved` 的 `2.54.1` 與本機 Xcode 解析出的 Auth source：`SignOutScope` 僅有三個 scope、存在 `session_id` claim、iOS active／inactive lifecycle refresh wiring 與沒有 public session-list method。SDK 更新後 probe 失敗即表示本記錄必須重新評估，不能沿用本結論。

### Current session：可用欄位與顯示規則

| 來源 | 可取得欄位 | 可作為產品「裝置」欄位嗎？ |
| --- | --- | --- |
| `Session` | `accessToken`、`refreshToken`、`tokenType`、`expiresAt`、`expiresIn`、`user` | 否。兩種 token 是敏感憑證，禁止顯示、log、分析、截圖或寫入資料庫。expiry 只描述 JWT，不描述一支裝置。 |
| `Session.user`／`JWTClaims.sub` | Supabase Auth user UUID | 否。它識別帳號，不區分同帳號的 session。 |
| `JWTClaims.sessionId` | JWT 的 optional `session_id` UUID | 否。SDK 可解碼該 optional claim，但受控 Simulator A 的目前 JWT 未帶它；不可假設它存在。即使存在，也只能作短生命週期、server-side session correlation 的技術識別；不得向使用者顯示為裝置、不得成為 client 自報 registry key，且目前無 API 用它挑選撤銷 target。 |
| `JWTClaims.exp`／`iat`／`aal` | token 到期／簽發時間與 assurance level | 否。可做本次驗證時序證據，不能推論裝置型號、最後活躍時間或物理持有人。 |

若發行端 JWT 帶有 `session_id`，相同值只表示 JWT claim 指向同一 Auth session；它不是授權 bearer token，卻仍是可跨 log 關聯的敏感技術識別。本次 runtime evidence 顯示不能把它當成測試前置條件。人工驗證紀錄只保留「claim 是否存在」及時間，不保存 raw `session_id`、JWT 或 refresh token。

### Scope 契約

| Scope | 遠端受影響範圍 | 呼叫端 local session | CoupleSpace 可用情境 |
| --- | --- | --- | --- |
| `.local` | 目前 session | SDK 先移除 local session，並發出 `SIGNED_OUT` | 一般「在此裝置登出」。 |
| `.global`（SDK 預設） | 此帳號所有 session | SDK 先移除 local session，並發出 `SIGNED_OUT` | SDK 能力記錄；MVP 不提供此產品操作。 |
| `.others` | 除目前 session 外的所有 session | 保留 current local session，且 current client 不發 `SIGNED_OUT` | SDK／歷史 probe 能力記錄；PD-044 已從正式產品移除。 |

`auth.admin.signOut(jwt:scope:)` 也只是同一個 `/logout?scope=` 語意的 server-only wrapper，不提供以 session UUID 指定 target 的能力。任何產品路徑不得把取得一個 HTTP success response 寫成「目標裝置已立即失效」。

## 歷史 `.others` probe 的時序模型（非正式產品契約）

下列是切片 7 根據官方契約建立的 probe 預期，保留作為真機失敗的比較基準；它不再授權正式 UI 或發布聲明：

1. Supabase 文件描述 `.others` 會撤銷受影響 session 的 refresh tokens；之後目標端理論上不可用舊 refresh token 換取新 token。SDK 的 `refreshSession()`／存取到期 session 失敗且 server response 判定為 `sessionMissing` 時會清除該 client local Auth session。
2. 已簽發的 access JWT 是 stateless。撤銷不會讓它在到達 `exp` 前立即失效；在這段殘留時間內，普通 API／RLS 請求仍可能接受它。實際上限是該 project Auth settings 的 JWT expiry，不能以 SDK 或單次 logout 回應推定。
3. `supabase-swift` 預設 `autoRefreshToken = true`；在 iOS active 時開始 refresh loop、`willResignActive` 時停止。背景／被終止的 App 不會因撤銷主動醒來或收到可靠的 client-side Auth event。
4. 目標 session 首次可**可靠**判定失去遠端授權的時點，是其 access JWT 到期後，下一次 refresh 或需要 server 驗證的受保護請求被拒絕，且 client 清除 local Auth session之後。這不是撤銷呼叫返回的時點，也不是 App 在背景、離線或只看 cache 時。
5. refresh token rotation 的一般規則是每次 refresh 取得新 pair；token reuse detection 預設允許 10 秒 reuse window，或在可證明 parent token 的容錯鏈中回傳 active token。非例外的 reuse 會終止整個 session。這是 token 被重放的防護，不是針對遺失實體裝置的即時撤銷機制；本切片不變更 reuse interval、detection 或任何 production Auth setting。

### 產品資料與本機畫面的邊界

- 本機登出不解除配對、不改 `relationship`／membership、不刪共同歷史、不刪任一 owner-only personal archive，也不得產生 deletion tombstone。這延續切片 6 與 [PD-033](../decisions/product-decisions.md#pd-033換機採遠端同步恢復，不要求手動聊天備份)。歷史 remote-revoke probe 也不得以資料變動作為成功訊號。
- server 端 relationship RLS 仍是遠端資料的唯一授權防線。若未來另案重新接受 remote revoke，必須觀察目標端的 relationship、共同內容與個人封存讀取被拒絕；只檢查 UI 或 logout response 不足以恢復該能力。
- 已下載到遺失裝置的本機 snapshot／照片快取不會被遠端 Auth revoke 回收。App Lock 只保護本機畫面，亦不會撤銷 Auth。W13 不得承諾遠端操作可立即擦除離線裝置上既有內容；若產品要提升此保證，需另行接受本機加密／清除／重新驗證設計，不能在本切片偷渡。
- 尚未到期的 JWT 仍可能讓裝置在殘留窗口讀取遠端資料。MVP 不宣稱「遺失裝置已不能讀取」；若未來重開此承諾，release evidence 必須記錄 JWT `exp`、refresh rejection 與三類資料 RLS rejection，不能只刪本機 token、force-quit 或確認呼叫端 response。

## Apple Sign In 邊界

Apple Sign In 的 Apple credential／Apple account session 與 Supabase Auth session 是不同控制：Apple credential 讓 App 向 Supabase 建立或恢復同一 Supabase user；MVP 的 `.local` 只登出目前裝置的 Supabase session，不能登出 Apple account、撤銷 Apple credential，或阻止使用者日後再次以 Apple Sign In 建立新 Supabase session。反之，App Lock、APNs routing 與 Apple account presence 都不是 Supabase session inventory 或遠端撤銷證據。

目前裝置執行 `.local` 後，強制結束並重開仍須停在登入入口；使用者若完成 Apple Sign In（Apple SSO 可能讓此流程很快）會重新建立 Auth session，並由同一 server SSOT 恢復既有授權資料。驗證要記錄此重新驗證邊界，且不得把 Apple `user` identifier、Apple ID email 或裝置名稱寫進產品資料作為 session identity。

## PD-044 正式契約與 stop condition

正式帳號設定只提供目前裝置的 `.local` 登出：

```swift
try await client.auth.signOut(scope: .local)
```

切片 8 保留的 Auth service 只負責穩定完成 local-first 登出，並避免晚到 refresh／Auth event 將已登出的 authenticated UI 恢復。產品不顯示目前或其他 session 的技術欄位，不提供 `.others`／`.global`，也不新增 registry、migration、Edge Function 或 production Auth policy。兩支裝置以同一帳號登入時，各自的 local session 互相獨立，但共同內容與授權資料仍來自同一 server SSOT。

**Stop condition：** 若未來重新要求可信 inventory、裝置名稱、last-seen、所有其他或指定 session 的遠端撤銷，必須另立產品／架構決策與 server-verified contract；在 threat model、data minimization、伺服器可觀察結果、migration／RLS 與兩支真實 iPhone 證據完成前，不得恢復既有 `.others` UI。縮短 JWT expiry、`push_devices` 或任何 client 自報 identifier 都不能通過此 gate。

## SESSION-001：retired stable ID 與真機 FAIL

`SESSION-001` 原本驗證 PD-043 的 all-others 路徑。PD-044 已移除該產品能力，因此此 ID 不再阻擋 G12／W13，正式候選固定記為 `NOT_APPLICABLE (REMOVED)`；歷史結果仍保留，不能改寫成 PASS。現行整合步驟見 [W13-INTEGRATION-001](../../quality/manual/w13-integration.md)。

2026-08-19 兩支真實 iPhone 的已知證據：

- A、B 的同帳號基線與 A 不受影響檢查正確；B 在 A 送出 `.others` 後仍以既有 JWT 成功讀取受保護資料。
- B 手動觸發 refresh 後成功取得新 token，Access JWT expiry 更新為 **9:44 PM**；Auth session 仍存在，受保護資料基線未改變。這是 refresh 成功，不是既有 access JWT 的殘留窗口。
- 原 Access JWT expiry 為基線截圖所示的 **9:29 PM**；A／B 操作的精確時間、logout／refresh HTTP status、Auth audit events、test-project alias、build、iOS 與可驗證 `session_id`：**未記錄**。
- 判定：原 PD-043 all-others 契約為 **FAIL**。未診斷的 endpoint、in-flight refresh 或 session-family 原因不影響產品移除決策；也不得據此宣稱 `.others` 永遠無效。

### 2026-08-19 受控三 Simulator 歷史 preflight

- 同一測試帳號的 iPhone 17 Pro Simulator A 與 iPhone 17 Pro Max Simulator B 均取得 current session；11:20 兩台手動 refresh 成功且 local expiry 都更新為 12:20。兩台 JWT 及 B 重新 Apple 驗證後的 JWT 都缺少 optional `session_id`，故沒有可安全比對的 stable session identity。
- 11:21 A 從正式「帳號設定 → 登入安全」送出 `.others`，畫面只回報「已送出」；11:22 A 再次 refresh 成功且 expiry 更新為 12:22，證明呼叫端 Auth session 未被誤撤銷。
- B 回前景後先顯示既有 relationship 畫面；11:23 在進入「我們／帳號設定」的同一時段，系統 log 記錄一個 Supabase request 收到 HTTP 403，約 13 ms 後發生 Keychain `SecItemDelete`，App 回到 Apple 登入。因 HTTP/2 connection 被 Auth／REST 請求共用，log 沒有保留該 task 的精確 endpoint；因此只記錄「前景／受保護操作期間收到 403 後 SDK 清除舊 local session」，不宣稱帳號設定觸發登出，也不把此單次觀察推廣為 access JWT 在 `exp` 前必然失效。
- 11:26 B force-quit 後正常重開仍停在 Apple 登入，舊 session 沒有恢復；11:27 B 完成 Apple 重新驗證後，A、B 顯示相同八碼帳號識別與相同 relationship 名稱資料，沒有重新配對。此證明重新驗證建立可用登入狀態且帳號／relationship identity 延續；缺少 `session_id` 時，不把它寫成可比對的「新 session ID」。
- 第二輪加入 iPhone 17 Simulator C，以另一位 relationship owner P 登入；A／B 維持同一 owner S 的兩個 session。三台撤銷前後都由 remote-only probe 讀到 active relationship 指紋 `1971C4CFD7A1`、active members `2` 與無私密 `shared_items` count `1`。A／B 讀到 S 的 archive 指紋 `9FF517E636D8`，C 讀到 P 的不同 archive 指紋 `48EA519E7187`；兩份 archive 都指向既有 archived relationship 指紋 `30BE04486C70` 且 item count 都是 `4`。因此不需對目前 relationship 執行 intentional unpair。
- A 從正式入口送出 `.others` 後，A 與不同 user 的 C 都能 refresh，且 relationship／shared item／各自 archive metadata 與 count 完全不變。B 在撤銷後、顯示 access JWT `exp` 2:28 PM 時仍可於 1:32 PM 執行相同 remote read，直接證明既有 JWT 的殘留窗口；B 未再人工 refresh，於 2:26 PM 自動回到 Apple 登入。此時序符合 SDK 在到期前 proactive refresh、因 refresh token 已撤銷而清除 local session，但沒有保存精確 Auth endpoint，因此不宣稱 access JWT 本身於 2:26 提前失效。
- B force-quit／重開仍停在 Apple 登入；重新以 S 完成 Apple 驗證後取得新的 `exp`，背景／前景後 refresh 與 remote read 正常。最終 A／B 仍讀到相同 S account、active relationship、shared count 與 S archive；C 仍讀到 P 的不同 archive，沒有 closing、archived、重新配對、內容清空或 archive 改寫。未保留或重播 raw JWT；這是 SDK API／資料不變的歷史 preflight，不支持正式 `.others` 產品路徑，也不形成即時 token introspection 保證。

## 官方與版本化來源

- [Supabase User Sessions](https://supabase.com/docs/guides/auth/sessions)：session、`session_id`、JWT expiry、session lifetime、refresh rotation／reuse detection 與 access JWT 殘留窗口。
- [Supabase Signing out](https://supabase.com/docs/guides/auth/signout)：`global`／`local`／`others` scope、refresh token 刪除及 access JWT 到期前仍有效。
- [Supabase Swift sign out reference](https://supabase.com/docs/reference/swift/auth-signout) 與 [supabase-swift 2.54.1 source](https://github.com/supabase/supabase-swift/tree/v2.54.1/Sources/Auth)：本專案鎖定的 Swift API surface。
- [Supabase managing user data](https://supabase.com/docs/guides/auth/managing-user-data)：撤銷／刪除不會追溯使已簽發 access JWT 即刻失效；需要強保證時必須在敏感操作額外驗證 session。
