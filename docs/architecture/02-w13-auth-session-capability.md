---
title: W13 Supabase Auth session capability record
status: active
last_updated: 2026-08-19
---

# W13 Auth session capability record

## 結論（2026-08-19）

CoupleSpace 目前鎖定的 `supabase-swift 2.54.1` 可讓已登入 client 安全取得**目前** Supabase Auth session 的 user UUID、local expiry 與已驗證 JWT claims，並可執行 `local`、`global` 或 `others` scope 的 sign-out。SDK 型別有 optional `session_id` claim；但本次受控 Simulator A runtime probe 回報其目前 JWT **沒有** `session_id`。因此 client 不能保證取得可用的 current-session identity，更不能讓 client 列出該帳號的所有 session／裝置或以 `session_id` 指定撤銷其中一個 session。

因此本切片的可實作安全路徑只有「從目前 session 登出」或「保留目前 session，撤銷所有其他 session」。[PD-043](../decisions/product-decisions.md#pd-043裝置安全採登出其他所有登入不建立逐一裝置清單) 已接受後者作為 iPhone MVP 契約。沒有可信 session inventory 前，不得建立可逐一命名、選取或撤銷某支裝置的產品 UI。這是 W13／G12 的 stop condition，不是可由 `push_devices`、APNs token、Apple ID、`UIDevice.name`、本機 install ID 或 user 自報 device name 補上的缺口。

| 問題 | 結論 | 證據／限制 |
| --- | --- | --- |
| Client 可取得的目前 session identity | **不可保證** | `Session.user.id` 與 local expiry 可取得；`auth.getClaims()` 的 `session_id` 是 optional。受控 Simulator A 已觀察到缺少此 claim，因此沒有可安全顯示的 stable session identity。`sub` 只識別帳號，不識別 session。 |
| Client 可列出所有 session／裝置欄位 | **不可做** | SDK 的 public Auth surface 沒有 list-sessions API；目前 `Session` 僅是本機 current session 的 token、expiry 與 user。 |
| Admin API 可列出所有 session／裝置欄位 | **不可做（本產品邊界內）** | 2.54.1 Admin surface 可管理 users，`admin.signOut(jwt:scope:)` 也只依一個 access JWT 與 scope 操作；沒有以 `session_id` list／revoke 的 API。它需 secret key，client、App bundle、Edge Function 記錄與測試輸出都不得持有或回傳該 key。 |
| Session 與實體裝置一對一對應 | **不可做** | Auth session 是 token login，不是裝置 inventory；公開 session fields 沒有可信 device model、OS、push token、device name 或 install identity。一支裝置可有多個 session；同一 session 也不是實體裝置所有權的證明。 |
| 撤銷指定其他 session | **不可做** | `SignOutScope` 只有 `local`、`global`、`others`，沒有 target `session_id` 參數。 |
| 只撤銷所有其他 session | **可做；產品已採用，完整遠端 gate 未完成** | 在保留 session A 時呼叫 `try await client.auth.signOut(scope: .others)`；它會撤銷 A 之外的全部 Auth sessions，而非指定 B。 |
| 目前 session 保持有效 | **可做；A refresh 已實測，完整 RLS gate 未完成** | `others` 不清除呼叫端 local storage／不發呼叫端 `SIGNED_OUT`；仍須補 A 的三類受保護 RLS 讀取。 |

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
| `.global`（SDK 預設） | 此帳號所有 session | SDK 先移除 local session，並發出 `SIGNED_OUT` | 帳號完全登出；不是遺失單一裝置的預設操作。 |
| `.others` | 除目前 session 外的所有 session | 保留 current local session，且 current client 不發 `SIGNED_OUT` | 遺失裝置的最小安全能力；正式文案是「登出其他所有登入」。 |

`auth.admin.signOut(jwt:scope:)` 也只是同一個 `/logout?scope=` 語意的 server-only wrapper，不提供以 session UUID 指定 target 的能力。任何產品路徑不得把取得一個 HTTP success response 寫成「目標裝置已立即失效」。

## 撤銷、JWT 與 refresh 的時序契約

1. Supabase 撤銷受影響 session 的 refresh tokens；之後目標端不可用舊 refresh token 換取新 token。SDK 的 `refreshSession()`／存取到期 session 會失敗，受 server response 判定為 `sessionMissing` 時會清除該 client local Auth session。
2. 已簽發的 access JWT 是 stateless。撤銷不會讓它在到達 `exp` 前立即失效；在這段殘留時間內，普通 API／RLS 請求仍可能接受它。實際上限是該 project Auth settings 的 JWT expiry，不能以 SDK 或單次 logout 回應推定。
3. `supabase-swift` 預設 `autoRefreshToken = true`；在 iOS active 時開始 refresh loop、`willResignActive` 時停止。背景／被終止的 App 不會因撤銷主動醒來或收到可靠的 client-side Auth event。
4. 目標 session 首次可**可靠**判定失去遠端授權的時點，是其 access JWT 到期後，下一次 refresh 或需要 server 驗證的受保護請求被拒絕，且 client 清除 local Auth session之後。這不是撤銷呼叫返回的時點，也不是 App 在背景、離線或只看 cache 時。
5. refresh token rotation 的一般規則是每次 refresh 取得新 pair；token reuse detection 預設允許 10 秒 reuse window，或在可證明 parent token 的容錯鏈中回傳 active token。非例外的 reuse 會終止整個 session。這是 token 被重放的防護，不是針對遺失實體裝置的即時撤銷機制；本切片不變更 reuse interval、detection 或任何 production Auth setting。

### 產品資料與本機畫面的邊界

- Auth session revoke 不解除配對、不改 `relationship`／membership、不刪共同歷史、不刪任一 owner-only personal archive，也不得產生 deletion tombstone。這延續切片 6 與 [PD-033](../decisions/product-decisions.md#pd-033換機採遠端同步恢復，不要求手動聊天備份)。
- server 端 relationship RLS 仍是遠端資料的唯一授權防線。撤銷真正被觀察到後，目標端的 relationship、共同內容與個人封存讀取必須被拒絕；驗證時需對三類資料各做一次受保護讀取，而非只檢查 UI 或 logout response。
- 已下載到遺失裝置的本機 snapshot／照片快取不會被遠端 Auth revoke 回收。App Lock 只保護本機畫面，亦不會撤銷 Auth。W13 不得承諾遠端操作可立即擦除離線裝置上既有內容；若產品要提升此保證，需另行接受本機加密／清除／重新驗證設計，不能在本切片偷渡。
- 尚未到期的 JWT 仍可讓裝置在殘留窗口讀取遠端資料。因此「遺失裝置已不能讀取」的 release evidence 必須記錄 JWT `exp`、等待或受控 expiry 策略、refresh rejection 與三類資料 RLS rejection；不能只刪本機 token、force-quit 或確認 A 的 response。

## Apple Sign In 邊界

Apple Sign In 的 Apple credential／Apple account session 與 Supabase Auth session 是不同控制：Apple credential 讓 App 向 Supabase 建立或恢復同一 Supabase user；Supabase `signOut(scope: .others)` 只撤銷受影響的 Supabase refresh session，不能登出 Apple account、撤銷 Apple credential，或阻止使用者日後再次以 Apple Sign In 建立新 Supabase session。反之，App Lock、APNs routing 與 Apple account presence 都不是 Supabase session inventory。

在目標裝置重新開啟後，先前 Supabase refresh 必須失敗並回到登入入口；使用者若完成 Apple Sign In（Apple SSO 可能讓此流程很快）是**新的** Auth session，不是被撤銷 session 復活。驗證要記錄此重新驗證邊界，且不得把 Apple `user` identifier、Apple ID email 或裝置名稱寫進產品資料作為撤銷依據。

## 可實作契約與 stop condition

PD-043 已接受下列最小能力；正式帳號設定提供二次確認後的操作，但不建立 registry、migration、Edge Function 或變更 production Auth policy：

```swift
try await client.auth.signOut(scope: .others)
```

正式 UI／文案使用「登出其他所有登入」，在操作前明確告知會影響全部其他登入、目前裝置保持登入、需要 Apple 重新驗證，且未到期 JWT 仍有最多一個 project JWT expiry 的殘留窗口。SDK success 只能顯示「已送出」，不能宣稱遠端裝置已立即失效。完成條件仍是 A 保持可 refresh／讀取，B 在 expiry 後 refresh／RLS 讀取被拒絕，且 relationship／共同歷史／兩人的個人封存資料均未改變；正式入口存在不會關閉此 gate。

**Stop condition：** 若產品需求堅持可信的每裝置清單、裝置名稱、last-seen，或撤銷指定其他 session，W13 必須停止在此並重新請求產品／架構決策。

PD-043 已選擇「所有其他 session」的最小安全模型。若未來改為要求逐一管理，須另案設計 server-verified device-session registry（需 threat model、data minimization、伺服器授權、re-auth／revocation audit、遺失／重裝／多 session 情境、RLS 與 migration review）。

不得以 `push_devices` 或任何 client 自報 identifier 偽造 inventory，也不得把 `.others` 包裝成逐一裝置管理。

## SESSION-001：受控雙 session 人工驗證

此 gate 需要兩支真實 iPhone（或兩個確實隔離的 iOS client container）和同一個**可清理的 Supabase test project**。Apple Sign In 與已登入 session 無法由 deterministic unit test 取代；不可使用 production project、真人 relationship、service-role secret 或真實私密內容。

Debug 測試專用 build 可在 Xcode launch arguments 明確加入 `--session-capability-probe` 後，從 paired／closing／archived 畫面右上角僅在 `DEBUG` 出現的「W13 session 測試」看到 probe。它顯示 local access JWT 到期時間；只有 issuer 實際提供 `session_id` 時才顯示其單向 12 碼指紋，並提供 current-session refresh 與確認後的 `.others` 呼叫；沒有 raw session ID、JWT、refresh token、session inventory 或指定裝置選項。另有唯讀 protected-data probe，直接向 test project 查詢可見 relationship／active membership／`shared_items`／owner-only personal archive 的 metadata、單向指紋與筆數，不讀正文且不使用本機 cache。本次 Simulator A 不顯示 session 指紋是預期可記錄的 capability result，不可用其他 identifier 代替。完整清單見 [SESSION-001 手動驗證](../../quality/manual/session-capability.md)。2026-08-19 受控三 Simulator 已使 PD-043 接受的 all-others App 路徑達到 **PASS**；本機 deterministic test 仍只證明 probe 契約，不能取代該人工證據。

### 2026-08-19 受控三 Simulator 完成結果

- 同一測試帳號的 iPhone 17 Pro Simulator A 與 iPhone 17 Pro Max Simulator B 均取得 current session；11:20 兩台手動 refresh 成功且 local expiry 都更新為 12:20。兩台 JWT 及 B 重新 Apple 驗證後的 JWT 都缺少 optional `session_id`，故沒有可安全比對的 stable session identity。
- 11:21 A 從正式「帳號設定 → 登入安全」送出 `.others`，畫面只回報「已送出」；11:22 A 再次 refresh 成功且 expiry 更新為 12:22，證明呼叫端 Auth session 未被誤撤銷。
- B 回前景後先顯示既有 relationship 畫面；11:23 在進入「我們／帳號設定」的同一時段，系統 log 記錄一個 Supabase request 收到 HTTP 403，約 13 ms 後發生 Keychain `SecItemDelete`，App 回到 Apple 登入。因 HTTP/2 connection 被 Auth／REST 請求共用，log 沒有保留該 task 的精確 endpoint；因此只記錄「前景／受保護操作期間收到 403 後 SDK 清除舊 local session」，不宣稱帳號設定觸發登出，也不把此單次觀察推廣為 access JWT 在 `exp` 前必然失效。
- 11:26 B force-quit 後正常重開仍停在 Apple 登入，舊 session 沒有恢復；11:27 B 完成 Apple 重新驗證後，A、B 顯示相同八碼帳號識別與相同 relationship 名稱資料，沒有重新配對。此證明重新驗證建立可用登入狀態且帳號／relationship identity 延續；缺少 `session_id` 時，不把它寫成可比對的「新 session ID」。
- 第二輪加入 iPhone 17 Simulator C，以另一位 relationship owner P 登入；A／B 維持同一 owner S 的兩個 session。三台撤銷前後都由 remote-only probe 讀到 active relationship 指紋 `1971C4CFD7A1`、active members `2` 與無私密 `shared_items` count `1`。A／B 讀到 S 的 archive 指紋 `9FF517E636D8`，C 讀到 P 的不同 archive 指紋 `48EA519E7187`；兩份 archive 都指向既有 archived relationship 指紋 `30BE04486C70` 且 item count 都是 `4`。因此不需對目前 relationship 執行 intentional unpair。
- A 從正式入口送出 `.others` 後，A 與不同 user 的 C 都能 refresh，且 relationship／shared item／各自 archive metadata 與 count 完全不變。B 在撤銷後、顯示 access JWT `exp` 2:28 PM 時仍可於 1:32 PM 執行相同 remote read，直接證明既有 JWT 的殘留窗口；B 未再人工 refresh，於 2:26 PM 自動回到 Apple 登入。此時序符合 SDK 在到期前 proactive refresh、因 refresh token 已撤銷而清除 local session，但沒有保存精確 Auth endpoint，因此不宣稱 access JWT 本身於 2:26 提前失效。
- B force-quit／重開仍停在 Apple 登入；重新以 S 完成 Apple 驗證後取得新的 `exp`，背景／前景後 refresh 與 remote read 正常。最終 A／B 仍讀到相同 S account、active relationship、shared count 與 S archive；C 仍讀到 P 的不同 archive，沒有 closing、archived、重新配對、內容清空或 archive 改寫。未保留或重播 raw JWT；這是刻意的隱私邊界，不影響已接受 App 路徑 PASS，也不形成即時 token introspection 保證。

## 官方與版本化來源

- [Supabase User Sessions](https://supabase.com/docs/guides/auth/sessions)：session、`session_id`、JWT expiry、session lifetime、refresh rotation／reuse detection 與 access JWT 殘留窗口。
- [Supabase Signing out](https://supabase.com/docs/guides/auth/signout)：`global`／`local`／`others` scope、refresh token 刪除及 access JWT 到期前仍有效。
- [Supabase Swift sign out reference](https://supabase.com/docs/reference/swift/auth-signout) 與 [supabase-swift 2.54.1 source](https://github.com/supabase/supabase-swift/tree/v2.54.1/Sources/Auth)：本專案鎖定的 Swift API surface。
- [Supabase managing user data](https://supabase.com/docs/guides/auth/managing-user-data)：撤銷／刪除不會追溯使已簽發 access JWT 即刻失效；需要強保證時必須在敏感操作額外驗證 session。
