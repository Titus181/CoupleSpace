# SESSION-001：Supabase Auth session capability

本清單驗證 PD-043 接受的 W13 路徑：「從 session A 執行 `.others`，保留 A 並撤銷所有其他 session」。它不是逐一裝置撤銷驗收；若需求改為清單或指定 target，依 [W13 capability record](../../docs/architecture/02-w13-auth-session-capability.md) 停止並另立產品／架構決策。

## 2026-08-19 三台 Simulator 交接卡

這是切片 7 完成時的測試環境對照，供下一個開發 session 辨識現有 fixture。`S`、`P` 都是測試帳號的邏輯代號；不在 Git 記錄 Apple 帳號姓名、email、Apple identifier、raw Supabase user UUID、JWT 或 refresh token。Simulator 的 Auth／Apple 登入狀態可能在重開、token refresh 或手動切換帳號後改變，因此下表是交接基線，不是永久授權真相。

| 裝置代號 | Simulator／iOS | UDID | 登入帳號 | W13 角色 | 切片完成時狀態 |
| --- | --- | --- | --- | --- | --- |
| A | iPhone 17 Pro／iOS 26.5 | `98B44B29-01D7-4750-8597-D75599F34554` | `S` | `.others` 呼叫端／應保留的目前 session | 已登入；撤銷後 refresh 與 remote read 正常。 |
| B | iPhone 17 Pro Max／iOS 26.5 | `5B23A61A-F3DA-48AB-BD68-FBB1CCE9449D` | `S` | 其他 session／撤銷觀察目標 | 舊 session 已被拒並清除；已重新以 Apple 驗證建立可用 session，背景／前景後 refresh 與 remote read 正常。 |
| C | iPhone 17／iOS 26.5 | `B1205133-D87F-4AA4-9F39-DAF07403146A` | `P` | relationship 另一位 owner／不同 user 控制組 | 已登入；A 執行 `S` 的 `.others` 前後皆不受影響。 |

帳號與資料對應：

| 邏輯帳號 | 使用裝置 | 與目前 relationship 的關係 | 本人舊個人封存 |
| --- | --- | --- | --- |
| `S` | A、B | active owner | archive 指紋 `9FF517E636D8`；來源 relationship 指紋 `30BE04486C70`；item count `4`。 |
| `P` | C | active owner／`S` 的另一位 relationship member | archive 指紋 `48EA519E7187`；來源 relationship 指紋 `30BE04486C70`；item count `4`。 |

三台在切片完成時都可讀到目前 active relationship 指紋 `1971C4CFD7A1`、active members `2`、`shared_items` count `1`。這個 active relationship 與兩份 personal archive 所屬的舊 archived relationship `30BE04486C70` 是不同資料；不得因驗證 session 而解除目前配對、刪除封存或重新建立 relationship。

A、B 是同一個 Supabase user `S` 的兩個隔離 local Auth container，但本次 JWT 都沒有 optional `session_id`。因此只能把 A／B 當作測試流程角色，不能宣稱已取得兩個可列出、可穩定顯示或可指定撤銷的 session identity。C 的 `P` 是不同 Supabase user；C 不是 `.others` 的撤銷目標。

下一個 session 若要恢復 probe，可先確認三台仍為 Booted，再以各自 UDID 啟動：

```sh
xcrun simctl launch 98B44B29-01D7-4750-8597-D75599F34554 com.titus.CoupleSpace --session-capability-probe
xcrun simctl launch 5B23A61A-F3DA-48AB-BD68-FBB1CCE9449D com.titus.CoupleSpace --session-capability-probe
xcrun simctl launch B1205133-D87F-4AA4-9F39-DAF07403146A com.titus.CoupleSpace --session-capability-probe
```

接手後先在 A／B／C 各按一次「讀取遠端受保護資料」，核對上述 relationship、member、shared item 與各自 archive 基線。若任何一台回到 Apple 登入、帳號角色不同或數值不符，先記錄新狀態並重建基線；不要直接再按「登出所有其他 session」。

## 前置條件

