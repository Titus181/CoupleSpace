---
title: W14 資料生命週期與基本匯出契約
status: accepted
last_updated: 2026-08-20
---

# W14 資料生命週期與基本匯出契約

## 目的與接受狀態

本文件是 W14-01 的 canonical contract，收斂 PD-011、PD-022、PD-030、PD-037、PD-045、TD-001、TD-003 與 TD-004。下列帳號刪除結果、資料保留矩陣、export v1、audit／tombstone 與 A／B／C fixture 均為 **accepted**；後續 migration、RPC、client 或測試不得另行推測不同語意。

W14-01 只完成文件契約，不建立 runtime code、migration、部署或測試 PASS。W13 final candidate 的 migrations 001–040、31 files／533 pgTAP、236 個 iPhone 測試定義／239 次 executions、三台 Simulator preflight 與兩支真實 iPhone 整合只作 W14 基線，不是本契約已實作的證據。

## 名詞與狀態

shared relationship 與每位使用者的 archive lifecycle 是兩個維度，不得共用一個會傷害另一位 owner 的全域終態。

| 層級 | 狀態 | accepted 語意 |
| --- | --- | --- |
| Shared relationship | `active` | 兩位 active member 可依 RLS 讀寫核准的共同資料。 |
| Shared relationship | `closing` | server 已接受正式解除配對或 active 帳號刪除；立即禁止新共同寫入，等待同一 server boundary 的兩份封存完成。不得回到 `active`。 |
| Shared relationship | `archived` | 兩份 owner-isolated 封存均已 seal 並驗證；共同 live rows 不再供 former members 讀寫。 |
| Owner archive | `archived` | 該 owner 可唯讀、匯出或獨立刪除自己的封存。 |
| Owner archive | `archive_deleted` | 該 owner 的 archive row、archive-local 正文與 media references 已實體刪除且不可讀、不可匯出；產品資料中不保留空 archive row。此名稱是由 tombstone／operation result 表達的 per-owner 邏輯終態，不是 relationship 狀態，也不改變另一位 owner 的封存。 |

兩份封存使用相同的 `closing_snapshot_at`／server boundary，但不要求 bytes 完全相同：owner-only 私人稱呼、尚未共同揭曉的答案及其他 owner-specific 可見性必須依每位 owner 在該 boundary 已有的授權產生，封存不得讓任一方看到當時無權讀取的內容。

兩份封存及 archive-local 關聯驗證完成後，live shared content rows 與 membership rows 必須實體刪除；owner 存取改由各自 archive 的 owner link 授權。只在至少一份 owner archive 存在期間保留不含 user identity 的最小 relationship row：`relationship_id`、`status = archived`、`closing_snapshot_at`，以及 archive／最後引用 GC 所需的 opaque refs。最後一份 owner archive 刪除並完成 reference 核對後，該最小 relationship row 也必須實體刪除；operation receipt、audit 與 tombstone 依各自保存終點處理，舊備份復活防護由 tombstone policy 控制。

## 帳號刪除契約

帳號刪除是 server-authoritative、具 stable `account_delete_operation_id` 的不可逆流程，不等同 `.local` 登出、App Lock、Apple credential 操作、移除 APNs token 或單純刪除 client cache。relationship closing 另有 stable `closing_operation_id` 與 `closing_snapshot_at`：active 帳號刪除首次接受時建立並記錄它們；若 relationship 已由解除配對進入 `closing`，帳號刪除 operation 必須引用並接續既有 closing operation／snapshot，不得重用其 ID 或建立第二個 snapshot。使用者送出最後確認前可以取消；server 接受 account-delete operation 並建立不可逆 lifecycle／tombstone boundary 後不得取消或退回 `active`。

| 申請時狀態 | Server 必須完成 | 申請者結果 | 另一位 owner／former partner 結果 |
| --- | --- | --- | --- |
| 未配對且沒有歷史封存 | 失效邀請與短碼，清除 profile、owner-only／device／營運資料，先寫最小 account-delete tombstone | Auth identity 最後刪除；沒有個人封存 | 不存在伴侶封存，不建立空封存 |
| `active` | 進入 `closing`、停止共同寫入，以同一 server boundary 建立並驗證 A／B 兩份封存，再刪除申請者擁有的全部封存 | 全部 owner archives 進入 `archive_deleted`，產品資料清理後 Auth identity 最後刪除 | 不必在線；其封存不受本次操作影響，仍可自行匯出或刪除 |
| `closing` | 新建或重用本次 `account_delete_operation_id`，但引用既有 `closing_operation_id`／snapshot 冪等接續；不建立第二次 closing、snapshot 或 owner archive，不得回到 active | 完成後同 active 申請結果 | 同 active 申請結果 |
| `archived`（含目前沒有 active 關係但仍有舊封存） | 刪除申請者擁有的所有 owner archives、owner-only live data 與帳號資料 | archives 全部進入 `archive_deleted`，Auth identity 最後刪除 | 每位 former partner 的 archive、媒體引用、匯出與自行刪除權均保持不變 |
| 已無 owner archive | 將 archive delete 視為冪等成功，完成其餘產品資料與 Auth 清理 | 不重建 archive 或產品資料 | 其他 owner archive 不變 |

### 帳號刪除不變量

1. 申請裝置仍有 `pending`、`sending` 或 `failed` Outbox work 時先阻擋，要求明確重試或捨棄；不得靜默丟棄。PD-044 不提供跨裝置 session／device inventory，因此其他裝置尚未同步至 server 的 Outbox 不保證進入 closing snapshot。
2. 申請者可以先做基本匯出，但成功匯出不是帳號刪除的必要前提；未選匯出或檔案交付失敗不得永久卡住刪帳。
3. 產品資料清理、雙份封存、申請者 archive delete、引用核對、GC enqueue、audit 與 tombstone 必須先於 Auth identity 刪除；Auth delete 是最後一個外部副作用。
4. 每次重試必須使用同一 `account_delete_operation_id`；relationship sealing 使用該 operation 已記錄或引用的同一 `closing_operation_id`／snapshot。Auth identity 已不存在視為 account-delete operation 的成功終態；不得因 response 遺失重建帳號、relationship、archive 或資料。
5. 另一方封存保留雙方曾共同分享的正文、archive-local actor 及 closing 時的顯示名稱快照，但不得保留可回連 live Auth identity 的外鍵。被刪帳者的 live profile、本人設定的私人稱呼與目前狀態全部刪除。
6. relationship 進入 `closing` 時，建立者「最近刪除」中的 Moment 立即永久刪除、排除於雙方封存並寫 tombstone，不等待剩餘 30 天。獨立來源不連帶刪除，媒體仍須最後引用消失後才 GC。

## 資料保留、封存、匯出與刪除矩陣

