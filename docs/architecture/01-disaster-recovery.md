---
title: 一人營運災難復原規格
status: active
last_updated: 2026-08-20
---

# 一人營運災難復原規格

## 文件目的與證據狀態

本文件是 CoupleSpace 遇到 Supabase database、Storage、region、帳號控制面或供應商事故時的災難復原 SSOT。它補充一般換機／重裝恢復，但不取代產品資料生命週期、RLS、匯出、刪除或解除配對規則。

- **已接受：** 單一 Supabase production SSOT、受管 PITR、供應商外加密冷備份、唯讀事故模式、簽章式 service manifest、刪除 tombstone、人工決策切換及定期 restore drill。
- **尚未完成：** production 付費方案、PITR、外部備份帳號、排程、signed manifest、事故模式、tombstone 外送、完整重建自動化與實際 restore drill。
- **證據規則：** 本文件、備份設定畫面、成功上傳紀錄或供應商耐久性宣稱都不是復原成功證據；只有指定 recovery point 的實際還原、完整性核對、RLS 測試及清空本機狀態真機恢復才可關閉 gate。

## 決策摘要

CoupleSpace 採「單一可寫主站＋供應商外冷備份」，不採 active-active、多主寫入、自架 Supabase、CloudKit／Supabase 雙寫或自動跨區 failover。

```text
iPhone App
├─ user＋relationship scoped 本機唯讀快照
├─ 各垂直切片已完成的持久 Outbox
└─ 已簽章 service manifest
        ↓
Supabase production（唯一可寫遠端 SSOT）
├─ Auth／Postgres／RLS／RPC／Realtime
├─ Private Storage
├─ Edge Functions
└─ 7-day PITR
        ↓ 只讀備份來源
供應商外加密冷備份
├─ Database logical dump
├─ Storage objects＋版本
├─ recovery manifest
└─ deletion tombstone journal
```

此模型接受重大事故期間暫時停止寫入，以換取一人可操作、可稽核且不產生雙主分叉的恢復流程。舊主站一旦失去 production 寫入權，即使稍後恢復，也不得自動與新主站雙向合併或自動 failback。

## 與換機／重裝恢復的接縫

雲端災難復原與裝置換機是同一條恢復鏈的兩層，不是兩套互相競爭的備份：

```text
外部冷備份／PITR
→ 恢復 Supabase 遠端 SSOT
→ 同一 Apple 帳號重新驗證
→ 帳號／relationship／membership
→ 最近聊天與 Moment
→ 歷史分頁與可見媒體漸進載入
```

- `normal` 且伺服器已確認最新狀態時，App 才能顯示「所有內容已同步」。`read_only／recovery` 必須顯示服務狀態、目前內容截至時間、待送數量及可重試狀態，不得把本機快照或未送 Outbox 說成雲端已同步。
- D4 輪替金鑰或重建 Auth 時，可以使全部既有 session 失效並要求 Sign in with Apple 重新驗證；還原必須維持原 Supabase Auth user identity、Apple identity mapping、relationship／membership 與內容所有權。重新驗證後應回到原關係，不重新配對。
- D4 輪替憑證或重建 Auth 時可使舊站 session 全部失效；這是災難復原控制，不是 iPhone MVP 的遠端裝置管理。依 PD-044，產品不建立 session／裝置 inventory，也不提供遺失裝置的遠端撤銷；D4 全面失效仍不是解除配對、帳號刪除或內容刪除，不得產生 deletion tombstone。
- 雲端恢復完成後仍依 PD-033 漸進交付：先恢復身分與關係，再恢復最近內容，最後分頁取得歷史並按可見範圍載入媒體。單一頁面或 object 失敗不得使已恢復內容消失或阻塞核心入口。

## 保護目標與非目標

### 必須保護