- 使用可清理的 Supabase **test project**、同一個可重複登入的測試 Apple account、兩支真實 iPhone A／B（或兩個隔離 iOS client container）。不得連線 production。
- 在 Xcode 的測試專用 Run scheme → **Arguments Passed On Launch** 加入 `--session-capability-probe`，確認該 scheme 的 Debug 設定指向 test project 後才安裝 A、B。沒有此 argument，手機上不會出現 probe；一般 Debug 與 Release build 也不會出現。
- A、B 都安裝同一個 Debug build，且能在本機執行 `quality/scripts/verify-session-capability.sh`；記錄 SDK version、build、iOS、測試時間與 test-project 名稱（不記 URL／key）。
- 以同一 Supabase user 在 A、B 分別登入，建立兩個獨立 session。若只有 relationship 的兩個既有 Apple 測試帳號可用，可依下方「兩帳號、原 relationship 不保留」流程分階段建立共同 fixture 與兩份 owner-only archive；不得假裝 active relationship 與尚未建立的同 relationship archive 能同時存在。
- 不在筆記、截圖、Xcode console、log 或 issue 貼入 access JWT、refresh token、raw `session_id`、Apple identifier、APNs token、URL、publishable key 或內容正文。只記錄 A／B 的 session identity 是否存在、若兩邊皆存在時是否相異、JWT `exp` 時間與 pass/fail。
- 在 test project Auth settings 記下既有 JWT expiry；**不**為本驗證修改 session policy、rotation、reuse detection、single-session 或 production 設定。

## 兩帳號、原 relationship 不保留的受控流程

此流程只需要兩個既有 Apple／Supabase user：`S` 是要驗證 all-others 的帳號，`P` 是 relationship 的另一位 owner。A、B 是兩個隔離 Simulator。流程會把原 relationship 永久轉成 archived；兩份 personal archive 必須保留到整輪證據完成，期間不要刪除封存或建立新配對。

### 0. 安裝與每次重開 probe

1. 確認 Debug scheme 指向 Supabase test project，且已啟用 `--session-capability-probe`。先完成一次 build／install；不需要為每次切換帳號重新 build。
2. Xcode 只會把 launch argument 傳給它啟動的那台 Simulator。若手動重開後看不到右上角「W13 session 測試」，先終止再以 `simctl` 帶 argument 啟動；不得因此改成一般 Debug 永久顯示：

   ```sh
   xcrun simctl terminate 98B44B29-01D7-4750-8597-D75599F34554 com.titus.CoupleSpace
   xcrun simctl launch 98B44B29-01D7-4750-8597-D75599F34554 com.titus.CoupleSpace --session-capability-probe
   xcrun simctl terminate 5B23A61A-F3DA-48AB-BD68-FBB1CCE9449D com.titus.CoupleSpace
   xcrun simctl launch 5B23A61A-F3DA-48AB-BD68-FBB1CCE9449D com.titus.CoupleSpace --session-capability-probe
   ```

3. probe 的「讀取遠端受保護資料」只查 remote metadata：Auth 是否存在、可見 relationship 的狀態與單向指紋、active membership 數、可見 `shared_items` 數、本人最新 personal archive／其 relationship 的單向指紋，以及 `personal_archive_items` 數。不讀取或顯示正文、照片、raw UUID 或 token；所有數字都是本次 server query，不使用畫面 cache。

### 1. 建立 active relationship 基線

1. 維持目前狀態：A、B 的 App 都以 `S` 登入，且 `S`／`P` 的 relationship 為 active。先不要再次執行 `.others`。
2. A 在正式對話送出一筆不含私人內容且可辨認的測試文字，例如 `W13 fixture`；等待 B 看見已同步結果。不要使用照片或真實對話。
3. A、B 各開啟 W13 probe，依序按「驗證目前 session refresh」與「讀取遠端受保護資料」。兩台都須顯示 Auth 存在、同一個 relationship 指紋 `R`、status `active`、active members `2`、`shared_items = N` 且 `N >= 1`。記錄 `R`、`N` 與 JWT expiry，不記 raw ID／token。
4. 在 B 從 App 正常登出 `S`。若 Sign in with Apple 只能使用 Simulator 目前的 Apple account，到 iOS「設定」登出 `S`、登入 `P`，再回 CoupleSpace 以 Apple 登入；不需清除 Simulator 或重新 build。
5. B 以 `P` 登入後再讀一次遠端受保護資料。預期仍是 `R`、`active`、members `2`、`shared_items = N`；帳號識別碼應與 `S` 不同。任一值不符即停止，不開始解除配對。