| 資料類型 | Actor | 可見性 | 保存 | closing／封存 | Export v1 | 刪除／帳號刪除 | Audit／tombstone 結果 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Auth identity／credential mapping | 帳號本人；Auth server authority | 只以受保護 session 間接使用，不作共同內容 | 帳號存在期間保存；session 與產品生命週期分離 | 不複製進 owner archive，不作 actor identity | 不匯出 credential、Apple subject、token、session 或 raw Auth UUID | 所有產品清理完成後最後刪除 | `account_delete` tombstone 使用不可回連 live identity 的 actor ref；無 credential 正文 |
| Relationship／membership lifecycle metadata | server 執行狀態轉移；任一 active member 可發起 formal unpair／account delete | active members 可讀目前 relationship；closing 後不再提供共同內容入口；archived owner 只讀自己的 archive metadata；第三人不可見 | 完整 row 至少保存到同一 snapshot 的雙份 archive 驗證完成；其後刪 membership，只在有 owner archive 時保存 `relationship_id`／`archived`／`closing_snapshot_at` 與 opaque refs | 每份 archive 使用 archive-local opaque relationship／actor IDs 與 `closing_snapshot_at`，不複製 live membership 或 former-partner Auth FK | manifest 只輸出 package-local `relationship_id`，actor role 在 `actors`；不輸出 membership row／status history／Auth ID | 雙份 seal 後實體刪除 membership；最後一份 owner archive 刪除且 reference 安全後實體刪除最小 relationship row；一方刪帳不改 partner archive | closing 寫 `unpair` 或 account lifecycle event；owner／account delete 各寫相應 tombstone，無名稱／正文／live Auth ref |
| 本人顯示名稱 | 本人寫入 | 本人與 active partner 可見 | live profile 保存到本人修改或刪帳 | 兩份 archive 均保存 closing 時可見的 display-name snapshot | `unpaired_account` 匯出本人值；`active_relationship` 匯出雙方可見 snapshot；`personal_archive` 匯出 archive snapshot | live profile 隨本人刪帳清除；surviving partner archive snapshot 保留 | 只記 entity ref／action，不記名稱字串 |
| 私人伴侶稱呼 | 設定者寫入 | 僅設定者 | 只在該 owner scope 保存 | 只進設定者自己的 archive，另一份不得出現 | 只匯出 export owner 自己設定的值 | 設定者可清除；刪帳刪除本人設定值，但不刪 former partner 自己的 alias snapshot | 只記 owner-scoped entity ref／action，不記稱呼 |
| 目前狀態 | 狀態 owner 寫入 | active 雙方只看尚未過期值 | 單筆 current value；過期即不可見，不建立歷史 | `closing` 立即不可見並清除，不進任何 archive | 僅 `active_relationship` 匯出 `snapshot_at` 仍可見值與 expiry；其他 scopes 不匯出 | owner 清除、到期、closing 或刪帳皆移除 | 一般到期不需 deletion tombstone；scope cleanup audit 不得含狀態正文 |
| Live Moment | 建立者建立；雙方依契約互動 | active 雙方 | 不按時間到期；來源與媒體另保留獨立 identity | 依每位 owner 可見視圖進兩份 archive，保留 actor、時間、媒體與來源 link | `active_relationship`／`personal_archive` 匯出內容、actor、時間、media／source refs | active 只有建立者依 PD-037 刪除；刪帳不刪 surviving partner archive copy | content delete 與 object GC 各有最小 tombstone，不存正文 |
| Recently Deleted Moment | 原建立者 | active 期間只供建立者 | 最長 30 天且可復原 | `closing` 立即永久刪除，不進任一 archive | `active_relationship` 只可包含 export owner 自己在 `snapshot_at` 仍可見的項目，標示 `deleted_at`／`purge_after`；其他 scopes 不含 | 期限到或 closing 永久刪除；來源不連帶刪除 | permanent-delete tombstone；最後引用媒體另有 GC tombstone |
| Moment 回應／問答答案／移除標記 | 各自提交者；server 控制 reveal | 一般回應依共同卡片；答案未共同揭曉前維持原 RLS | live Moment 存在期間保存；本人可依 PD-037 移除自己的內容。一般回應移除後刪除該正文；問答答案移除後保留不含正文的中性 marker | 每份 archive 只保存 owner 當下有權讀的正文；不得因 seal 揭露未揭曉答案。只有問答答案的中性移除 marker 可保存 | 只匯出該 scope 有權讀的正文；已移除的一般回應不匯出，已移除的答案只匯出不含正文的 marker | 本人移除正文；整筆 Moment 永久刪除時一併刪除；帳號刪除不改 partner archive 已授權 snapshot | 移除／永久刪除只記 entity ref、actor ref、action |
| 主聊天與約定討論文字／照片 | 訊息建立者 | active relationship 與正確 conversation／appointment scope | 共同歷史持續保存；目前沒有任意單則訊息刪除契約 | 兩份 archive 保存正文／media ref、actor、server time 與 discussion scope | `active_relationship`／`personal_archive` 匯出；discussion 以 appointment scope 表達 | 只隨 owner archive／帳號 lifecycle 清除；一方刪帳不移除 partner archive copy | archive／account delete tombstone 不複製訊息正文 |
| W1 technical marker | W1 驗證 fixture／debug actor | 只屬技術 spike；Release 無產品入口 | 不得再由正式 App 新增 | 不進 W14 正式 archive；既有 test/dev row 在 closing cleanup 移除 | 不匯出 | 依 relationship／environment cleanup 清除 | 不逐筆保存內容；scope cleanup audit 只記 count／result |
| 訊息 Emoji Reaction | reaction actor | active 雙方於正確訊息 scope 可見 | 保存目前 set／replace 結果；remove 後不留私人值歷史 | archive 保存 closing boundary 的目前 reaction snapshot | `active_relationship`／`personal_archive` 匯出目前值與 actor ref | actor remove 後清除；archive／account lifecycle 同來源訊息 | audit 不記 Emoji 值，只記 entity／action |
| 照片 metadata 與 Private Storage JPEG | uploader 建立；server 驗證 relationship、quota 與引用 | 依引用內容及 owner archive RLS | 不按時間到期；不保存相機原檔 | 每份 archive 保存 media ref、bytes、MIME、checksum；object 可由多份資料引用 | `media/<opaque-id>.jpg`，manifest 記 bytes／MIME／SHA-256；只有授權引用可列入 | 只有最後一份 product／archive 引用消失才 enqueue GC；方案降級不刪既有媒體 | metadata delete 與 Storage GC 分開 tombstone；不得存 image bytes／URL token |
| 共同約定 snapshot | 建立者及兩位 active partner 透過受控 operation | active 雙方 | scheduled／cancelled 均作共同歷史保存 | 兩份 archive 保存 title、time、location、note、reminder snapshot、status、actor 與 source | `active_relationship`／`personal_archive` 匯出 | 取消不是刪除；只隨 owner archive／account lifecycle 清除 | lifecycle audit 不複製 title、location、note |
| 約定重大事件 | server 由有效 operation 產生，保留 actor | active 雙方 | 改期／取消事件不可由 client 偽造或任意刪除 | 兩份 archive 保存 event kind、actor、時間與 appointment ref | `active_relationship`／`personal_archive` 匯出共同歷史事件 | 隨 owner archive／account lifecycle 清除 | operation receipt 不是 privacy-safe audit；audit 只保留最小 refs |
| 來源關聯 | server-authoritative content／source identity | 跟隨兩端內容的授權 | live 期間維持 Moment↔message／appointment／discussion link | 改寫成 archive-local IDs 並通過 reference integrity；未納入封存的 Recently Deleted Moment 不建立 link | `source_links` 使用 package 內 stable IDs；不得暴露 Storage path 或 Auth ID | 刪除 Moment 不刪來源；來源依自身契約清除。link 任一端不存在時不得偽造可返回入口 | 只記 link entity ref／integrity result，不記兩端正文 |
| 對話 read cursor、interaction ledger／read state | 每位 viewer；server 驗證 boundary | owner-only cursor；ledger 依內部授權 | 只服務 active unread／badge | closing 停止前進並清除，不進 archive | 不匯出 | relationship closing／account delete 清除 | 不需內容 tombstone；cleanup audit 只記 scope／result |
| PD-020 產品分析事件／彙整 | server 從 allowlisted interaction metadata 產生；分析服務處理 | service-only，不提供 user／partner 內容瀏覽 | raw actor／relationship-linked event 只保存於 relationship active 期間；不得含私人正文 | relationship 進入 closing 即刪除 raw linked events；不進 archive。無 actor、account、relationship 或 content 可回連欄位的不可逆 aggregate 可保留 | 不匯出 | 任一相關帳號先刪除時立即刪除 raw linked events；不可逆 aggregate 不受影響 | cleanup audit 只記 scope、count、result；不為每筆分析事件保留 identity tombstone |
| 邀請、短碼、無效嘗試限流 | 邀請者／受邀者；server authority | 只限必要參與者；短碼不是資料 identity | 到接受、拒絕、取消、過期或輪替 | 不進 archive | 不匯出 | terminal invite、closing 或 account delete 失效／清除 | audit 不保存完整 token／短碼；只記 action／result |
| Push device／delivery job、notification preference、本機提醒 | 裝置 owner；server／iOS authority | owner／service only | 只為 active routing／本機呈現保存 | closing 移除 relationship routing 與提醒；不進 archive | 不匯出 APNs token、job、preference 或 reminder | 登出／relationship terminal／account delete 依 scope 移除；不能作 Auth inventory | audit 不含 token、通知正文、appointment title／note |
| Session、local cache、snapshot 與 Outbox | 裝置上的已登入 user | 該 app installation only | cache 不是 SSOT；Outbox 只保存尚未 server-accepted work | closing／logout／account switch 依既有 lifecycle generation 收斂；不進 archive | 不匯出 local cache／Outbox | 申請裝置未清 Outbox 會阻擋刪帳；server terminal 後清除本機 scope | 不寫內容 tombstone；只可記不含正文的 count／result |
| 產品 mutation receipt／idempotency record | server；原 mutation actor | service-only | active 期間只為冪等重試保存；可能含 appointment payload，故屬產品資料而非 audit | 對應產品 row 完成雙份 seal 後實體刪除，不進 archive | 不匯出 | closing／account delete 依來源產品 scope 實體刪除 | 含產品欄位的 receipt 不得被當成 audit 或長期保留 |
| Lifecycle operation result／GC queue | server／worker | service-only | 無 mutation 的 blocked／failed result 保存到 terminal response；有 mutation 者保存到 side effects terminal 且 tombstone durable | 不進 owner archive | 不匯出 | 無 mutation 者在 terminal 後首次 sweep 刪除；有 mutation 者在 terminal＋tombstone durable 後首次 sweep 刪除；GC completion tombstone durable 後刪 queue item | operation／GC 結果另寫 body-free audit；實際刪除各有 tombstone |
| Owner personal archive | archive owner；server seal | 僅 owner | `archived` 後持續保存，無時間型自動到期 | owner-specific immutable snapshot | `personal_archive` 完整匯出 | 只有 owner／其 account-delete operation 可刪除 archive row、archive-local 正文與 references，並以 tombstone 表達 `archive_deleted`；不得保留可讀空殼，另一份不受影響 | `archive_delete` tombstone，最後引用再觸發 object GC |
| Lifecycle audit | server／受限維運角色 | 不提供一般使用者或 partner 任意瀏覽 | 只保存完成授權、除錯與稽核所需的最小 metadata | 不進產品 archive | 不匯出 | 依下節兩分支終點實體刪除 identity-bearing event；只可另留不可回連 aggregate | 欄位及禁止內容見下節 |
| Deletion tombstone／DR journal | server／DR worker | service-only、加密、append-only | 保存至所有可能含目標的 recovery point 淘汰，且 journal replay／完整性驗證通過 | 不進 owner archive | 不匯出 | 依下節條件退役 identity-bearing segment，只留 hash-chain checkpoint／不可回連 drill evidence | 永不保存私人正文；restore 開放前必須依 sequence＋hash 重播 |

