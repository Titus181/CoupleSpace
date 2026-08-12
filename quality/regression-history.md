---
status: active
last_updated: 2026-08-12
---

# CoupleSpace 回歸紀錄

本表保存已發生且必須永久防止重現的缺陷。新增事故時，先加入最低可靠層級的 regression，再記錄 catalog ID 與修正證據。

| Regression | 發現階段 | 失敗 | 永久防線 |
| --- | --- | --- | --- |
| REG-001 | W4 真機 | 雙方同時建立邀請後，各自占用 active 單人成員 relationship，無法直接接受對方邀請 | `PAIR-001`／`PAIR-002`：取消 RPC 的 pgTAP、PairingModel tests 與雙真機恢復清單 |
| REG-002 | W4 真機 | 邀請拒絕或失效後只顯示文案，沒有可操作的重試入口 | `PAIR-002`：PairingModel／UI regression 與拒絕、失效 token 輪替人工 gate |
| REG-003 | W5 真機 | 最新 Moment 是照片時，Image hit-test 區域攔截「留下 Moment」按鈕 | `MOMENT-002`：預載照片 UI case 實際點擊 composer |
| REG-004 | W5 full suite | Launch matrix 留下橫向狀態，污染後續一般 UI cases | UI test `setUpWithError` 回復直向，完整串行 scheme 驗證 |
| REG-005 | W6 full suite | 元素在 ScrollView 外或 selector 不可見，聚焦 UI tests 通過但完整 suite 失敗 | `INTERACT-001`／`QUESTION-001`：只 assertion 可見元素並在必要時條件式捲動，完整 suite 重跑 |
| REG-006 | W7 UI | Partner 卡 accessibility identifier 同時落在多個文字元素，selector 命中多筆 | `STATUS-001`：明確 selector 與伴侶左、本人右的位置 regression |

## 新增格式

新增一列時至少記錄：穩定 Regression ID、發現版本／階段、使用者可見影響或資料風險、修正 commit、對應 catalog ID、測試路徑，以及為何舊測試未攔住。若只能人工驗證，必須連到 `manual/` 的精確步驟。
