---
title: 技術決策紀錄
status: active
last_updated: 2026-08-20
---

# 技術決策紀錄

本文件記錄會影響系統責任、資料所有權或後續實作方向的技術決策。`proposed` 項目只供審核，不得視為已接受架構；接受後才同步更新架構文件與開發路線圖。

## 決策狀態

- `accepted`：目前有效。
- `superseded`：已被後續決策取代。
- `proposed`：尚未確認，不應當成規格實作。

## 已確認決策

### TD-001：Supabase 作為 iPhone v1 共同資料的受管後端

- **狀態：** accepted
- **日期：** 2026-08-06
- **決策：** iPhone v1 使用 Supabase 作為使用者身分、伴侶關係、共同資料與資料生命週期的唯一遠端系統紀錄；不以 CloudKit Sharing 作為正式共同資料來源，也不建立 CloudKit／Supabase 雙寫。

#### 責任

- Sign in with Apple 取得的原生 credential 交由 Supabase Auth 建立及恢復 App session。
- Postgres constraint、RLS 與受控 RPC 執行一對一關係、共同資料授權、解除配對、雙份個人封存與獨立刪除不變量。
- Realtime 只作為變更提示；client 收到事件後必須重新經 RLS 讀取，不直接信任事件 payload。
- 私有照片存放於 Supabase Storage；App 先在裝置端重新編碼，再寫入具 relationship scope 的 metadata，不使用 public URL。
- 遠端寫入使用持久 client UUID outbox；伺服器執行冪等寫入並回傳時間，client 以穩定規則排序及明確呈現待送／失敗／成功狀態。
- Edge Function 只承擔需要服務端權限的非同步工作，例如最後引用照片的 Storage GC；App 不持有 service-role secret。

#### 已有證據

- 兩個不同 Apple 身分已通過原生登入、session 恢復與登出。
- 同一 relationship 的 pairing、`2/2` membership、雙向 RLS 寫入及雙向 Realtime 變更提示已通過真機 A＋Simulator B 實測。
- 私有 Storage 照片已通過雙向上傳、讀取與前景重啟恢復。
- 單筆及三筆 FIFO marker metadata outbox 已通過斷網、強制結束 App、恢復網路、明確重試、順序一致與資料庫冪等驗證。
- 三筆 FIFO photo outbox 已通過斷網 enqueue、強制結束 App、恢復網路、單次 drain、順序一致與跨裝置可見性驗證。
- 最近一次伺服器確認的 relationship 識別、狀態與成員數可依使用者保存為唯讀顯示快照；快照不得取代 session、RPC 或 RLS 授權。
- relationship closing、禁止新增、雙份 owner-isolated archive、獨立刪除及最後引用 Storage GC 已通過雲端實測。
- 兩支真實 iPhone、兩個不同 Apple 身分已完成 development 登入、配對、雙向 marker／message／photo、五輪弱網／跨啟動 Outbox，以及雙向背景／終止／鎖定 sandbox 推播實測。
- CloudKit Sharing 的 owner／participant 權限無法單獨保證 PD-011 要求的對等封存權，因此不符合正式共同資料來源的硬性條件。

#### 本決策不會一併定案