## 正式基本匯出 v1

### 適用 scope

- `unpaired_account`：本人 profile 資料；若仍持有舊 owner archives，須另以 `personal_archive` scope 逐份匯出。
- `active_relationship`：export owner 在 `snapshot_at` 有權讀取的共同資料、本人 owner-only 欄位及本人可見的 Recently Deleted Moment。
- `personal_archive`：本人已 seal 的單一 owner archive。
- `closing` 不直接匯出仍變動中的 live tables；須等本人封存 seal 後使用 `personal_archive`。

所有授權、目前狀態 expiry、Recently Deleted 可見性與 reference count 都在 `snapshot_at` 判斷。`unpaired_account`／`active_relationship` 的 `snapshot_at` 是 export read transaction 的 server consistency boundary；`personal_archive` 的 `snapshot_at` 必須等於該 immutable archive 的 `closing_snapshot_at`，不是 export 執行時間或單純的 `sealed_at`。`generated_at` 只表示 package 產生完成時間，不得改寫 snapshot 內容。

基本匯出不設 Plus 付費牆。精美排版、合輯或其他進階呈現可以另案，但不得阻礙取得完整 v1 基本資料。v1 是 export-only；匯入／還原 package 不在本契約範圍。

### Package layout

```text
CoupleSpace-export-v1/
  manifest.json
  data.json
  media/
    <opaque-media-id>.jpg
```

v1 的規範物是可直接閱讀的資料夾；ZIP、加密容器、匯入／還原格式與分享 UI 均不是 v1 schema 的一部分。外層資料夾可由交付介面重新命名，但解開任何未來 transport container 後必須只有上述相對路徑。沒有媒體時仍保留空的 `media` manifest array；實體 `media/` 目錄可省略。package 不得包含未列於 manifest 的檔案。

### `manifest.json`

| 欄位 | 型別 | 規則 |
| --- | --- | --- |
| `format` | string | 固定 `com.couplespace.basic-export` |
| `format_version` | integer | 固定 `1` |
| `export_id` | string | 本次 export opaque UUID |
| `scope` | string | `unpaired_account`、`active_relationship` 或 `personal_archive` |
| `generated_at` | string | server 產生的 RFC 3339 UTC timestamp |
| `snapshot_at` | string | 本 package 的 server consistency boundary，RFC 3339 UTC |
| `owner_actor_id` | string | package 內 actor ID，不是 Auth UUID |
| `relationship_id` | string or null | package 內 opaque relationship ID；`unpaired_account` 必須為 `null`，`active_relationship`／`personal_archive` 必須非 `null` |
| `archive_id` | string or null | package 內 opaque archive ID；`unpaired_account`／`active_relationship` 必須為 `null`，`personal_archive` 必須非 `null` |
| `data_file` | object | 只能有 `path`、`bytes`、`mime_type`、`sha256`；`path` 固定 `data.json`，`mime_type` 固定 `application/json` |
| `media` | array | 每筆只能有 `id`、`path`、`bytes`、`mime_type`、`sha256`；`id` 是 package-local opaque UUID，`path` 必須等於 `media/<id>.jpg`，MIME 固定 `image/jpeg`；按 `path` 升冪 |