### 2. 正式解除配對並建立兩份封存

1. A（`S`）開啟「我們 → 帳號設定 → 關係與資料 → 解除配對」，確認不可恢復原 relationship 後按「開始解除配對」。這一步會把 relationship 改為 closing，並自動建立 `S` 的 owner-only archive。
2. A 進入「解除配對進行中」後，由右上角 W13 probe 讀取遠端受保護資料。預期 relationship 仍為 `R／closing`、members `2`、`shared_items = N`、本人封存存在且其關係指紋為 `R`、封存項目數為 `N`。記錄 `S` archive 指紋 `AS`。
3. B（`P`）回前景，確認直接進入「解除配對進行中」，按「建立我的個人封存」。第二份封存完成後 relationship 轉為 archived；A、B 都應收斂到「個人封存已完成」。
4. A、B 分別由右上角 W13 probe 再讀一次。預期 Auth 都存在；Relationship 顯示「成功 · 無可見資料」、active members `0`、`shared_items 0`，這是 archived membership 的 RLS 可見性，不是刪除證據；兩台本人封存都存在、封存 relationship 指紋都等於 `R`、封存項目數都等於 `N`。`S` 的 archive 指紋仍為 `AS`；記錄 `P` 的不同 archive 指紋 `AP`。
5. 若兩份 archive 的 relationship 指紋不同、`AS == AP`、任一 archive item count 為 0／不等於 `N`，或任一方能看到對方 archive，立即記為 FAIL；不要刪除或建立新配對。

### 3. 在 archived 狀態建立兩個 S session 並撤銷其他登入

1. 先保存 B（`P`）的 `AP／R／N` 截圖。B 從 App 登出 `P`，必要時將 Simulator Apple account 從 `P` 切回 `S`，再以 Apple 登入。A 維持既有 `S` session；此時 A、B 是同一 Supabase user `S` 的兩個 session。
2. A、B 各按「讀取目前 session identity」、「驗證目前 session refresh」與「讀取遠端受保護資料」。兩台都須顯示 Auth 存在、同一 `AS／R／N`。若 JWT 有 `session_id`，兩台指紋應不同；沒有則誠實記為 unavailable。
3. 因 archived 畫面沒有正式帳號設定入口，本段只在 A 的 W13 probe 按「登出所有其他 session」並二次確認；先前 active relationship 的正式產品入口已另行驗證。成功訊息只能記為 requested。
4. A 立即按「驗證目前 session refresh」及「讀取遠端受保護資料」。預期 refresh 成功、Auth 存在、`AS／R／N` 完全不變。
5. B **先不要 refresh**，先按一次「讀取遠端受保護資料」並記錄舊 access JWT 在 `exp` 前是否仍可讀 `AS／R／N`；成功或已被拒絕都如實記錄，不以單一結果推廣為固定行為。
6. B 再按「驗證目前 session refresh」。預期舊 refresh token 被拒絕、Auth 變成不存在或 App 回到 Apple 登入。若仍 refresh 成功則 FAIL。
7. 若 W13 probe 仍可開啟，再按「讀取遠端受保護資料」：預期 Auth 不存在、relationship／archive 無可見資料、members 與 shared items 為 0，或 server query 明確失敗；不得出現 `AS／R／N`。這要與同時仍能在 A 讀到 `AS／R／N` 一起判讀，不能把空集合單獨當成資料已刪除。
8. 強制結束 B，再用本節第 0 段的 `simctl launch ... --session-capability-probe` 重開。預期舊 session 不恢復，仍停在 Apple 登入。
9. B 重新以 `S` 完成 Apple Sign In；再讀遠端受保護資料。預期建立新的 Supabase session，重新看見完全相同的 `AS／R／N`，證明撤銷沒有刪除 `S` archive。A 再 refresh 一次並確認仍有效。

