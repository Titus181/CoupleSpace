---
title: CoupleSpace Project Harness
status: active
last_updated: 2026-08-12
---

# CoupleSpace Project Harness

## 目的

讓人類與 AI Agent 以可重現、可審查、可回復的方式修改 CoupleSpace，並用與風險相稱的證據確認新行為和既有核心流程沒有退化。

## 分層

### 共享層

- 固定版本：`../harness-version.yaml`
- 共用 Skills：`../.agents/skills/`
- 共用 Rules：`../.harness/shared/rules/`

共享層是指定 release 的 vendored snapshot，不追蹤 `agent-harness/main`。

### 專案層

- Agent 入口：`../AGENTS.md`
- 架構與依賴邊界：`ARCHITECTURE.md`
- 產品範圍：`product/04-iphone-mvp-scope.md`
- 開發目標：`operations/01-v1-development-roadmap.md`
- Agent Evals：`../evals/README.md`
- 測試控制中心：`../quality/README.md`

CoupleSpace 的產品事實、私人資料限制、Apple 平台驗證與完成條件只保存在產品 repo。

## 主要風險

風險由高到低排序：

1. 私人內容傳給錯誤使用者，或由通知、分析、log 洩漏。
2. 訊息或 Moment 遺失、重複、錯序，尤其在離線與重試期間。
3. 解除配對、刪除、匯出後雙方資料結果不一致。
4. 身分、配對或共同資料的授權邊界錯誤。
5. 跨兩支裝置同步、推播、App Lock 等只在單機測試中看似正常。
6. iPhone MVP 被尚未驗證的 Watch、多平台或非首版功能拖延。

高風險項目不能只以畫面可操作或單一模擬器測試作為完成證據。

## 工具與權限

Agent 可以在專案範圍內讀取、修改程式、文件與測試，並執行本機 build、Simulator 測試、Harness 檢查及 Git 唯讀檢查。

下列操作必須先取得人類明確批准：

- TestFlight／App Store 上傳與發版。
- CloudKit production schema promotion、production data write 或 migration。
- 對真實使用者傳送推播、Email、邀請或其他外部訊息。
- 刪除或重設真實帳號、共同資料、照片或 production container。
- 新增付費服務、秘密、憑證或提高 Agent 權限。

秘密使用 Keychain、Xcode signing、CI secrets 或核准的 Secret Manager，不得放入 repo、測試 fixture、log 或 Eval。

## 測試策略

### 測試責任

| 層級 | 主要責任 | 不應承擔 |
| --- | --- | --- |
| Unit | 配對限制、狀態機、排序、冪等、重試、資料生命週期與隱私規則 | Apple 服務是否真的跨裝置運作 |
| Integration | 儲存、同步、repository/service 邊界、照片與通知 payload 組合 | 大量重複 SwiftUI 點擊流程 |
| UI | 登入、配對、Moment、聊天、收藏、時間線等關鍵旅程 | 所有規則排列組合 |
| Real device | 兩個 Apple ID、兩支 iPhone、推播、背景、Face ID、弱網與跨裝置同步 | 可由快速 deterministic unit test 覆蓋的純邏輯 |
| Agent Eval | Agent 是否遵守範圍、架構、測試與隱私規則 | App runtime correctness 的替代品 |

### Gate A：每次行為改動

- 先確認受影響功能與失敗風險。
- 新增或更新最低可靠層級的測試。
- 執行 affected tests 與 affected target build。
- 行為、資料格式或權限改變時同步更新文件。

### Gate B：PR 合併前

- 完整 iPhone unit suite。
- 受影響的 integration/UI tests。
- iPhone target build。
- Watch 或共享程式受影響時，執行 Watch suite。
- `project-harness.sh check`、Agent Evals、`git diff --check`。
- 人類 review 高風險資料、權限、通知、分析與 migration 變更。

### Gate C：Nightly／定期回歸

CI 建立後，將較慢的完整 integration/UI matrix、離線重試、資料 migration、不同權限與語系情境放在此層。Nightly 失敗必須可追蹤，不得因不阻擋單一 PR 就長期忽略。

### Gate D：TestFlight／Release

至少記錄以下人工或自動證據：

1. 兩個新 Apple ID 在兩支真實 iPhone 完成登入與一對一配對。
2. `Moment／共同約定 → 回應／約定討論 → 對話 → 收藏 → 共同時間線` 全流程成立。
3. 弱網、離線與重連後，訊息不遺失、不重複且順序可預期。
4. 推播到達正確使用者，鎖定畫面預設不顯示私密內容。
5. App Lock、背景切換與重新啟動行為正確。
6. 匯出、刪除與解除配對依已核准規則執行，雙方結果一致。
7. 分析事件不含私密訊息或照片內容。

實際測試 ID、人工清單、阻擋規則與每版證據格式以 `../quality/test-catalog.md`、`../quality/release-gates.md` 及 `../quality/release-record-template.md` 為準。正式版本更新前必須執行目前全部自動化測試，以及所有適用的 Critical／High 人工 gate；未執行、blocked、failure 或最後行為改動前的歷史結果都不能視為通過。

G1 尚未決定的技術方案，在完成兩支真機／兩個 Apple ID 的小型驗證前不得標示通過。

## 失敗處理與回復

- 資料錯發、遺失、通知洩漏、解除配對不一致或授權錯誤：停止新增功能，先修正並加入 regression case。
- 自動化測試不穩定：隔離根因並修復；不可用無條件 retry 或刪除 assertion 掩蓋。
- Harness 升級造成退化：revert 該產品升級 commit，將失敗加入 CoupleSpace Eval，再由共享 Harness 發修正版。
- App 行為退化：優先 revert 最小造成退化的 commit；資料 migration 必須另有可驗證的 forward／rollback 計畫。

## Local Overrides

- iPhone 核心循環優先於 Watch 與其他 Apple 平台。
- 私密內容、通知與資料生命週期變更必須提高驗證層級。
- 「所有功能仍正常」必須由分層回歸證據支持，不以單一 build 成功取代測試，也不要求每個功能機械式重複所有測試類型。
- 無法在 Simulator 可靠驗證的 Apple 平台行為，必須明確標記為待真機驗證，不得推測通過。

## Harness 升級

1. 只選擇已發布的 SemVer tag。
2. 在非 `main/master` 的乾淨分支執行 `project-harness.sh upgrade`。
3. Review vendored diff 與權限變化。
4. 執行 CoupleSpace tests、Evals 與相稱的真機 gate。
5. 經人類 Review 後以 PR 合併。

CoupleSpace 專用規則應優先留在本 repo。只有可跨多個專案重用的能力，才移回共享 Harness 並發布新版本。