`data_file.bytes` 是 positive integer；每筆 `media.bytes` 也是 positive integer。`sha256` 是對實際檔案 bytes 計算的 64 字元小寫 hexadecimal SHA-256。`snapshot_at` 不得晚於 `generated_at`。manifest 及其 nested object 不得加入上述未定義欄位；若需新增或改變語意，必須提高 `format_version`。

### `data.json`

`schema_version` 固定為 integer `1`。下列 top-level keys 全部必須存在，且不得加入未定義 key；每個 nested object／array item 也必須恰好具有表列欄位，不得加入 extension key。若需新增或改變欄位語意，必須提高 `schema_version`。array 沒有資料時使用 `[]`，nullable 欄位沒有值時使用 JSON `null`，不得以漏 key 表示不同語意。

| Key／型別 | 每筆 object 的必要欄位與固定語意 |
| --- | --- |
| `schema_version`／integer | 固定 `1`。 |
| `actors`／array | `actor_id: string`、`role: string`、`display_name: string|null`、`display_name_updated_at: timestamp|null`。`actor_id` 是 package-local opaque UUID；`role` 只能是 `export_owner` 或 `partner`。 |
| `owner_preferences`／object | `partner_actor_id: string|null`、`partner_alias: string|null`、`updated_at: timestamp|null`。只表示 export owner 自己設定的私人稱呼。 |
| `current_statuses`／array | `actor_id: string`、`status_kind: string`、`custom_text: string|null`、`expiration_kind: string`、`expires_at: timestamp|null`、`updated_at: timestamp`。只允許 active scope 在 `snapshot_at` 仍可見的值。 |
| `moments`／array | `moment_id: string`、`kind: string`、`creator_actor_id: string`、`mood_value: string|null`、`text_content: string|null`、`question_key: string|null`、`question_prompt: string|null`、`media_ids: array<string>`、`created_at: timestamp`、`lifecycle_state: string`、`deleted_at: timestamp|null`、`purge_after: timestamp|null`。 |
| `moment_responses`／array | `response_id: string`、`moment_id: string`、`actor_id: string`、`kind: string`、`emoji_value: string|null`、`text_content: string|null`、`created_at: timestamp`。已移除的一般回應沒有 export row。 |
| `moment_answers`／array | `answer_id: string`、`moment_id: string`、`actor_id: string`、`state: string`、`answer_content: string|null`、`created_at: timestamp`、`removed_at: timestamp|null`。`state` 只能是 `present` 或 `removed`；`removed` row 是中性 marker。 |
| `messages`／array | `message_id: string`、`conversation_kind: string`、`appointment_id: string|null`、`actor_id: string`、`kind: string`、`text_content: string|null`、`media_ids: array<string>`、`created_at: timestamp`。主聊天的 `conversation_kind` 為 `main` 且 `appointment_id` 為 `null`；專屬討論為 `appointment` 且 ID 必須解析到 `appointments`。 |
| `message_reactions`／array | `reaction_id: string`、`message_id: string`、`actor_id: string`、`emoji_value: string`、`created_at: timestamp`、`updated_at: timestamp`。只輸出 snapshot 當下仍存在的 reaction。 |
| `appointments`／array | `appointment_id: string`、`creator_actor_id: string`、`title: string`、`starts_at: timestamp`、`location: string|null`、`note: string|null`、`reminder_at: timestamp|null`、`status: string`、`cancelled_by_actor_id: string|null`、`cancelled_at: timestamp|null`、`created_at: timestamp`、`updated_at: timestamp`。 |
| `appointment_events`／array | `event_id: string`、`appointment_id: string`、`actor_id: string`、`kind: string`、`previous_starts_at: timestamp|null`、`starts_at: timestamp|null`、`created_at: timestamp`。 |
| `source_links`／array | `link_id: string`、`source_type: string`、`source_id: string`、`target_type: string`、`target_id: string`、`context_appointment_id: string|null`。`source_type` 固定為 `message`；`target_type` 只能是 `moment` 或 `appointment`；討論訊息來源另以 context ID 指向所屬 appointment。 |

欄位 enum 與 nullability 必須符合下列規則：

- `status_kind` 只能是 `busy`、`available_to_talk`、`quiet`、`tired`、`need_company`、`need_hug`、`thinking_of_you` 或 `custom`；只有 `custom` 的 `custom_text` 非 `null`。`expiration_kind` 只能是 `one_hour`、`four_hours`、`tonight` 或 `manual`；只有 `manual` 的 `expires_at` 為 `null`。
- `actors` 中 `display_name` 為 `null` 時 `display_name_updated_at` 也必須為 `null`。`owner_preferences` 在 unpaired scope 三欄皆為 `null`；relationship／archive scope 一律有 `partner_actor_id`，沒有私人稱呼時其餘兩欄皆為 `null`，有私人稱呼時 `partner_alias` 與 `updated_at` 都非 `null`。
- Moment `kind` 只能是 `mood`、`text`、`photo` 或 `question`，並分別只填入 `mood_value`、`text_content`、恰好一個 `media_ids` item，或 `question_key`＋`question_prompt`；其他種類的 `media_ids` 必須為空。`mood_value` 只能是 `calm`、`happy`、`tired`、`thinking_of_you` 或 `need_hug`。`lifecycle_state` 只能是 `live` 或 `recently_deleted`；只有 export owner 自己可見的 `recently_deleted` row 具有非 `null` 的 `deleted_at` 與 `purge_after`，且不出現在 archived scope。
- Moment response `kind` 只能是 `emoji` 或 `text`，並分別只填 `emoji_value` 或 `text_content`；Emoji 只能是 `heart`、`hug`、`smile`、`cheer`、`laugh` 或 `support`。Moment answer 的 `present` row 必須有 `answer_content` 且 `removed_at` 為 `null`；`removed` row 的正文必須為 `null` 且 `removed_at` 非 `null`。未揭曉答案若不在 export owner 於 `snapshot_at` 的授權視圖中，整列不得出現。
- Message `kind` 只能是 `text` 或 `photo`；只有 `text` 填 `text_content`，只有 `photo` 具有恰好一個 `media_ids` item。W1 technical marker 不是正式產品聊天，不得出現在 v1。Message reaction 保留 snapshot 的實際 `emoji_value`：可為上述六個 fixed key，或首字元為 non-ASCII、總長 1–8 個字元、最多 32 UTF-8 bytes 且無 whitespace／control 的 custom Emoji。
- Appointment `status` 只能是 `scheduled` 或 `cancelled`；只有 `cancelled` 的 `cancelled_by_actor_id` 與 `cancelled_at` 非 `null`。Appointment event `kind` 只能是 `rescheduled` 或 `cancelled`；只有 `rescheduled` 同時具有非 `null` 且不同的 `previous_starts_at`／`starts_at`。

所有 `timestamp` 都是 RFC 3339 UTC string，正規化為 `Z`：保留來源最多六位小數、移除小數尾端 `0`，整秒則不輸出小數點。內容及關聯 array 依 `(created_at, stable_id)` 升冪；`actors`、`current_statuses` 與 `source_links` 分別依 `actor_id`、`actor_id` 與 `link_id` 升冪。`manifest.json`／`data.json` 都使用 RFC 8785 canonical JSON UTF-8 bytes，不含 BOM 或尾端換行；同一 stable export operation／`export_id` 的重試，在 `snapshot_at` 與 package-local mapping 不變時，必須產生相同 `data_file.bytes`／`sha256`。使用者另行建立的新 export 可以有新的 `export_id`／mapping，不能只因 snapshot 相同就要求跨 operation bytes 相同。內容與 source 的 stable ID 可沿用不含身分意義的 product／archive client UUID；actor、relationship、archive 與 media IDs 必須重新映射為 package-local opaque UUID，禁止輸出 raw Auth UUID 或 internal Storage identity。每個 actor、content、media 與 source reference 都必須在同一 package 解析，且 ID 在該 package 內唯一。每個獲授權且不同的 Storage object 在 manifest 只能有一筆 media entry；同一 object 被 Moment／訊息／來源重複引用時必須重用同一 package media ID，不得複製 bytes 或增加第二筆 entry。

