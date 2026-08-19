---
status: active
last_updated: 2026-08-20
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
| REG-007 | W9 雙真機弱網 | FIFO 隊首失敗後，後續訊息永久停在「傳送中」且無法操作 | `CHAT-002`／`NETWORK-001`：失敗隊首傳播、blocked 項目可重試及 FIFO 人工 gate；收斂於 `6c0f4e3` |
| REG-008 | W9 雙真機重連 | Realtime refresh 執行中收到的事件被丟棄，伴侶必須重啟 App 才看到新內容 | `CHAT-002`／`NETWORK-001`：follow-up refresh、重建 subscription 與前景重連雙機 gate；收斂於 `6c0f4e3` |
| REG-009 | W9 離線冷啟動 | 已登入配對者離線重開卻跳出帳號設定，或三分頁顯示成全新空白 | `TODAY-001`／`CHAT-002`：relationship／Today／conversation scoped 快照、離線 UI regressions 與雙機 gate；收斂於 `6c0f4e3` |
| REG-010 | W9 離線傳送 | 離線按傳送後輸入已清空，但內容未成功寫入 Outbox | `CHAT-002`：enqueue 成功才清空、store recreation unit／UI regression；收斂於 `6c0f4e3` |
| REG-011 | W11 離線重啟 | 待送改期仍存在，但缺少已同步約定快照，冷啟動顯示空白或「無法更新共同約定」 | `APPOINTMENT-001`／`NETWORK-001`：user＋relationship scoped 約定快照、200 筆上限與離線重啟 regression；收斂於 `194c341` |
| REG-012 | W11 離線重啟 | 快照恢復後先顯示舊時間，必須等遠端 refresh 才套用本機待送改期 | `APPOINTMENT-001`：遠端懸停測試要求 refresh／delivery 前先依 FIFO 疊加 pending operations；收斂於 `194c341` |
| REG-013 | W11 離線 UI | 全域離線提示遮住約定詳情／編輯頁左上導覽控制 | `APPOINTMENT-001`：完整 UI 路徑確認底層提示不可互動且取消按鈕可操作，另保留真機視覺 gate；收斂於 `194c341` |
| REG-014 | W13 雙真機 5C | B 停留「今天／我們」時，A 傳文字或照片後未讀先增加、隨即被錯誤歸零 | `CHAT-001`／`W13-INTEGRATION-001`：同步且實際畫面導向的 visibility、離開畫面後拒絕舊 read 回寫、latest-only badge response、message-bound migration 039／pgTAP，以及 5C 雙真機清單；舊測試只覆蓋對話可見時自動已讀，未覆蓋 hidden／in-flight 競態；同一最終候選的雙真機 LOCK／PUSH／5C／W8 回歸已通過，收斂於本次 W13 closure changeset |
| REG-015 | W13 Slice 8 lifecycle audit | model 已 stop、登出或切換 scope 後，較晚完成的 start／refresh／observer／drain 仍可能重寫舊 cache／UI、重新掛 observer 或加入提醒 | `W13-INTEGRATION-001`：Moment／Together Now／Conversation／Shared Appointment 共用 lifecycle generation，stop 先失效並 join 已在途 side effects；`CoupleSpaceTests/CoupleSpaceTests.swift` 覆蓋 delayed start／refresh、stale callback、cache write、observer 與 reminder reconcile；focused unit 191／191、最終本機 Gate C 236 definitions／239 executions、linked migration 040 與同一最終候選的雙真機 local logout／W9–W11／lifecycle 整合均通過，收斂於本次 W13 closure changeset |
| REG-016 | W13 Slice 8 background push audit | appointment background refresh 在 logout、account／relationship switch 或 closing cleanup 後完成，可能用舊 context 復活已移除的本機提醒 | `APPOINTMENT-001`／`W13-INTEGRATION-001`：完成 fetch 後重驗 Auth user＋active relationship，scheduler generation conditional activation 讓 terminal cleanup 勝出；unit 覆蓋四種 context 變更與 cleanup-wins 競態，最終本機 Gate C、linked migration 040，以及同一最終候選的雙真機 PUSH／約定提醒／lifecycle 整合均通過，收斂於本次 W13 closure changeset |

## 新增格式

新增一列時至少記錄：穩定 Regression ID、發現版本／階段、使用者可見影響或資料風險、修正 commit、對應 catalog ID、測試路徑，以及為何舊測試未攔住。若只能人工驗證，必須連到 `manual/` 的精確步驟。