- Supabase Auth user、relationship、membership 及授權所需資料。
- 聊天正文、server timestamp、stable client UUID、未讀／排序狀態。
- 照片 metadata、Private Storage object、bytes、checksum 與內容引用。
- Moment、回應、Question Moment 與回答揭露狀態。
- 共同約定、專屬討論、主對話卡片與跨內容引用。
- 顯示名稱、owner-only 私人伴侶稱呼、尚未過期的目前狀態。
- active／archived relationship、owner-only 個人封存、刪除與 GC 狀態。
- schema、RLS、RPC、extensions、Realtime publication、Storage policy、Edge Functions、Auth／Apple callback 及非秘密設定。
- 恢復所需 secrets、recovery codes、signing key 與供應商帳號控制權。

### 明確不保證

- 只存在永久遺失裝置 Outbox、尚未被遠端接受的內容。
- 原始相機畫質；CoupleSpace 只保存共同回顧版本。
- 零停機、零資料遺失或固定公開 SLA。
- 以分析事件、App cache、使用者匯出或推播 payload 重建完整產品資料。
- 在尚未完成演練前宣稱本文件中的 RPO／RTO 已達成。

## 事故分級與應對

| 等級 | 例子 | App 行為 | 後端行動 |
| --- | --- | --- | --- |
| D0 正常 | 所有必要服務健康 | 正常讀寫 | 正常監控與備份 |
| D1 降級 | Realtime、推播或單一非核心 Function 故障 | 基本讀寫可用；改以 RLS 重讀／手動更新 | 隔離故障功能，不切換主站 |
| D2 唯讀事故 | Database／Auth／Storage 不穩定或一致性未知 | 顯示快照；只保留已具安全持久 Outbox 的待送；其他寫入停用 | 停止 migration、GC 與非必要 worker，調查 recovery point |
| D3 同站還原 | 誤刪、錯誤 migration、database corruption | 維持唯讀／恢復中 | 使用 PITR 或受管 backup 還原原 project |
| D4 異區冷重建 | region、控制面、帳號或供應商長時間不可用 | 維持唯讀，切換後要求必要的重新驗證 | 在另一 region／替代環境重建唯一新主站 |

不得只因單一裝置、單一 ISP、DNS cache、憑證或短暫監控失敗進入 D4。跨區切換由人類根據至少兩個獨立健康來源、供應商狀態、資料一致性與預估恢復時間決定，不作自動 promotion。

## 內部 RPO／RTO 目標

以下是正式實作與演練的初始內部目標，不是目前能力或對外承諾：

| 情境 | RPO 目標 | RTO 目標 | 主要控制 |
| --- | ---: | ---: | --- |
| 本機短暫離線 | 已持久 enqueue 內容 0 遺失 | 網路恢復後數分鐘 | Outbox＋stable UUID |
| database 誤刪／錯誤 migration | 最壞約 2 分鐘候選 | 2–4 小時候選 | 7-day PITR；須以實測取代 |
| Storage object 事故 | 1 小時候選 | 4–8 小時候選 | 每小時外部增量副本 |
| region／供應商事故的一致恢復點 | 6 小時候選 | 8 小時候選；大型資料可放寬至 24 小時 | 每 6 小時 DB dump＋較密集 Storage 副本 |

有效的一致 RPO 取 Database 與 Storage 中較舊且已完整驗證的 recovery point；不能因照片每小時複製就把完整系統 RPO 寫成一小時。連續三次相同規模的 drill 達標前，不得向使用者承諾固定恢復時間。

## Production 主站

正式公開前的目標配置：

- Supabase paid production project，與 dev／staging 分離。
- 至少 Small compute 與 7-day PITR；實際方案與價格在採購前重新核對。
- `api.couplespace.app` 類型 custom domain 作長期可攜入口，但不把 DNS 或 custom domain 當成完整 failover。
- 所有 schema、migration、RLS、RPC、Function source 及非秘密設定皆在 Git 可重建。
- 兩把硬體安全金鑰、MFA、密碼管理器與異地離線 recovery codes。
- production runtime 不持有外部備份刪除權，App 不持有 service-role、backup 或 signing secrets。

PITR 處理營運誤刪、錯誤 migration 與 database 層事故；它不包含實際 Storage objects，也不能取代供應商外副本。

## 供應商外冷備份

### 目的端與帳號隔離