`manifest.owner_actor_id` 必須解析到唯一一筆 `actors.role = export_owner`。`unpaired_account` 不得有 partner actor；`active_relationship`／`personal_archive` 恰有一筆 `partner`，且 `owner_preferences.partner_actor_id` 必須解析到它。每位 actor 最多一筆 current status；每個 `(moment_id, actor_id)` 最多一筆 response 及一筆 answer；每個 `(message_id, actor_id)` 最多一筆 current reaction；相同 `(source_type, source_id, target_type, target_id, context_appointment_id)` 不得重複。Moment response 只能指向 `mood`／`text`／`photo` Moment，且 actor 必須是非 creator partner；Moment answer 只能指向 `question` Moment。Message reaction actor 也必須是非 message creator partner。所有 source endpoints、appointment context 及 media refs 都必須解析，不能用漏列或 duplicate 表達不同語意。

匯出不得包含：另一位使用者設定的私人稱呼、未揭曉答案、不可見／過期狀態、session／device inventory、Apple identity、APNs token、邀請 token／短碼、Outbox、cache、read／unread、notification preference、operation receipt、GC queue、內部 audit、tombstone、signed service manifest secret、Storage internal path 或 signed URL。

package 完成的必要條件是 `data.json` 及所有列入 manifest 的媒體都已原子寫入、bytes／MIME／SHA-256 相符、所有 source link 可解析，且 staging 沒有額外檔案。失敗或取消必須清理 staging；大型資料、低磁碟、resume 與交付 UI 是後續 gate，不能改變 v1 schema。

## Audit 與 tombstone

### Privacy-safe lifecycle audit

允許欄位只有：

| 欄位 | 型別／規則 |
| --- | --- |
| `audit_event_id` | opaque UUID string，單一事件不可重用 |
| `operation_id` | stable operation UUID string |
| `occurred_at` | server RFC 3339 UTC timestamp |
| `event_type` | allowlisted machine string，不得塞入自由文字 |
| `actor_kind` | `user` 或 `system` |
| `actor_ref` | opaque string 或 `null`；`user` 時非 `null`，`system` 時為 `null` |
| `scope_type` | `account`、`relationship`、`archive`、`content` 或 `object` |
| `scope_ref` | 不含正文／path 的 opaque string |
| `entity_type` | allowlisted machine string |
| `entity_ref` | 不含正文／path 的 opaque string |
| `result` | `accepted`、`blocked`、`succeeded` 或 `failed` |
| `reason_code` | allowlisted machine string 或 `null` |
| `affected_count` | nonnegative integer 或 `null`；只供 scope cleanup／GC 等彙總結果，不得取代逐 entity tombstone |
| `contract_version` | 固定 `w14-v1` |

`actor_ref` 不得是 raw Auth UUID，也不得保存可將它回連 live Auth identity 的外鍵；帳號刪除後任何另外的 mapping 必須一併刪除。一般 user、partner 與 export client 對 audit 都沒有直接讀寫權。

`event_type` 只允許 `unpair`、`archive_seal`、`archive_delete`、`account_delete`、`content_delete`、`object_gc`、`scope_cleanup`、`export_generation`。`entity_type` 只允許 `account`、`relationship`、`relationship_content`、`archive`、`profile`、`partner_alias`、`current_status`、`moment`、`moment_response`、`moment_answer`、`message`、`message_reaction`、`appointment`、`appointment_event`、`source_link`、`analytics_event`、`media_object`、`invitation`、`device_registration`、`delivery_job`、`read_state`、`operation` 或 `gc_queue`。`reason_code` 只允許 `null`、`outbox_not_empty`、`relationship_not_active`、`relationship_not_accessible`、`personal_archive_not_accessible`、`resource_not_found`、`export_not_ready`、`reference_integrity_failed`、`checksum_mismatch`、`journal_not_durable`、`auth_delete_failed`、`storage_delete_failed`、`operation_conflict`、`invalid_request` 或 `internal_error`；新增值必須提高 contract version。

禁止保存顯示名稱、私人稱呼、狀態正文、訊息／Moment／回答、Emoji 值、約定 title／location／note、照片 bytes／path／signed URL、APNs token、Apple identity、邀請 token、auth credential 或 export 內的私人正文。含 title／location／note 等欄位的 appointment operation receipt 是產品／冪等資料，不是 privacy-safe lifecycle audit。

### Deletion tombstone