### 4. 最後驗證 P archive 未受 S 的 all-others 影響

1. B 登出 `S`，必要時把 Simulator Apple account 切回 `P`，再以 `P` 登入。
2. 開啟 W13 probe 讀取遠端受保護資料。預期本人 archive 指紋仍為 `AP`、archive relationship 指紋仍為 `R`、item count 仍為 `N`；不應看到 `AS`。
3. 到此才可記錄：「`S` 的 all-others 不影響目前 A session，不刪除 `S` archive，也不刪除／改寫 `P` archive」。仍不得宣稱 Supabase 支援逐一裝置 inventory 或指定 B revoke。
4. 本輪結束前不要刪除 `AS`／`AP`；若之後要清理，另依 `LIFECYCLE-001` 執行並留下獨立證據，不能把清理混入 session revoke 結果。

## 執行清單

- [ ] **SDK deterministic probe：** 在 repo root 執行 `quality/scripts/verify-session-capability.sh`。預期 PASS，輸出只描述 2.54.1 的 scope／claim surface，不含私密值。任何版本或 API surface 差異都是 BLOCKED，先更新 capability record。
- [ ] **建立獨立 session：** A、B 依序以同一 Apple 測試身分登入。每台點右上角僅在 `DEBUG + --session-capability-probe` 出現的 **W13 session 測試**，按「讀取目前 session identity」。預期至少顯示「目前 session 已取得」及 Access JWT 到期時間。若 issuer 有 `session_id`，會另顯示 12 碼單向測試指紋，A、B 應不同；它不是 raw UUID。若和本次 Simulator A 一樣缺少 `session_id`，記錄「session identity unavailable」，並把可信 inventory／逐一撤銷結論標為 BLOCKED；不得用 `sub`、Apple ID、APNs token 或本機裝置資料代替。仍可另外觀察 `.others` 的全體撤銷語意，但不能聲稱已識別或選取 B。
- [ ] **撤銷前基線：** A、B 各自執行一次受保護讀取：active relationship、共同 history fixture、自己的 personal archive fixture。三類都成功；比對 count／fixture identity，證明兩台本來都有效。
- [ ] **正式入口與警告：** 在 A 開啟 **我們 → 帳號設定 → 登入安全 → 登出其他所有登入**。確認警告完整說明目前裝置保持登入、其他裝置需重新使用 Apple 登入、既有 access JWT 可能在到期前短暫有效，以及 relationship／共同內容／個人封存不變；缺任一項即 FAIL，先不要送出。
- [ ] **送出 all-others：** 僅在 A 的確認框按「登出其他所有登入」。預期畫面顯示以「已送出」開頭的保守狀態；此刻只能記錄 `requested`，不能寫 B 已撤銷。不要再從 Debug probe 重複呼叫 `.others`，不要執行一般「登出」或 `.global`，不要在 B 本機刪 token，也不要解除配對。
- [ ] **A 不受影響：** A 立刻與在接近 expiry 後各做一次 refresh／受保護讀取。預期 A 維持同一 Supabase user、relationship、共同 history 與 owner-only archive 可讀；沒有 `SIGNED_OUT`、沒有 relationship 變更與沒有資料刪除。
- [ ] **B JWT 殘留窗口：** 在 B 仍未過 `exp` 時讀取相同三類資料。預期可能成功；這是預期安全限制，不是撤銷失敗。記錄實際結果與 expiry，不等待或猜測一個固定分鐘數。
- [ ] **B 首次可靠拒絕：** 在 B 的 access JWT 過期後，先讓 App 回前景並執行一次 `refreshSession()` 或觸發需要 session refresh 的受保護讀取；再逐一讀 relationship、共同 history、自己的 personal archive。預期 refresh 被拒絕，SDK 將 session 視為 missing／登出，三類遠端讀取都被拒絕。只有這項與 A 不受影響同時成立，才可寫「所有其他 session 已撤銷」。
- [ ] **B 重開與重新驗證：** 強制結束 B 後重新開啟。預期舊 Supabase session 不能恢復，進入登入入口；若再完成 Apple Sign In，記錄它建立新的 session（可因 Apple SSO 很快），而非撤銷 session 自動復活。新 session 建立後，帳號仍是同一 Supabase user，relationship、共同 history 與 personal archive 均完整。
- [ ] **資料生命週期不變：** 由 A 與 B 新 session 分別比對：relationship status／membership、共同 history fixture、兩個 owner 的 archive fixture identity 與 count 均不變；不得出現 unpair、closing、archive delete、tombstone、內容清空或新的配對。
- [ ] **本機快取與離線限制：** 在 B 被拒絕前後都不要把既有 snapshot／照片快取是否仍在本機誤報成遠端存取。若本機仍顯示已下載內容，記錄為已知限制；只要遠端讀取在 expiry 後成功，則為 FAIL。