首選候選為獨立 Backblaze B2 private bucket，啟用 server-side encryption、Object Lock 與 lifecycle；若採其他 S3-compatible provider，必須維持相同的帳號隔離、不可變保存與可驗證還原能力。

- 備份帳號不得與 Supabase 共用登入、密碼或 MFA recovery path。
- 自動化只取得來源 read/list 與目的端必要 write/list 權限。
- 解除 Object Lock、批次刪除、restore 及帳號復原權限不得放進 App 或日常 CI secret。
- 內容在離開 Supabase 前以受審查工具作 client-side encryption；B2／其他目的端只見密文物件。
- signing private key 與 backup decryption key 分離；其中一份可用的離線副本須異地保存。

### Database logical dump

目標頻率為每 6 小時，並在 schema／RLS／RPC／Auth 相關 production 變更前後各建立一個具名 recovery point。

每次成功工作至少產生：

- 壓縮且 client-side encrypted 的 logical dump。
- dump SHA-256、開始／完成時間、Postgres version、schema／migration version。
- 主要表的 count、min／max server timestamp 與可比對的非內容統計。
- 對應 Storage recovery manifest 及 deletion journal sequence。
- backup tool／workflow version 與不可變 artifact identity。

工作須串流壓縮與加密，避免在 runner 落地未加密完整 dump；stdout、錯誤 log、通知與 artifact 名稱不得包含正文、照片路徑中的敏感使用者文案、connection string 或 secrets。任何步驟失敗都不得更新 `last_successful_backup_at`。

### Storage objects

目標頻率為每 1 小時增量 `copy`，不對目的端執行即時鏡像刪除：

- Supabase Private Storage 是來源；外部 bucket 不是 App runtime 的第二個讀取來源。
- 使用穩定 object identity，比對 bytes、版本／時間與 checksum；新正式上傳流程須保存可稽核的 SHA-256，不能只依賴不一定代表完整內容的 multipart ETag。
- 目的端保存 object version；來源刪除不能立即摧毀仍在 backup retention 內的版本。
- Database snapshot 有引用但目的端找不到相符 object、bytes 或 checksum 時，該 recovery point 為 `FAIL`。
- 目的端多出但 Database snapshot 沒引用的 object 保持隔離，不因存在就重新公開或重新建立產品引用。

### Recovery manifest

每個 Database recovery point 必須有 machine-readable manifest，至少包含：

```text
recovery_point_id
started_at／completed_at
schema_version／migration_version
database_artifact_id／sha256
storage_snapshot_at
storage object_id／path／bytes／sha256／reference type
deletion_journal_sequence
deletion_journal_event_hash
backup workflow version
verification result
```

還原以 Database metadata 與 manifest 的引用集合為準。Database 與 Storage 不必在同一毫秒完成，但目的端必須已保存 recovery point 所引用的每個 object 版本。

## 刪除、解除配對與舊備份復活防護

舊備份可能早於使用者刪除、解除配對或 Storage GC。任何 restore 若未重播較新的刪除事件，就可能讓已刪內容重新可見，因此需有獨立的 append-only DR deletion journal。

### Tombstone 最小內容

- 不可重用的 event UUID 與遞增 sequence。
- stable operation ID、server timestamp、不可回連 live Auth identity 的 opaque actor ref 或 `system`、relationship／account scope。
- entity type 與精確 entity／object identity。
- action 採 W14 canonical 名稱：`content_delete`、`unpair`、`archive_delete`、`account_delete` 或 `object_gc`。
- 已核准生命週期規則版本及 event hash。
- 不保存訊息正文、照片內容、Moment 文案、Emoji 值、回答或約定文字。