沿用並具體化[一人營運災難復原規格](01-disaster-recovery.md#tombstone-最小內容)，最小欄位為：

| 欄位 | 型別／規則 |
| --- | --- |
| `event_id` | opaque UUID string，單一事件不可重用 |
| `sequence` | production deletion journal 全域嚴格遞增且不重用的 positive integer |
| `operation_id` | stable authoritative operation UUID string |
| `occurred_at` | server RFC 3339 UTC timestamp |
| `actor_kind` | `user` 或 `system` |
| `actor_ref` | opaque string 或 `null`；規則同 audit，account delete 完成後不得有 live identity mapping |
| `scope_type` | 同 audit |
| `scope_ref` | 同 audit |
| `entity_type` | 同 audit |
| `entity_ref` | 同 audit；Storage object 也只能使用 opaque object ref，不得存 internal path／URL |
| `action` | `content_delete`、`unpair`、`archive_delete`、`account_delete` 或 `object_gc` |
| `contract_version` | 固定 `w14-v1` |
| `event_hash` | 64 字元小寫 hexadecimal chained SHA-256，計算方式如下 |

hash input 是「前一筆 `event_hash` 的 64-byte lowercase ASCII＋單一 LF byte＋本筆除 `event_hash` 外所有欄位的 RFC 8785 canonical JSON UTF-8 bytes」；`sequence = 1` 的前一 hash 固定為 64 個 ASCII `0`。以上述 bytes 計算 SHA-256 後輸出 lowercase hex。空 journal 的 recovery manifest sentinel 固定為 `deletion_journal_sequence = 0`、`deletion_journal_event_hash =` 64 個小寫 ASCII `0`，不得使用 `null`、空字串或缺 key。如此 restore worker 不得自行選擇不同欄位順序、whitespace、Unicode encoding 或 hash chain。

上述 snake_case action 與 actor 去連結規則是 TD-003／DR 文件舊顯示名稱的 canonical refinement。tombstone 必須在正常資料失去存取權的同一 authoritative operation 建立，並以加密 append-only journal 外送。任何 recovery point 還原後，先從 manifest sequence 重播後續事件；缺段、hash 不符或重播失敗時保持隔離。一般 user、partner 與 export client 對 tombstone 都沒有直接讀寫權。

保存終點採已接受的 condition-based rule，不依賴 TD-003 尚未定案的 14／35 天候選：

1. 若 preflight 在任何不可逆 mutation 前即 `blocked`／`failed`，不建立 deletion tombstone；terminal result 寫入冪等 operation receipt 後的首次 retention sweep 必須刪除 identity-bearing audit，audit 不承擔重試狀態。若已跨過不可逆 boundary，identity-bearing lifecycle audit 至少保存到 operation 已 terminal、相關 tombstone 已在外部 journal durable，且所有可能復活該 scope／entity 的 recovery points 均已淘汰並通過最近一次 replay／reference／GC 驗證；條件成立後的首次 retention sweep 必須刪除該 audit event。兩個分支都只有不含 actor、account、relationship、archive、content、object refs 的另行不可逆 aggregate 可繼續保存。
2. tombstone／journal segment 至少保存到所有可能含目標資料的 recovery points 均已淘汰、manifest sequence continuity 完整，且最近一次隔離 restore replay 證明 account／archive／content／object 不復活；條件成立後的首次 journal compaction 必須退役 identity-bearing segment。compaction 必須留下不含 actor／scope／entity 的 checkpoint `{retired_through_sequence, terminal_event_hash, contract_version}`；下一筆 event 以前述 terminal hash 作 chain anchor，每個 recovery manifest 也必須綁定當下 journal sequence＋event hash。長期 drill evidence 只能是不可回連的 counts／result／contract version／checkpoint，不得保留原 refs 或私人正文。

## A／B／C 隔離 fixture

### Actors 與資料

- A：`00000000-0000-4000-8000-0000000000a1`
- B：`00000000-0000-4000-8000-0000000000b1`
- C：`00000000-0000-4000-8000-0000000000c1`，永不加入 A／B relationship
- D：`00000000-0000-4000-8000-0000000000d1`，只作 C 的 fixture partner，讓 C 擁有合法且完整的 unrelated graph
- E：`00000000-0000-4000-8000-0000000000e1`，只作 A 第二份歷史封存的 former partner
- A／B relationship：`10000000-0000-4000-8000-000000000001`
- C／D relationship：`20000000-0000-4000-8000-000000000001`
- A／E 歷史 relationship：`30000000-0000-4000-8000-000000000001`

以上皆為 synthetic UUID。D／E 不是額外驗收 persona；C 仍是 user-facing 第三人隔離視角。其餘 archive、export、operation、product／operational row、source、media、audit 與 tombstone ID 一律使用 RFC 9562 UUIDv5、namespace `50000000-0000-5000-8000-000000000014`，name 固定為 UTF-8 `w14/<scenario-slug>/<entity-type>/<label>`，無前後空白或換行。scenario slug 使用下表 code；`entity-type` 與 `label` 必須來自本節 registry／生成規則，不能自訂文字或使用 random UUID。

Canonical A／B rich graph row registry 如下；每個逗號分隔 token 就是該 `entity-type` 唯一可用的 `label`。actor／creator 取 label 的第一個 actor code；`*-to-*`、`*-on-*` 與 `*-from-*` 依字面固定兩端。C／D mirror 逐 token 只替換以連字號分隔的 `a`／`b` actor-code segment，分別改為 `c`／`d`，所有 photo refs 改指 `c-canary`；不得替換一般單字中的字母，也不得省略某一 table family。A／E 歷史封存只使用 archive labels `a-ae`／`e-ae`、archive-local message label `a-e-history` 與 media label `e-archive`。

| `entity-type` | Canonical `label` registry／關聯 |
| --- | --- |
| `profile` | `a`, `b` |
| `alias` | `a-for-b`, `b-for-a` |
| `status` | `a`, `b`；兩筆皆為 `status_kind = custom` |
| `moment` | `a-mood`, `b-text`, `a-photo`, `a-question-revealed`, `a-question-unrevealed`, `a-saved-main`, `b-saved-discussion`, `a-deleted-shared-source`, `a-deleted-last-reference` |
| `moment-response` | `b-to-a-mood`, `a-to-b-text` |
| `moment-answer` | `a-revealed`, `b-revealed`, `a-unrevealed` |
| `message` | `b-main-text-source`, `b-main-photo-source`, `a-main-appointment-source`, `a-discussion-text-source`, `b-discussion-photo` |
| `message-reaction` | `a-on-b-main-text`, `b-on-a-discussion-text` |
| `appointment` | `b-from-a-main` |
| `appointment-event` | `a-rescheduled`, `b-cancelled` |
| `source-link` | `b-main-text-to-a-saved-main`, `a-discussion-text-to-b-saved-discussion`, `b-main-photo-to-a-photo`, `b-main-photo-to-a-deleted`, `a-main-to-b-appointment` |
| `technical-marker` | `a-debug` |
| `read-cursor`／`interaction-event`／`interaction-read-state` | `a-main`／`a-moment`／`b-relationship` |
| `analytics-event`／`delivery-job`／`notification-preference` | `a-core`／`b-delivery`／`a-notifications` |
| `push-device` | rich graph：`a-device`；unpaired B control 另使用 `b-device` |
| `product-receipt` | `b-appointment` |
| `invite`／`invitation-attempt` | unpaired scenario only：`a-open`, `b-open`／`a-rate-limit`, `b-rate-limit` |

`a-photo`、`a-deleted-shared-source`、`b-main-photo-source` 與 `b-discussion-photo` 都引用 `shared-source`；`a-deleted-last-reference` 只引用 `last-reference`。source-link 的五個 label 也固定上述 endpoints，不得另找同類 row 取代。revealed question 的 creator／answers 是 A／A＋B；unrevealed question 的 creator／唯一 answer 是 A／A。`b-to-a-mood = hug`，`a-to-b-text = support`；兩個 reactions 分別是 custom `🫶` 與 fixed `heart`。

Scenario-only label 也不是自由欄位：owner archive 使用 `a-ab`、`b-ab`、`c-cd`、`d-cd`、`a-ae` 或 `e-ae`；export 使用 `a-unpaired`、`a-active`、`b-active`、`a-archive` 或 `b-archive`。operation 使用 `closing`、`account-delete-a`、`archive-delete-<owner-code>`、`content-delete-<actor-code>`、`object-gc-<media-label>` 或 `export-<actor-code>`；因此同一 scenario 先後刪 A／B archive 必須使用不同的 `archive-delete-a`／`archive-delete-b` operation IDs，不得跨 actor／target 重用。`audit-event` label 固定為 `<operation-label>-<event-type>-<entity-type>-<entity-label>-<result>-<reason-or-none>-01`；`tombstone-event` label 固定為 `<operation-label>-<action>-<entity-type>-<entity-label>-01`。W14 v1 fixture 禁止產生兩筆具有相同 label 前綴的 audit／tombstone；若未來同一 tuple 需要多事件，必須先提高 contract version 並接受新的 ordering rule，不能自行把尾碼改成 `02`。operation receipt／GC queue label 分別重用 `<operation-label>`／`<entity-type>-<entity-label>`。如此 `audit_event_id`、`event_id`、operation IDs、所有 target refs 與 export IDs 都能由 scenario seed 唯一重建。

Audit／tombstone 的 user `actor_ref` 使用 `entity-type = service-actor-ref`、label = actor code；account `scope_ref`／`entity_ref` 使用 `entity-type = service-account-ref`、label = actor code。它們是 fixture-only opaque UUID strings，不是 actor 的 Auth UUID；`system` event 的 `actor_ref` 仍固定 `null`。relationship、archive、content 與 object refs 使用本 registry 對應 stable UUID，Storage object 只用 media UUID、不用 path。account delete terminal 後不得存在 service actor/account ref 到 Auth identity 的 mapping。

每個成功 package 另以 `entity-type = export-remap` 產生 package-local IDs，UUIDv5 label 固定如下：actor 為 `<export-label>-actor-<actor-code>`；relationship 為 `<export-label>-relationship-ab`、`-cd` 或 `-ae`；archive 為 `<export-label>-archive-<owner-archive-label>`；media 為 `<export-label>-media-<media-label>`。`manifest.owner_actor_id`、`relationship_id`、`archive_id`、`actors.actor_id`、owner preference／actor refs 與 media refs 一律使用這組 remap；不適用的 relationship／archive 仍是 JSON `null`，不產生 placeholder ID。content、appointment、event、reaction 與 source-link IDs 則明確沿用本 scenario registry 生成的 product／archive stable UUID，不再次 remap。搭配前述 canonical JSON、固定 snapshot scalars 與排序，fixture 的 package file set、bytes 與 checksum 不需要實作者補任何命名選擇。

`account-delete-active`／`account-delete-closing` 的 Outbox preflight subcase 各自使用全新本機 store，且只放 1 筆未送達 main text item。`outbox_item_id` 與 `client_content_id` 分別使用 `entity-type = outbox-item`／`outbox-content`，label 固定為 `a-account-delete-<pending|sending|failed>-main-text`；`relationship_id` 固定為 A／B relationship，body 使用同 label 的正文 canary，`created_at = updated_at = 2026-01-14T11:59:00Z`。row 的 state 必須等於 label 中的 state；empty control 是同一 seed 但零 Outbox rows。這些 local IDs／bytes 不進 server snapshot、audit、tombstone或 export。

固定時間基準 `T0 = 2026-01-14T12:00:00Z`：一般 `created_at` 從 `2026-01-14T10:00:00Z` 起，依同 table stable ID 升冪的 zero-based ordinal 每筆加一秒；`updated_at` 同法從 `2026-01-14T11:00:00Z` 起。active status 的 `expires_at = 2026-01-14T13:00:00Z`；Recently Deleted 的 `deleted_at = 2026-01-14T11:30:00Z`、`purge_after = 2026-02-13T11:30:00Z`；`closing_snapshot_at`／所有 export `snapshot_at = T0`，archive `sealed_at` 從 `2026-01-14T12:00:10Z` 起依 archive ID ordinal 每筆加一秒，`generated_at = 2026-01-14T12:01:00Z`。任何 fixture 使用裝置 now 判斷時也固定為 T0。

共同約定先從 `2026-01-15T12:00:00Z` 改期到 `2026-01-15T13:00:00Z`，`reminder_at = 2026-01-15T12:00:00Z`，rescheduled event `created_at = 2026-01-14T10:30:00Z`；之後 cancel event 及 appointment `cancelled_at = 2026-01-14T11:15:00Z`，cancel event 的 previous／new time 都是 `null`。fixture deletion journal 從空 journal 開始；事件依 `unpair → content_delete → archive_delete → account_delete → object_gc` phase、再依 `entity_type／entity_ref` 升冪配置 `sequence = 1...N`，`occurred_at = T0 + sequence seconds`。audit 依 `(event_type, entity_type, entity_ref, audit_event_id)` 升冪配置 zero-based ordinal，`occurred_at = T0 + 1 minute + ordinal seconds`。

顯示名稱固定為 `Fixture A`～`Fixture E`；私人稱呼依 owner 固定為 `A alias for B`、`B alias for A`、`C alias for D`、`D alias for C`、`A alias for E` 或 `E alias for A`。A／B／C／D 目前狀態都是 `status_kind = custom`、`expiration_kind = one_hour`，custom text 分別為 `W14 A STATUS`～`W14 D STATUS`。Moment mood 固定 `calm`，B 對 A Moment 的 response 固定 `hug`，A 對 B Moment 的 response 固定 `support`；C／D mirror 沿用相同 value topology。主聊天 custom Reaction 固定 `🫶`，約定討論 fixed Reaction 固定 `heart`。其他正文一律為 `W14::<scenario-slug>::<actor>::<entity-type>::<label>`，其中 `<actor>` 固定為大寫 `A`～`E` 或 `SYSTEM`；同一 row 有多個正文欄位時沿用同一 canary。這個可掃描 canary 必須在產品資料／匯出中出現於預期位置，且在 audit／tombstone／C 對 A／B target 的結果中出現零次。fixture 不得保存密碼、Apple credential、APNs token、service-role secret 或真實私人內容。

Media checksum canary 使用下列恰好 9 bytes 的 synthetic JPEG marker fixture；hex 不含空白，SHA-256 為 lowercase hex。它只供 Storage／export bytes、dedupe、引用及 GC oracle，不作影像 decoder 測試。

| Label | Hex bytes | Bytes | SHA-256 | 引用拓撲 |
| --- | --- | ---: | --- | --- |
| `shared-source` | `ffd8fffe000353ffd9` | 9 | `29bd338f12c5eb6e458ce6876c7351680d5012d00cf699594c25b665d6895aa6` | A／B graph 的 main source photo message、live photo Moment、由該訊息收藏且位於 Recently Deleted 的 Moment，以及 discussion photo 共用同一 object |
| `last-reference` | `ffd8fffe00034cffd9` | 9 | `585c10d51a08fcef37c275af7a5abb441f88e853c37a970f2ad12680779a5f96` | A 的直接建立 Recently Deleted photo Moment 單獨引用 |
| `c-canary` | `ffd8fffe000343ffd9` | 9 | `8f4781afd7663effc945b6f6ecdd5a3b2d1f7cb0b281bb230b298b1be1f15379` | C／D unrelated graph 引用 |
| `e-archive` | `ffd8fffe000345ffd9` | 9 | `72e17240e7494436cfe223b60f89f5084a4d758aec209ec7d85f638ef2fe4dae` | A／E 歷史封存雙方引用 |

A／B rich graph 的基數即為 registry：2 profiles、2 aliases、2 current statuses；7 筆 live Moments（mood／text／photo、2 questions、main／discussion 各 1 筆收藏）、2 responses、3 answers，以及 2 筆 A Recently Deleted photo Moments；3 筆 main messages、1 筆 main reaction、1 筆 appointment、2 筆 discussion messages、1 筆 discussion reaction、2 筆 appointment events、5 筆 source links、1 筆 legacy technical marker，並為表列每個 operational `entity-type` 各建立 1 row。A／B GC queue 起始為空。revealed question 固定使用 `understand_today`／`今天最希望我理解你什麼？`，unrevealed question 固定使用 `recent_small_happiness`／`最近有哪件小事讓你感到幸福？`。

每個 scenario 使用 transaction rollback 或全新隔離資料庫，不沿用前一 scenario 已變異的 actor。除 unpaired A 的明示例外，每個 scenario 都要建立與被測 table family 同 lifecycle class 的 C／D rich mirror graph，含 profile、alias、status、Moment／互動、聊天／照片／Reaction、約定／事件／討論、source graph、operational rows及需要時的雙份 archives。如此任何未帶 relationship／owner predicate 的全表刪除都會改變 C canary，而不能以 C 原本零列誤判 PASS。A／E 歷史 relationship 在所有「刪除 A 全部 archives」scenario 先有 A、E 各一份封存，正文及 `e-archive` object 可核對。

### Required scenarios and oracles

| Code／scenario | Seed 前提與必須證明 |
| --- | --- |
| `unpaired-delete` | A 不存在 relationship／archive，只有 profile、invite、device／operational rows；B 是另一個沒有 relationship／archive 的 Auth＋profile＋invite／device canary，C／D 為 active rich canary。刪除後 A rows 清除、account tombstone 完整、Auth 最後刪除且不建立空 archive；B 與 C／D rows／Auth 完全不變。 |
| `unpaired-export` | 同上但不刪帳。`scope = unpaired_account`，relationship／archive IDs 與 owner preference 三欄皆為 `null`，只有 A actor／profile，所有 relationship arrays 為空；manifest／hash 完整。 |
| `active-export` | A／B active rich graph、C／D active mirror。A／B 各自 `scope = active_relationship`，只取得 `snapshot_at` 授權資料及自己的 alias；A 取得兩筆自己的 Recently Deleted Moment，B 均不得取得；unrevealed question 只有 A export 有 A answer，B export 不得因匯出看到。shared Storage object 在每個 package 只出現一次。 |
| `closing-export-not-ready` | A／B 已有固定 closing operation／T0 snapshot，但 A archive 尚未 seal。live export 必須回 `export_not_ready` 且無 staging 殘留；A archive seal 後只能以 `personal_archive` 成功，不可把 closing live rows 包成 active export。 |
| `personal-archive-export` | A／B archived 且各有 immutable owner view。兩人各自 `scope = personal_archive`，`snapshot_at = closing_snapshot_at = T0`；alias／unrevealed answer visibility 依 owner view，Recently Deleted rows 為零，source／media refs 全部解析。 |
| `active-to-closing` | A／B active rich graph。新共同寫入全部拒絕；current status 與 raw analytics events 清除；兩筆 Recently Deleted Moment 立即永久刪除且不進 archive。`shared-source` 因 live source message 仍有引用而不 GC，`last-reference` 因最後引用消失只排一次 GC；兩份 archive 共用 T0。 |
| `closing-to-archived` | 固定 closing operation／T0 snapshot；兩份 archive 完整 shared history、各自 owner-only view、media refs 與 source graph。seal／response-loss 重試不增加 archive、row、link 或 media entry。 |
| `archive-delete-a` | A／B archived。實體刪除 A archive row／正文／refs，只留下 service tombstone／result；A 不可讀或匯出，B counts、正文、source graph、媒體與權限 byte-for-byte 不變；仍被 B 引用的 object 不得 GC。 |
| `account-delete-active` | A／B active rich graph，A／E 已 archived，C／D active mirror。對 `pending`、`sending`、`failed` 各跑一個隔離 Outbox subcase，均須 blocked 且零 server mutation；empty control 才建立 closing、seal A／B、實體刪除 A 的 A／B 與 A／E 兩份 archives／owner data、最後刪 Auth。B 與 E archives 保留且兩人不必在線。 |
| `account-delete-closing` | A／B 已由 formal unpair 以 `closing_operation_id X`／T0 進入 closing，並預先 seal 恰好一份 A archive；account delete 使用不同 `account_delete_operation_id Y` 並引用 X。Outbox 四個 subcase 同上；empty control 接續既有 snapshot、重用 A archive、建立恰好一份 B archive，重試不得建立任何 duplicate；最後刪 A 全部 archives／Auth，B 與 E archives 保留。 |
| `account-delete-archived` | A 同時擁有 A／B、A／E 兩份 archived owner archives；B、E 各有對應封存，C／D 為 archived mirror。單一 account-delete operation 必須實體刪除 A 的兩份 archives／owner data／account；B、E、C、D 的 archives、media refs 與權限不變。 |
| `last-archive-restore` | A／B archived seed 中 `shared-source` 同時由 A、B archives 引用；先刪 A archive 時不得 enqueue，後刪 B 最後一份 archive 時恰好 enqueue／完成一次 object GC。audit／tombstone 對下列完整 forbidden corpus 零命中；從早於兩次 archive delete 的 recovery point 還原並重播後，兩份 archives、其 content 與 object 均不得復活。 |
| `third-person-isolation` | 於上述每一 scenario 重複 C 視角 exact oracle；A／B lifecycle 前後，C／D 每個 seeded table family 以 stable primary ID 對齊後的完整 contract-owned column values、source graph、media refs、archive／export 能力及 Auth existence 必須逐值相同。 |

### Exact isolation oracle

| Surface | C 對 A／B target 的唯一合格結果 |
| --- | --- |
| RLS collection／table `SELECT` | 成功但回傳 0 rows |
| relationship／content mutation RPC | SQLSTATE `42501`，public code 固定 `relationship_not_accessible`；不得指出 target 是否存在 |
| owner-archive delete／mutation RPC | SQLSTATE `42501`，public code 固定 `personal_archive_not_accessible`；不得指出 target 是否存在 |
| archive／export／media point lookup | SQL layer 為 `P0002`＋public code `resource_not_found`；HTTP／Storage mapping 為中性 404，不得回傳 owner、relationship 或 object metadata |
| audit／tombstone direct access | authenticated role 無 grant，SQLSTATE `42501`＋generic `insufficient_privilege`；A、B、C 都相同 |

每個 scenario 都要核對 A、B、C 三個視角，以及受信 server 視角的 row count、source FK、media reference count、GC queue、audit 與 tombstone。不能只驗 UI 隱藏；所有操作前後都要按 logical table family 名稱升冪、再按 stable primary ID 升冪，比較 C／D seed 的每個 contract-owned column，且 `c-canary` 的 object identity、9 bytes、MIME 與 SHA-256 必須相同；Database engine／Storage provider 自動產生、未被本契約採用的維運 metadata 不得混入 oracle。三種成功 export scope 與 closing-not-ready 另須驗證 exact manifest／file set／hash、排序、nullability、cardinality、無 raw Auth UUID、無 C data、無禁止欄位，以及 failed／cancelled staging cleanup。

Privacy scan 的 forbidden corpus 是 fixture 所有非 ID／非 timestamp 的 product scalar：`Fixture A`～`Fixture E`、所有 alias／status、所有 `W14::...` 正文、兩個中文 question prompt、fixed／custom Emoji 值、appointment title／location／note、四組 media hex bytes／SHA-256 及任何 internal path／signed URL。每個 audit／tombstone 欄位逐值檢查 forbidden corpus 必須零命中；不能只搜尋 `W14::` prefix。

## W14-01 Gate 與下一切片

W14-01 的 gate 只有：

1. 所有 SSOT 連到本文件，且 PD-045／TD-004 與本矩陣沒有矛盾。
2. `W14-CONTRACT-001` 完整性 review。
3. `rtk git diff --check`。
4. `rtk ../../agent-harness/scripts/project-harness.sh check .`。

本切片不執行 xcodebuild、pgTAP、Simulator 或真機。W14-02～08 的名稱／詳細分工目前為 `未記錄`，只能從本契約拆出並使用最低可靠層、自動化與 Simulator；W14-09 才集中執行一次雙真機／雙帳號整合複驗。

本契約沒有剩餘的產品資料語意未決事項。後續若發現任何 migration 或 runtime 必須選擇本文件未定義、或會改變 actor、可見性、保存、封存、匯出、刪除、audit／tombstone 結果的語意，必須停止該切片、先新增並取得 accepted 決策；不得由實作者補猜後繼續。