- 正式訊息、Moment、共同約定及其討論的完整資料模型。
- 照片的確切上市額度、顯示尺寸、壓縮品質、正式 upload queue、自動重試與清理細節；PD-019 已確認產品只需共同回顧畫質、不提供原始畫質備份，PD-021 的 30 張／1 GB 研究邊界及拒絕清理已通過 W1 遠端實測，但尚未成為永久上市規格。PD-022 已接受不按時間自動到期，並沿用 relationship／個人封存／明確刪除／最後引用 GC 的既有生命週期。
- production／TestFlight 的 APNs token、worker、送達與鎖定畫面實測細節；development sandbox 的兩支真實 iPhone 雙向背景／終止／鎖定送達已通過。
- 個人封存的正式匯出格式、交付方式與大型資料處理；其中正式基本匯出 v1 的格式與資料範圍已由 [TD-004](#td-004正式基本匯出-v1-與資料刪除稽核契約) 接受，取代本項「尚未接受為最終產品契約」的不確定性。交付機制、大型真機、低磁碟與中斷續傳仍是後續實作／release gate。
- Moment、共同約定、照片等其他正式內容的 outbox 排程、長時間退避、背景執行與長佇列上限；正式文字聊天的前景排程已由 TD-002 定案。
- Firebase 作為事故備援或未來替代方案；v1 不為未採用的第二套後端預建 adapter。

#### 影響

- `ARCHITECTURE.md` 可將帳號、共同資料、同步與資料生命週期由 provisional 候選更新為上述責任邊界。
- W1 後續只需關閉 Supabase 路徑的剩餘風險，不再為 CloudKit Sharing 補做兩支真機的正式架構證據。
- G1 與 M0 於 2026-08-11 通過，可進入 W2。production／TestFlight 推播、大型封存、實際低磁碟與中斷續傳保留為 G13／G15 release gates，不作為 Supabase 架構可行性的循環前置條件。
- CloudKit Sharing PoC 保留為實驗紀錄；正式 App 不進行雙寫、資料遷移或 fallback，以避免衝突與不一致的所有權語意。

#### 替代方案

- **CloudKit Sharing only：否決。** 無法保證解除配對後 participant 在 owner 撤銷分享前取得不可被剝奪的個人封存。
- **CloudKit 與 Supabase 雙寫：否決。** 沒有產品需求需要兩套共同資料來源，會新增衝突、刪除、封存與事故恢復風險。
- **Firebase：保留但不進入 v1 spike。** 能力可行，但目前沒有足以抵銷重做已驗證 constraint、RLS、archive 與 Storage lifecycle 的證據。

### TD-002：正式文字聊天採 relationship-scoped 持久 FIFO Outbox

- **狀態：** accepted
- **日期：** 2026-08-12
- **決策：** W9 正式文字聊天在遠端寫入前，先把本文、登入 user UUID、active relationship UUID、stable client UUID 與本機建立時間寫入裝置持久 Outbox；同一 user／relationship 只以單一 drain 依 FIFO 傳送。伺服器沿用 `write_shared_message` 的 stable UUID 冪等契約與 server timestamp，client 只有在 RPC 成功且本機 acknowledgement 成功後才移除 queue entry。

#### 傳送與恢復規則

- UI 只在本機持久寫入成功後清空輸入框並立即顯示訊息；首次等待伺服器時為傳送中，有限重試耗盡後保留為傳送失敗並提供明確重試，遠端收件後為已同步。產品不顯示伴侶已讀狀態。
- 冷啟動／登入、回到前景，以及 App 在前景觀察到網路由 unavailable 轉為 available 時觸發恢復；同一 model 只允許一個 drain，後續訊息加入既有 FIFO 尾端。
- 每筆在一次恢復事件中立即嘗試，失敗後以 1 秒、4 秒延遲再試，合計最多三次；到達上限後停止並保留失敗項目，等待使用者重試或下一次恢復事件。
- relationship scope 或登入身分改變時不會把舊 queue 送給目前伴侶；畫面結束／登出後停止後續 retry 與 queue drain。
- response 遺失時仍以同一 client UUID 重送；伺服器既有冪等 RPC 回傳原本訊息時間，因此不建立第二則遠端訊息。
- 已登入 user UUID 由恢復完成的 authentication state 傳入正式聊天 service，讓 user＋relationship scoped Outbox 可在沒有網路時先完成本機初始化，不等待其他遠端模型。
- App 保存最近 200 則已同步文字作為 user＋relationship scoped 裝置顯示快照；離線時先合併快照與待送內容，恢復網路後仍以 Supabase RLS 重讀結果校正。快照不是備份，成功登出或遠端確認 relationship 已失效／改變時清除。

#### 明確不包含

- 不使用 background task、無限輪詢、長時間退避或推播喚醒保證；背景中的未同步內容仍誠實保留在裝置，不宣稱已備份。
- 本決策只關閉 W9 正式純文字聊天。聊天照片、Emoji 回應與收藏為 Moment 仍屬 W10；其他內容類型須在各自垂直切片另行接入或驗證，不因共用名稱 `outbox` 自動視為完成。

#### 證據與剩餘 Gate

- 本機 unit tests 已覆蓋跨 store recreation 的 FIFO、user／relationship 隔離、有限退避、同一 drain 期間連續送出、最近對話快照的容量與 scope，以及伺服器已收件但本機 acknowledgement 失敗後以同一 UUID 重送不重複。
- 首輪雙真機弱網驗收另要求：隊首失敗時所有被阻塞訊息均須顯示可重試；網路恢復須重建 Realtime subscription 並在 drain 後重讀，執行中的 refresh 不得丟棄新事件。離線冷啟動可使用既有 user-scoped relationship 唯讀快照通過導覽 gate，但不可據此授權寫入。
- 2026-08-13 針對雙真機影片揭露的離線輸入靜默消失、既有聊天誤顯示為空白與啟動等待問題，新增本機 enqueue 語意、最近對話快照、配對快照優先恢復、平行模型啟動及對應 regression。全新完整 iPhone scheme 記錄 110 個測試定義、動態 launch matrix 展開後 113 次 executions，0 failure、0 skip；完整本機 gate 另含 18 files／251 pgTAP、schema lint、5 個 APNs tests、Harness 與 diff hygiene，均通過。
- 2026-08-13 最終雙真機複驗通過三分頁離線冷啟動快照、前景 Realtime，以及離線期間新增內容在恢復網路後自動補齊且不需重啟。commit `6c0f4e3` 的最終完整 Gate B 記錄 113 個測試定義、動態 launch matrix 展開後 116 次通過，0 failure、0 skip；18 files／251 pgTAP、schema lint、5 個 APNs tests、Harness 與 diff hygiene 亦通過。G8／W9 正式完成。

### TD-003：雲端災難復原採受管主站、供應商外加密冷備份與人工冷重建

- **狀態：** accepted
- **日期：** 2026-08-13
- **決策：** Supabase production 保持唯一可寫遠端 SSOT；database 以受管 PITR 加上供應商外 encrypted logical dump 保護，Private Storage objects 另作供應商外增量與不可變版本保護。重大 region／control-plane／vendor 事故由人類選擇 recovery point，在另一 region 或核准替代環境冷重建單一新主站，不自動 promotion、failback 或雙向合併。

#### 技術不變量

- Database backup／PITR 只保護 database 與 Storage metadata，不得視為實際 object backup。
- 每個可用 recovery point 均須有 manifest，綁定 database artifact、schema version、Storage object identity／bytes／checksum，以及 deletion journal sequence 與該筆 event hash。
- 還原以 Database 引用集合為準；缺少任何被引用 object、checksum mismatch、tombstone 斷裂、RLS／Auth 無法重建或 reference integrity 失敗時保持隔離。
- App 透過離線 private key 簽署、內嵌 public key 驗證的最小 service manifest 取得 endpoint、publishable key、事故 mode 與 status URL；manifest 不承載秘密或一般產品 feature flags。
- 事故模式為 `normal／degraded／read_only／recovery`。一致性未知時停止不具可靠持久 Outbox 的寫入；舊主站失去 production 寫入權後不得自動復權。
- 刪除、解除配對、archive delete、account delete 與 GC 以最小化 append-only tombstone 外送，舊備份還原後先重播再開放使用者存取。
- 自動排程須由獨立 dead-man freshness 監控；沒有失敗通知不能推論備份成功。

#### 初始操作目標

- Database logical dump 每 6 小時、Storage incremental copy 每 1 小時、deletion journal 最遲每 15 分鐘外送。
- 備份不可變保護 14 天、日常 recovery retention 35 天為上線候選；正式設定與隱私文案須在法規、供應商及 restore drill 核對後定案。
- 一致 recovery point 的初始內部 RPO 候選為 6 小時，D4 冷重建 RTO 候選為 8 小時；這些數字只有在實際資料量連續演練達標後才能視為能力，且不自動成為公開 SLA。
- 每月以 synthetic data 完整還原；每季以 production encrypted backup 在隔離環境還原並以 counts、hash、constraint、RLS 與真機恢復驗證。相關 schema、Storage、Auth、encryption、delete／unpair、backup 或 endpoint 變更的正式版本須重跑受影響 drill。

#### 拒絕的替代方案

- **CloudKit／Supabase 雙寫：拒絕。** 會把授權、排序、刪除、封存與衝突處理擴大成兩套 production SSOT，超過一人可靠營運能力。
- **Read Replica 作完整 DR：拒絕。** 唯讀非同步 database replica 不等於 Auth、Storage、Realtime、Functions 與設定的可寫災備環境。
- **自架 Supabase：拒絕。** 將 HA、patch、監控、備份與災難復原責任轉回單人，沒有抵銷風險的現有需求。
- **自動跨區切換：拒絕。** 在資料一致性與失敗範圍未知時可能製造雙主分叉；早期產品以明確唯讀及人工冷重建為較安全取捨。

完整操作規格與尚未完成證據見[一人營運災難復原規格](../architecture/01-disaster-recovery.md)。

### TD-004：正式基本匯出 v1 與資料刪除稽核契約

- **狀態：** accepted
- **日期：** 2026-08-20
- **決策：** W14 採 versioned 基本匯出與 server-authoritative deletion operation；任何 migration、RPC 或 runtime 實作都必須先符合本決策及 PD-045，不得由實作者補猜帳號刪除語意。

#### Export v1

- 套件固定包含 `manifest.json`、`data.json` 與 `media/<opaque-id>.jpg`；manifest 記錄 format version 及 package UTC snapshot，並為每個媒體記錄 bytes、MIME 與 SHA-256。資料以 opaque stable ID 保持 Moment／互動、聊天／Reaction、照片、共同約定／事件／討論及其完整來源關聯，不暴露 live Auth UUID。
- `unpaired_account` scope 匯出本人 profile 資料；`active_relationship` scope 匯出本人在 `snapshot_at` 可見的 relationship 資料；`personal_archive` scope 只匯出本人擁有的封存，且 snapshot 必須沿用 closing boundary。`closing` 不從變動中的共同資料產生正式套件，須等待本人封存完成後改以 `personal_archive` 匯出。
- 套件包含顯示名稱、匯出者設定的私人伴侶稱呼、在 `snapshot_at` 可見且未過期的目前狀態，以及有權取得的 Moment、互動、聊天、Reaction、照片、共同約定、事件、討論與來源關聯。不得包含伴侶設定的私人稱呼、不可見或已過期狀態、session、push device、Outbox、未讀狀態、操作 receipt、內部 audit 或 tombstone。

#### 刪除、audit 與 tombstone

- 帳號刪除 preflight 必須在申請裝置有 `pending／sending／failed` Outbox work 時阻擋；server 使用穩定 `account_delete_operation_id` 冪等執行產品資料清理、同一快照雙份封存、owner-only archive delete、來源保留及最後引用 GC 排程。relationship seal 使用獨立 stable `closing_operation_id`／snapshot；active 刪帳首次建立，已在 closing 時則引用既有值，不得以 account operation 取代或建立第二份 snapshot。Auth 帳號刪除是整體冪等 operation 的最後一個外部副作用，重試時 Auth 已不存在視為該 operation 成功；回應遺失或重試不得重建資料、重複封存或改寫另一方封存。
- audit 只保存完成授權、除錯與營運所需的事件種類、時間、結果及 opaque references，不保存名稱、私人稱呼、狀態正文、Moment／聊天／Reaction／約定／討論正文或照片內容。append-only tombstone 只保留防止復活及辨識刪除範圍所需的最小 opaque identity、operation／sequence、事件種類與時間，並須外送至 deletion journal；災難恢復在開放存取前依 sequence 重播，確保 account／archive／content／object deletion 不被舊備份復活。

#### 隔離 fixture

- 自動化 fixture 固定使用 A、B 與無關第三人 C，採 deterministic opaque IDs、UTC timestamps、media bytes／checksums 與來源圖；覆蓋未配對、active、closing、archived、單方 `archive_deleted`、帳號刪除與三種 export scope。
- A／B 只能讀取、匯出或刪除各自被授權的 live／archive scope，不能讀取對方私人稱呼或刪除對方封存；C 對 A／B 的 profile、relationship、正文、媒體、來源、匯出、audit 與 tombstone 均無讀寫能力。A 刪帳後 B 的 archive-local actor／顯示名稱快照必須保留但不得含 live Auth link，C 的資料與授權保持不變。

完整資料矩陣、schema 欄位、不變量與 fixture oracle 見[W14 資料生命週期與匯出契約](../architecture/03-w14-data-lifecycle-contract.md)。