W14 的[資料生命週期與基本匯出契約](03-w14-data-lifecycle-contract.md#audit-與-tombstone)是 tombstone 欄位名稱、actor 去連結、action enum、hash chain、compaction checkpoint 與 condition-based retirement 的 canonical refinement；每個 recovery manifest 必須同時綁定 deletion journal sequence 與該筆 event hash。本文件的備份天數候選不得改變該資料生命週期語意。

尚無任何 deletion event 的空 journal manifest 固定記錄 `deletion_journal_sequence = 0` 與 64 個小寫 ASCII `0` 的 `deletion_journal_event_hash`；不得以 `null`、空字串或省略欄位表示。

### 寫入與完成語意

1. production transaction 先移除正常存取權並建立 tombstone／外送工作。
2. worker 將加密 journal 增量寫入供應商外不可變目的端；目標 freshness 為 15 分鐘。
3. 使用者介面可立即反映 production 不可存取，但「所有備份完成淘汰」不得在 retention 結束前宣稱。
4. 任一舊 recovery point 還原後，先重播其 manifest sequence 之後的所有 tombstone，再開放登入與讀取。
5. tombstone 缺段、sequence 不連續或重播失敗時保持隔離並判定恢復 `BLOCKED`。

### 保存政策

- backup object 前 14 天採不可變保護候選。
- 日常可恢復版本保留 35 天候選，之後依 lifecycle 淘汰。
- 不建立含永久私人正文的年度全量備份；長期保留只保存不含私人內容的 drill evidence、統計與設定版本。
- production 刪除後資料立即不再供產品存取；不可變備份中的密文於最長保存期內淘汰。正式隱私文案須說明此時間邊界，實際天數在法規與供應商設定核對後才可對外定案。

## App 事故模式與 service manifest

### 使用者可見狀態

- `normal`：正常讀寫。
- `degraded`：部分能力延遲；仍可安全完成的核心讀寫繼續，Realtime 失效時改用 RLS 重讀。
- `read_only`：顯示 user＋relationship scoped 快照；只有已具可靠持久 Outbox 的內容可明確排隊，其他建立／修改入口停用。
- `recovery`：後端已恢復但仍在核對；先開放必要驗證與唯讀，分批恢復寫入、媒體、推播與 GC。

事故時不得要求使用者刪除 App、主動登出、重新配對或反覆重送；D4 因 session 全面失效可要求一次必要的 Apple 重新驗證，但不得改變原帳號與關係。也不得把本機 cache 說成雲端備份，或將尚未由伺服器接受的內容顯示為成功。

### 簽章式 service manifest

App 需能從不依賴 production Supabase 的靜態端點取得最小 manifest，內容只允許：

- manifest version、environment、mode。
- Supabase／API endpoint 與 publishable key。
- status page、最低安全 App version、issued／expires time。
- Ed25519 或同級 detached signature。

App 內嵌驗證 public key，只接受 HTTPS、正確 environment、有效簽章、未過期且 version 不倒退的 manifest，並保存最後一份合法設定。private signing key 保持離線；manifest 不得承載 service-role、database、APNs、backup 或其他秘密，也不得演變成可遠端改寫產品行為的通用 feature flag 系統。

Custom domain 可降低長期 URL 搬移成本，但新 project 的 Auth、publishable key、Functions、Realtime、Storage 與 Apple callback 仍需重建；signed manifest 與 re-authentication 路徑不能由 custom domain 取代。

## 備份排程與 dead-man monitoring

初始目標：

| 工作 | 頻率 | freshness 阻擋線 |
| --- | ---: | ---: |
| Database logical dump | 每 6 小時 | 超過 8 小時告警 |
| Storage incremental copy | 每 1 小時 | 超過 2 小時告警 |
| Deletion journal export | 每 15 分鐘 | 超過 30 分鐘告警 |
| Manifest／hash 結構驗證 | 每次備份 | 任一錯誤立即告警 |
| 隨機 object 完整性抽查 | 每週 | 任一 mismatch 阻擋最新 recovery point |
| Synthetic full restore | 每月 | 超過 35 天未成功告警 |
| 隔離 production-backup restore drill | 每季 | 超過 95 天未成功阻擋公開 release |

排程器可能延遲、停用或漏跑，所以成功工作須向獨立 dead-man monitor 回報；「沒有失敗通知」不等於成功。警報至少透過兩條不依賴 CoupleSpace production Supabase 的通道到達營運者。

主要告警另包括：API／Auth／Database／Storage 分項健康、最老 Outbox age、備份大小異常下降、主要資料 count 異常、object／metadata 差距、Object Lock／lifecycle 變更、成本／egress 斜率及最近 restore drill 時間。

## D3／D4 恢復 Runbook

### 0. 宣告與隔離

1. 建立 incident ID、時間線、事故等級與決策人。
2. 發布外部狀態頁，signed manifest 切到 `read_only`。
3. 停止 deploy、migration、GC、批次刪除、非必要 worker 與可能改寫證據的工作。
4. 保存健康檢查、供應商狀態、最後可信寫入、最後成功 DB／Storage／journal 時間；不得覆寫任何備份。

### 1. 選擇 recovery point

- 基礎設施毀損：選最新 `PASS` 且三種 artifact 齊全的 recovery point。
- 誤刪／錯誤 migration：選第一筆錯誤操作之前。
- 帳號入侵：選確認未受污染的時間，並先輪替控制面憑證。
- 記錄選擇理由、預估資料缺口、manifest ID 與 deletion journal sequence。

### 2. 重建

1. D3 在原 project 執行受管 PITR；D4 在另一 region／核准替代環境建立新 project。
2. 依鎖定版本部署 extensions、schema、RLS、RPC 與必要設定。
3. 還原 Database artifact。
4. 依 manifest 恢復所有被引用 Storage object 版本。
5. 部署 Functions，重建 Auth、Sign in with Apple callback、Realtime publication 與 bucket policy。
6. 重播較新的 deletion tombstone。
7. 輪替 database、service-role、publishable、APNs、webhook、backup 與其他可能受影響憑證。
8. 維持外部入口唯讀，不在驗證完成前接受 production 寫入。

### 3. 開放前驗證

- migration／schema version 與 manifest 相符。
- 主要表 count、時間邊界、stable UUID 唯一性與 reference integrity 相符。
- 每一個產品 photo reference 都能找到 bytes／checksum 相符的 object。
- tombstone sequence 連續，已刪內容、解除配對與 GC 不會復活。
- active／archived relationship、owner-only archive 與第三人隔離符合 RLS。
- Auth、Apple re-authentication、Realtime hint＋RLS reread、push privacy 可用。
- 原 Auth user identity、Apple identity mapping 與 relationship／membership 對應保持一致；舊站 session 因 D4 全面失效且重新驗證不產生 deletion tombstone，也不因此建立產品 session／裝置 inventory。
- 兩支真實 iPhone 中至少一支清除本機狀態後可恢復完整授權與歷史，不需重新配對。
- 舊 Outbox 恢復後只送達一次、順序正確，不把舊 relationship 內容送往目前 relationship。

任何缺圖、靜默清空、越權、引用斷裂、刪除復活、重複、錯序或需要重新配對均為 `FAIL`；artifact、權限或裝置不足導致無法執行為 `BLOCKED`，都不得開放寫入。

### 4. 分階段恢復

1. manifest 切至 `recovery`，先開放 re-authentication 與唯讀。
2. 觀察錯誤率、RLS denial、缺 object、Auth 與成本。
3. 恢復低風險文字寫入與 Outbox drain。
4. 再恢復媒體上傳、Realtime、推播、刪除 worker 與 GC。
5. 通過觀察窗後切回 `normal`，在狀態頁記錄實際影響、資料 recovery point 與已知缺口。

### 5. 舊主站處理

新站接受第一筆 production 寫入後即成為唯一 SSOT。稍後恢復的舊站只作 forensic source；不得自動 failback。若需補資料，只允許經 relationship 授權、stable UUID、server time 與內容 hash 可證明的單向一次性匯入，並須另有變更計畫與驗證。

## 演練與證據

### 每次備份

- artifact 存在、大小合理、hash 正確、manifest 可解析。
- 可用隔離 credential 讀取並解密最小測試區段。
- 沒有 secrets 或私人內容進入 log／通知。

### 每月 synthetic drill

使用 production-shaped 合成資料驗證 relationship、message、Moment、photo、appointment、archive、delete、unpair、tombstone 與 RLS；不得把 synthetic 通過當成真實 production backup 已可恢復。

### 每季 production-backup drill

- 在隔離、無 production traffic 的暫時 project 還原真實加密備份。
- production 內容不供人工日常瀏覽；以 counts、hash、constraint、RLS 與自動化 reference checks 驗證。
- 記錄實際 RPO、各階段耗時、missing／mismatch、工具版本、費用與清理結果。
- drill 完成後依核准程序銷毀暫時環境；刪除本身需留非內容型 audit evidence。
- schema、Storage path／policy、Auth、encryption、delete／unpair、backup pipeline 或 endpoint 切換有變更的正式版本，須在該版本重跑受影響 drill。

## 一人營運與 break-glass

營運者本人也是單點，須有一份加密且異地可取得的 emergency operations kit：

- 供應商、DNS、Apple、GitHub、status page 與監控帳號清單。
- 兩把硬體安全金鑰與離線 recovery codes。
- backup decrypt key、manifest signing key 的分離備份與輪替程序。
- 最新 runbook、recovery manifest schema、可信工具版本與完整性 hash。
- 如何切唯讀、發布狀態、聯絡供應商及將事故交接給指定技術協助者。

可信任緊急聯絡人平時不取得私人內容閱讀權；其優先權限只涵蓋發布狀態、停止寫入、取得密封 runbook 與聯絡供應商。任何 break-glass 內容存取仍須最小權限、原因、限時與 audit log。

## 成本與升級觸發

依 2026-08-13 公開價格建立的初始規劃情境約為每月 US$140–150：Supabase Pro、Small compute、7-day PITR、custom domain，加上小量外部備份與監控。這是預算假設，不是採購、帳單或長期固定價格；正式採購前須重新核對供應商價格、稅、egress、資料處理條款與 subprocessor。

不以降低月費為由移除已通過的資料安全 gate。只有下列證據出現時才重新評估 warm standby、read replica 或其他供應商：

- restore drill 連續無法達成核准 RTO。
- 單一 region 事故頻率或付費使用者風險已超過冷備援承受範圍。
- backup／restore 資料量超過現有 runner、egress 或人工操作能力。
- 法規、企業合約或已驗證營收要求更低 RPO／RTO。

## 實施與發布 Gate

### G15／TestFlight 候選版前

- 建立 production-like 外部加密 DB／Storage backup 與 manifest。
- 具 dead-man alert，至少完成一次 synthetic full restore。
- App 的 `read_only`／`recovery` 行為與未同步語意可測。
- 清空本機狀態的真機恢復與一致版本 Database＋Storage drill 通過。

### G17／正式公開前

- production paid plan、PITR、custom domain、外部不可變備份、deletion journal、status page 與 emergency operations kit 可用。
- signed service manifest、另一 region 冷重建腳本與完整 D4 drill 通過。
- release record 記錄實際 RPO／RTO、artifact、mismatch、RLS、刪除重播及清理證據。

### 正式營運後

- 每月 synthetic restore、每季 production-backup 隔離 restore。
- freshness 或 drill 過期時停止正式發布；若 backup 已越過核准 RPO，先將事故風險處理為營運阻擋，不繼續擴大投放。

## 外部依據

- [Supabase：Database Backups／PITR](https://supabase.com/docs/guides/platform/backups)
- [Supabase：Restore to a new project](https://supabase.com/docs/guides/platform/clone-project)
- [Supabase：Download Storage objects](https://supabase.com/docs/guides/storage/management/download-objects)
- [Supabase：S3 compatibility 與 versioning 限制](https://supabase.com/docs/guides/storage/s3/compatibility)
- [Supabase：Custom Domains](https://supabase.com/docs/guides/platform/custom-domains)
- [Supabase：Production Checklist](https://supabase.com/docs/guides/deployment/going-into-prod)
- [Backblaze：Object Lock](https://www.backblaze.com/docs/cloud-storage-object-lock)
- [Backblaze：B2 Pricing](https://www.backblaze.com/cloud-storage/pricing)
- [GitHub：scheduled workflow 可能延遲或漏跑](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