## PASS、FAIL 與 BLOCKED

`PASS` 需要：兩個隔離 client 各自完成登入且撤銷前皆可 refresh／讀取、A 在 `.others` 後仍可 refresh／讀取、B 的既有 JWT 殘留行為有記錄且下一次 scheduled／manual refresh 被拒後清除 local session、B 重開不會恢復被撤銷 session、重新 Apple 登入建立新 session、relationship／共同歷史／兩份 owner archive 不變。若 SDK 在 `exp` 前 proactive refresh 並清除 session，須同時記錄原 `exp` 與實際清除時間，不得寫成 access JWT 提前失效；不為本 gate 保存或重播 raw JWT。缺少 optional `session_id` 不阻止驗證 all-others，但永久阻止宣稱已識別或指定 B。

`FAIL` 包含：B 在 expiry 後仍能 refresh 或讀任一遠端資料；A 被登出／失去資料；撤銷導致 relationship 或 archive 生命週期變更；或任何 token／私人資料寫入驗收記錄。

`BLOCKED` 包含：沒有可清理 test project／兩個隔離登入、無法得知現有 JWT expiry、SDK probe 與鎖定版本不一致，或無法從 test-project build 呼叫 `.others`。BLOCKED 不得以單次 HTTP success、B force-quit、刪除 B 本機 token、UI 暫時顯示登入入口或 APNs device 記錄取代。

## 2026-08-19 執行紀錄

- **PASS：** iPhone 17 Pro Simulator A 與 iPhone 17 Pro Max Simulator B 以同一測試 user S 建立隔離 session，iPhone 17 Simulator C 以 relationship 的另一位 owner P 登入。三台撤銷前 remote-only query 都讀到 active relationship `1971C4CFD7A1`、members `2`、`shared_items` count `1`；A／B 的 S archive 為 `9FF517E636D8`，C 的 P archive 為 `48EA519E7187`，兩份 archive 都指向 `30BE04486C70` 且 item count `4`。所有值都是單向指紋或 count，不含 raw ID／正文。
- **撤銷時序：** A 從正式入口送出 `.others` 後仍可 refresh／remote read，C 亦完全不受影響。B 在撤銷後仍以顯示 `exp` 2:28 PM 的既有 JWT 成功 remote read；未人工 refresh，於 2:26 PM 自動回到 Apple 登入，符合 proactive refresh 被拒後 SDK 清除 session。B force-quit／重開未恢復舊 session；重新以 S 完成 Apple 驗證並經背景／前景後，refresh 與 remote read 正常。
- **資料不變：** 最終 A、B 都維持 `1971C4CFD7A1／2／1` 與 `9FF517E636D8／30BE04486C70／4`；C 維持 `1971C4CFD7A1／2／1` 與 `48EA519E7187／30BE04486C70／4`。沒有 unpair、closing、archive delete、內容清空或重新配對。`SESSION-001` 對 PD-043 all-others App 路徑為 **PASS**。
- **不可過度推論：** JWT 均無 optional `session_id`，所以沒有可信 inventory，也沒有識別／指定 B 的證據。未保存或重播 raw JWT，且 2:26 的精確 refresh endpoint 未留存；不能寫成 access JWT 提前失效或即時撤銷所有 bearer token。
