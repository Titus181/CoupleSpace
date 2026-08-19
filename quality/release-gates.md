---
status: active
last_updated: 2026-08-19
---

# CoupleSpace 版本發布閘門

任何 gate 只接受最後一次行為影響變更之後的新證據。Build 成功、`build-for-testing` 成功或歷史版本曾通過，都不能代替本次 runtime 測試。

## Gate A：每次行為改動

- 指出受影響的 catalog ID、風險與最低可靠測試層級。
- 新功能加入測試；bug fix 在可行時先加入能重現問題的 regression。
- affected tests 與 affected target build 通過。
- 資料格式、權限、migration 或產品行為改變時同步文件。
- 失敗、skip 或 flaky case 未處理前，不宣稱切片完成。

## Gate B：垂直切片／合併前

- 本次切片的 database、unit、integration 與關鍵 UI tests 通過。
- 完整 iPhone automated suite 在最終程式變更後通過。
- Watch 或 shared behavior 受影響時，Watch suite 通過。
- Harness、適用 Agent Evals 與 `git diff --check` 通過。
- migration、RLS、通知、分析、刪除與資料生命週期變更經人工 review。

## Gate C：TestFlight release candidate

- 執行 `quality/scripts/run-full-automated-suite.sh --reset-local-database`。
- 使用兩支真實 iPhone、兩個 Apple 身分完成所有適用 `manual/` 清單。
- 若版本影響 W8–W11 的聊天、離線快照、Moment 來源或共同約定，依 `manual/w8-w11-regression.md` 的順序完成整合回歸；其中連結的個別 manual 清單仍是詳細步驟 SSOT。
- 若版本影響 W13 的同帳號多裝置、目前裝置登出／重新登入恢復、App Lock、推播、未讀／badge、本機提醒或解除配對整合，完整執行 `manual/w13-integration.md`；Simulator preflight 不能取代其中的兩支真實 iPhone 證據。已退役 `SESSION-001` 不重跑，但必須確認正式 inventory／remote-revoke UI 與 runtime 均已移除。
- `SESSION-001 = NOT_APPLICABLE (REMOVED)` 只記錄 PD-044 的 scope removal，不提供 G12／W13 PASS credit；`W13-INTEGRATION-001` 與其引用的全部適用 gate 仍須獨立通過。
- 從空本機資料庫依 migrations 重建，完整 pgTAP 與 local schema lint 通過。
- linked／staging migration history 與 schema lint 通過；任何部署仍需明確授權。
- 以舊 build 建立資料與本機待送項目，再安裝 release candidate，確認升級、重登與恢復不重複、不錯序、不遺失。
- `DR-001` 的 production-like encrypted Database／Storage backup、recovery manifest、freshness alert、synthetic restore，以及 App `read_only／recovery` 行為通過；未部署 production 付費能力時須明確記為 G17 尚待 gate，不得假裝正式 DR 已完成。
- 記錄 `.xcresult` 的 executions、failure、skip 與 exit status，不只記錄命令成功。
- 產生一份 `release-record-template.md` 的版本副本，未驗證項目不得留白。

## Gate D：正式公開發布

Gate C 全部通過後，還必須完成：

- Production 相符環境的 push、StoreKit、entitlement、語系與權限提示驗證。
- Production PITR、供應商外加密不可變 Database／Storage 備份、recovery manifest、deletion journal 與 dead-man freshness 監控可用。
- `DR-001` 在另一 region／核准替代環境完成 Database、Storage、Auth／Functions／設定與刪除 journal 的一致 recovery point 冷重建；counts、checksum、引用、RLS、第三人隔離、signed manifest 及清空本機狀態真機恢復全部通過。
- Phased release、監控、狀態頁、暫停發布、降級與回復方案可用。
- 所有 Critical／High release gate 為 PASS；沒有以 WAIVED、歷史結果或「不適用」掩蓋尚未實作的必要能力。
- 發布 commit、build、schema version、App Store version 與證據可互相追溯。

## 阻擋規則

以下任一情況都必須停止發布：

- 私人內容可能傳給錯誤使用者，或由推播、分析、log、fixture 洩漏。
- 訊息、Moment、照片或狀態可能遺失、重複或錯序。
- RLS、身分、配對、刪除、封存或解除配對結果不一致。
- 必要測試 failure、skip、未執行或結果早於最後行為變更。
- Migration 不能由舊 schema 安全升級，或沒有 forward／recovery 計畫。
- 最新完整 recovery point 超過核准 RPO、tombstone journal 有缺段、restore drill freshness 過期，或 incident mode／signed manifest 無法安全阻止寫入與版本倒退。
- Flaky test 只能靠重跑才通過。
- Release candidate 與實際準備發布的 commit／build 不一致。

## 測試結果語意

- `PASS`：本次版本、指定環境、指定 commit 的預期結果全部成立。
- `FAIL`：實際結果不符合預期；阻擋相關 gate。
- `BLOCKED`：因裝置、Apple 服務、權限或環境無法執行；不是通過。
- `NOT_APPLICABLE`：本版確實不含該能力，或已由 accepted 決策明確移除且沒有殘留 UI／runtime；必須寫理由及取代決策，不能用來隱藏仍存在的必要能力或歷史 FAIL。
- 不使用 `WAIVED` 把 Critical／High 風險帶入正式發布。

## 執行頻率

- 每次 edit：affected tests。
- 每個完整切片／合併：Gate B。
- 每個 TestFlight build：Gate C 中與 build 及 changed risk 相關的人工項目，加上全部自動化測試。
- 每個正式公開版本：Gate C＋Gate D 全部適用項目。
- Synthetic restore 每月至少一次，production-backup 隔離 restore 每季至少一次；備份／drill freshness 超過 `docs/architecture/01-disaster-recovery.md` 的阻擋線不得正式發布。正式版本若改到 schema、Storage、Auth、encryption、delete／unpair、backup 或 endpoint 流程，必須在該版本重新執行受影響 drill。
