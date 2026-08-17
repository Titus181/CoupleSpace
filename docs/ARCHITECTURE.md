---
title: CoupleSpace Architecture
status: provisional
last_updated: 2026-08-13
---

# CoupleSpace Architecture

## 系統目的

CoupleSpace 提供一對一伴侶私密互動空間。iPhone MVP 聚焦配對、Moment、基本共同約定與其專屬討論、聊天、收藏、共同時間線、通知隱私與資料生命週期。

Watch、macOS、visionOS、Widget、訂閱、公開社群與 AI 關係分析不是目前核心。詳細範圍以 `product/04-iphone-mvp-scope.md` 為準。

## 目前狀態

- TD-001 已接受 Supabase 作為 iPhone v1 使用者身分、伴侶關係、共同資料與資料生命週期的唯一遠端系統紀錄；正式 App 不使用 CloudKit／Supabase 雙寫。
- G1／M0 已於 2026-08-11 通過：兩支真實 iPhone、兩個 Apple 身分完成 development 登入、配對、雙向 marker／message／photo、五輪弱網／跨啟動 Outbox 與雙向背景／終止／鎖定 sandbox 推播。production／TestFlight、大型封存、實際低磁碟與中斷續傳留在 G13／G15 release gates，不阻擋 W2。
- `CoupleSpace/` 已完成 W2 最小產品骨架：正式入口預設進入「今天」，底部只保留「今天／對話／我們」三分頁；預設 SwiftData `Item` 已移除，W1 Supabase spike 保留為技術證據與後續資料層基礎，不再作為正式 App 首頁。
- G3／W3 已於 2026-08-11 通過。W1 驗證過的 Supabase Sign in with Apple session 已接入正式 App composition：啟動先等待本機 session 恢復，未登入才顯示 Apple 登入；取消與失敗可明確重試，登出需使用者確認，登出失敗時不會把仍有效的 session 誤判為已登出。App 不另建 client-side 帳號資料列，同一 Apple／Supabase identity 沿用同一 user UUID；帳號設定只顯示 UUID 前 8 碼供同帳號複驗。真機已通過取消、登入、登出、強制結束後 session 恢復、離線入口停用與提示，以及同一 Apple 帳號登出再登入後識別碼不變；Apple 登入按鈕維持 50pt 高度。iPhone target build、7 個 affected tests、Harness 與 diff check 均通過。
- G4／W4 已於 2026-08-11 完成。正式 App composition 在登入後加入 relationship gate：未配對者可建立並以系統分享表分享一小時邀請碼、貼上並接受或明確拒絕邀請；邀請失效或拒絕後由原邀請者檢查並重試時在同一 relationship 輪替 token，成功後才進入三分頁，雙方可在帳號設定核對相同 relationship UUID 前 8 碼。切換 Supabase identity 時會先清除上一個 pairing presentation state 並重新經 RLS 讀取，配對前仍保留登出。兩支真實 iPhone 已通過同時各自建立邀請後取消其中一份、拒絕、拒絕後重試、控制式過期後重試、接受，以及雙方收斂至 relationship `632fd4c5…`；控制式過期觸發與自然逾時相同的伺服器判斷，但不宣稱實際等待一小時。最終完整 iPhone automated suite exit 0，本機 Supabase 14 files／156 tests 通過，migrations 001–015 已部署測試專案且 linked schema lint 無錯誤。
- G4A 已於 2026-08-17 完成。migration 032 為每份 invitation 保留既有高熵 UUID token，另產生不含易混淆字元的八位短碼；server 以 advisory lock＋唯一約束處理碰撞，接受／拒絕 v2 RPC 同時支援短碼與舊 token，並以 owner-only server table 限制同一 authenticated user 十分鐘最多五次無效識別嘗試。舊 RPC 不移除，因此部署順序是 backend migration 先於新版 App；client 顯示短碼並可正規化直接輸入或明確標示的分享文字，不把 UUID 前綴當短碼。空資料庫 migrations 001–032、28 files／460 pgTAP 與 local schema lint 已通過；全新 DerivedData 的完整 Gate B 為 163 個測試定義／166 次 executions、0 failure、0 skip，另有 5 個 APNs tests、Harness v0.2.1 與 diff hygiene 通過。linked migration 032 已先部署，遠端 migration 001–032 一致且 linked schema lint 無錯誤；兩支真實 iPhone 的五輪短碼、分享文字、拒絕／取消／輪替、同時邀請、弱網／重啟、限流視窗與受控過期驗收均通過。AirDrop 在 G4A 仍以文字文件交付，受邀者可複製整段文字貼入 App；直接開 App、自動帶入與未安裝落地頁仍屬 G4B。
- G5／W5 已於 2026-08-11 完成。正式 App 的「今天」可建立固定心情、最長 280 字短句或經 W1 圖片處理重新編碼的照片 Moment；「今天」顯示最新一筆，「我們」由同一份資料顯示共同時間線。新增的 `moments` schema、建立 RPC、relationship RLS、私有 Storage 及 Realtime 只接受 active relationship，使用穩定 client UUID 去重，Realtime 事件後仍經 RLS 重讀。migration 016 與 18 個新增 pgTAP 已在本機從零重建，完整 15 files／174 tests 及 local schema lint 通過；migration 016 已部署 Supabase 測試專案，remote migration 001–016 一致且 linked schema lint 無錯誤。兩支真機已完成雙向心情／文字／照片同步、共同時間線順序／去重及強制結束後恢復。最終以全新 DerivedData 串行執行完整 iPhone scheme，73 個 unit tests 與 11 次 UI executions 全數通過且無失敗／跳過；一般 UI tests 會在每個 case 前回復直向，避免 launch matrix 的裝置方向跨案例污染。Xcode 26.6 仍會輸出 LLDB `DebuggerVersionStore.StoreError`／`no debugger version` 警告，但本輪 runner 已進入 `xctest`、完成 `.xcresult` 並以 exit 0 結束，因此不再阻擋 W5。
- G6／W6 已於 2026-08-12 完成。正式 App 可在原 Moment 卡片留下固定 Emoji 或最多 80 字短文字回應，並建立固定題庫 Question Moment；發起者先答，伴侶由 RLS 在自己送出前無法讀取第一份答案，第二份送出後雙方共同揭曉。migration 017 的 response／answer 表、固定題庫、RPC、RLS 與 Realtime 使用 stable client UUID 去重，只接受 active `2/2` relationship；完整本機資料庫為 16 files／201 pgTAP，schema lint 無錯誤，最終全新 DerivedData 的 iPhone scheme 為 76 unit tests 加 15 UI executions 全數通過。migration 017 已部署 Supabase 測試專案，remote migration 001–017 一致且 linked schema lint 無錯誤。兩支真實 iPhone 已通過雙向 Emoji／短文字回應、回答前隱藏第一份答案、第二份回答後共同揭曉、Realtime 收斂及強制結束後恢復；G6／M1 正式完成。
- G6A／W7 已完成。`現在的我們` 以獨立 domain／application／data 接縫提供本人顯示名稱、owner-only 私人伴侶稱呼、七種固定或最多 40 字自訂狀態、1 小時／4 小時／建立者當地今晚／手動清除，以及明確選擇才原子建立的獨立 Moment。migration 018 將帳號層 display name、關係層 private alias 與單筆 current status 分開，RLS 只讓 active partner 讀取共同名稱／未過期狀態，私人稱呼只供設定者讀取；過期由 server time 過濾，狀態不建立伴侶可追查歷史。完整本機資料庫為 17 files／232 pgTAP，local schema lint 無錯誤；全新 DerivedData 串行 iPhone scheme 為 99 個測試定義、動態 launch matrix 展開後 102 次 executions，0 failure、0 skip。migration 018 已部署 Supabase 測試專案，remote migration 001–018 一致、linked dry-run 與 lint 無錯誤。兩支 iOS 26.6 真實 iPhone 已通過名稱、私人稱呼、Realtime、選擇性 Moment、歷史動態換名、逐項清除、未來 30 秒受控到期自動清除，以及各自以原 Apple 帳號逐一登出／重新登入後由遠端恢復帳號、relationship、名稱、私人稱呼與手動狀態。產品訪談／原型另行管理，不阻擋工程 roadmap。
- G7／W8 已完成。正式「對話」分頁直接重用 migration 008 的 relationship-scoped `shared_items` 文字訊息與冪等 RPC，提供最多 4,000 字的一對一文字、伺服器時間排序、Realtime 重讀及分頁未讀數，不顯示已讀狀態。migration 019 只新增每位成員 owner-only 的 conversation read cursor；伴侶與第三人不可讀取，游標只前進不倒退。完整本機資料庫為 18 files／251 pgTAP，local schema lint 無錯誤；W8 關閉前以全新 DerivedData 串行執行完整 iPhone scheme，99 個測試定義、動態 launch matrix 展開後 102 次 executions，0 failure、0 skip。migration 019 已部署 Supabase 測試專案，remote migration 001–019 一致；兩支真實 iPhone 已通過雙向文字、Realtime、未讀數、訊息時間、無已讀標記、強制結束恢復與鍵盤互動。傳送狀態、持久 Outbox、離線重送與順序恢復仍屬 W9，不以 W8 證據提前宣稱完成。
- G8／W9 已完成。正式文字聊天依 TD-002 在遠端 RPC 前先寫入 user＋relationship scoped 的裝置持久 FIFO Outbox，立即以傳送中狀態呈現；輸入框只在本機 enqueue 成功後清空，遠端失敗不會讓尚未保存的文字靜默消失。單一 drain 在冷啟動／登入、回到前景或前景離線→連線時，以立即、1 秒、4 秒的有限策略恢復，耗盡後保留失敗訊息供明確重試。成功沿用 `write_shared_message` stable UUID 與 server timestamp，response 遺失時重送不建立第二則訊息；畫面結束／登出停止後續 retry。首輪雙真機弱網驗收發現 FIFO 隊首失敗時尾端仍顯示傳送中，以及送達後對方需重啟才重讀；修正後隊首失敗會把所有被阻塞項目呈現為可重試，Realtime refresh 會合併執行中收到的事件，前景／網路恢復會重建 subscription、drain 後再重讀。正式 pairing gate 會先依 Supabase user 恢復唯讀 relationship snapshot、立即進入三分頁，再以遠端 RLS 結果校正；Moment、此刻狀態與對話模型平行啟動，避免前兩項網路逾時阻塞 Outbox 初始化。最近 200 則已同步文字，以及已成功讀取的 Moment、Moment 照片、名稱與目前狀態，另以 user＋relationship scope 保存為裝置唯讀顯示快照；離線冷啟動會在遠端要求完成前先顯示快照，狀態仍依本機時間隱藏已過期內容，回到前景或恢復網路後再以 Supabase RLS 重讀校正。這些快照不是遠端備份，也不授權離線新增或修改 Moment／狀態；未同步聊天內容仍只由 Outbox 保存，成功登出、遠端確認沒有 active relationship 或 relationship identity 改變時會清除本機資料。所有寫入仍須通過 Supabase session、RPC 與 RLS。最終兩支真實 iPhone 已通過三分頁離線冷啟動快照、前景 Realtime，以及離線期間新增內容在恢復網路後自動補齊且不需重啟；commit `6c0f4e3` 的完整 Gate B 為 113 個測試定義／116 次通過、0 failure、0 skip，另有 251 pgTAP、schema lint、5 個 APNs tests、Harness 與 diff hygiene 通過。
- 真機首次 W5 回歸發現：當最新 Moment 是照片時，照片 `Image` 的未裁切 hit-test 區域會向上攔截「留下 Moment」按鈕，造成雙方看得到按鈕但點擊無反應。照片在 W5 只是展示內容，現已停用其 hit testing；新增預載照片 Moment 的 UI regression，並以 Simulator 真實點擊確認修正後可重新開啟 composer。這不改變照片資料、RLS 或 Storage。
- Moment schema 與 client domain 保留建立者、回應者與回答者 user UUID；畫面不把當時名稱複製進歷史資料，而是在顯示時依 W7 `TogetherNowSnapshot` 解析目前的本人顯示名稱與 owner-only 私人伴侶稱呼。名稱修改後，既有 Moment、回應與回答會自動改用新稱呼；未設定時以「我／伴侶」呈現，不改寫原始內容、建立者或時間，也不在共同畫面顯示帳號識別碼。
- W8 正式聊天重用 W1 已驗證的文字訊息 schema／RPC，但不把 W1 測試畫面帶入產品介面；照片與資料生命週期 spike 仍只由 Debug 帳號設定中明確標示的「W1 技術驗證工具」提供。帳號設定與配對前的登出均使用標準 alert 確認，不使用錨定在來源按鈕的 confirmation dialog。
- W4 真機回歸發現雙方若同時各自建立邀請，會各自持有一段 active 單人成員 relationship，既有一人一段 active membership constraint 使雙方無法直接接受另一份邀請。migration 015 與正式配對 UI 因此加入建立者主動「取消我的邀請」：Security Definer RPC 只允許刪除 active、未接受、恰有一位 active member，且沒有 shared item、personal archive、push job 或 Storage object 的自己邀請關係；非建立者、已配對或已有內容均拒絕。取消後 client 回到未配對狀態，可改為接受伴侶邀請；真機恢復流程已通過。migration 015 已部署 Supabase 測試專案；遠端 migration 001–015 一致且 linked schema lint 無錯誤。
- App composition 會先驗證明確的 runtime environment 與 Supabase 設定；checked-in build 維持 development environment，production 尚未明確配置前不會被默認為正式環境。
- `CoupleSpaceTests/` 已涵蓋 W2 runtime environment、核心分頁順序／預設入口，以及 W1 設定、登入 session、nonce、冪等／FIFO outbox、排序、照片政策、解除配對與通知隱私等純規則；`CoupleSpaceUITests/` 已加入啟動後預設進入「今天」並可切換三分頁的核心骨架旅程。導覽測試只在明確傳入 `--ui-testing` 時略過啟動動畫；獨立啟動動畫測試仍走正式啟動路徑。
- `CoupleSpace Watch App Watch App/` 是獨立的初始 Watch 畫面，不是 iPhone MVP 必要流程。
- 下列 W1 長段保留完成前的累積實作證據；其末尾原列的「兩支真實 iPhone 仍屬技術閘門」已由 2026-08-11 G1／M0 完成結論取代。大型封存、實際低磁碟與中斷續傳則後移為 release gates。
- Supabase Auth、pairing／RLS、Realtime 變更提示、私有 Storage、marker FIFO outbox、向後相容的多張照片持久 FIFO outbox 及資料生命週期已完成 W1 最小 spike；純文字訊息契約與 FIFO outbox 已完成 migration 008 雲端部署及真機 A＋Simulator B 雙裝置實測，封存正文則僅有本機 pgTAP 證據。遠端測試專案另以第三 authenticated UUID 證明 relationship、memberships、shared items、personal archives 與 Storage objects 均不可見，marker、message、photo finalization 與解除配對 RPC 也全部拒絕。三張照片 queue 已通過同組裝置的斷網、跨啟動、FIFO 重送與跨裝置順序驗證。App 登入完成或由背景回到前景時，會先更新遠端狀態，再以單一 coordinator 依 marker、message、photo 順序立即嘗試一次目前 active relationship 的待送 queue；closing、archived、其他 relationship 與同時重入均不自動送出。真機 A＋Simulator B 已通過背景返回及強制結束後重啟兩條自動 drain 流程，三種 queue 均送達、清空、跨裝置可見且沒有重複；此流程後續已加入三次有限短退避與前景 unavailable→available 監聽候選，真機 A 恢復網路後已自動清空 Outbox，Simulator B 只收到一次；仍不包含 background task、長時間退避或無限輪詢。migration 011 與 client reconciliation 已關閉「Storage upload 成功、metadata 因 closing 被拒絕」可能留下 orphan object／永久卡住 outbox 的競態：已存在的 sealed metadata 視為送達，缺少 metadata 才由原上傳者清除物件；migration 已部署測試專案，真機 A 離線待送＋Simulator B 觸發 closing 的跨裝置時序亦已通過。migration 012 現建立 W1 Free 照片配額候選：App 不可直接建立 photo metadata，Security Definer RPC 會鎖住 relationship、核對私有 Storage object 的 owner 與 bytes，再以 UTC 月曆月 30 張及每段關係 1,000,000,000 bytes 執行原子確認；配額拒絕後 client 會刪除剛上傳的 orphan，網路或清理失敗則保留 outbox。這是 PD-021 的 TestFlight 研究起點，不是正式 entitlement、週期或上市上限；migration 已部署 Supabase 測試專案，真機 A＋Simulator B 的近同時上傳已確認兩個不同 token 均落盤、雙方收斂至同一張最新照片且 Outbox 清空，月 30 張及累積 1 GB 的兩種拒絕與 orphan 清理亦已使用可回收 fixture 通過遠端真機實測。私人推播 migrations 009／010 與 `send-w1-push` Edge Function 已部署 Supabase 測試專案，APNs secrets 已設定且真機 sandbox token 登記成功；sender 以原子 claim／complete 處理只含 routing metadata 的工作，固定送出泛化 payload。Simulator B 已成功把通知送達背景、終止及鎖定狀態的真機 A，鎖定畫面與 Apple Watch 鏡像通知皆只顯示正確泛化文案。個人封存匯出已加入 owner-only RLS 讀取、version 1 JSON manifest、UUID JPEG 檔名與系統資料夾 exporter，並通過真機「儲存到檔案」與內容核對；目前照片改為逐張下載至受保護暫存目錄，`fileExporter` 以磁碟子項目重建不含 staging filename 的根 `FileWrapper`，完成、失敗與下次匯出前會清理專用暫存。已部署測試專案的 migration 013 會把已核對的照片 byte size 一併封存，讓 App 在下載前以 manifest＋照片總大小做暫存容量預檢；舊封存若缺少 size 則保持相容並沿用實際寫入錯誤。PD-022 已接受照片不按時間自動到期，並沿用 active relationship、owner-only 個人封存、明確刪除與最後引用 GC 的既有生命週期；這與目前 schema 行為一致，不需 migration。大型封存真機壓力、實際低磁碟空間與中斷後續傳，以及兩支真實 iPhone 證據仍屬技術閘門。
- W1 畫面會依 Supabase user UUID 保存最近一次由伺服器確認的 relationship UUID、status 與 member count，供斷網冷啟動顯示；這份唯讀快照不作為共同資料寫入授權，所有操作仍須通過 Supabase session、RPC 與 RLS。
- 登入、回到前景或 App 在前景中觀察到網路由 unavailable 轉為 available 後，recovery coordinator 會立即嘗試目前 active relationship 的待送 queue；初次監測即為 available 不觸發額外 drain。失敗且 queue 仍存在時，依 1 秒、4 秒短退避再試，合計最多三次，之後保留 Outbox。真機 A＋Simulator B 已通過登入／前景短暫斷線、三次失敗後保留，以及下一次前景事件送達且不重複；網路轉換觸發亦已由真機 A＋Simulator B 通過前景離線待送、恢復網路後自動清空與跨裝置只送達一次。這只是 W1 前景候選，不提供背景傳送、長時間退避或無限重試保證。
- 照片 Outbox 在寫入已重新編碼 JPEG 前，會以實際 bytes 檢查所在 volume 的已知可用空間；明確不足時不建立檔案或 queue metadata，容量未知時仍由原子寫入錯誤保護。真機正常上傳與 Simulator B 跨裝置讀取已完成回歸；此規則不改變遠端照片配額，也尚未取代真機低磁碟壓力驗證。
- CloudKit Sharing PoC 保留為實驗紀錄，不再是 v1 共同資料候選。

## 目標責任邊界

以下是 G1 已接受的責任與依賴原則，不預先強制資料夾或 framework 數量；W2 依此建立最小可行骨架：

| 責任 | 內容 |
| --- | --- |
| App composition | 啟動、dependency wiring、環境與平台入口 |
| Presentation | SwiftUI 畫面、navigation、顯示狀態與使用者意圖 |
| Application | 配對、Moment、共同約定、約定討論、聊天、收藏、時間線與資料生命週期 use cases |
| Domain | 不依賴 UI／儲存框架的規則、狀態轉換與 value types |
| Data／Services | Supabase Auth、Postgres／RLS／RPC、Realtime 變更提示、私有 Storage、持久 outbox、通知與分析 adapter |
| Platform | Face ID、background、push、Apple framework integration |

## 依賴方向

- Presentation 可以依賴 Application／Domain，不直接承擔同步、授權或重試規則。
- Application 組合 Domain 與抽象 service contracts，不依賴具體 SwiftUI 畫面。
- Domain 不依賴 SwiftUI、SwiftData、CloudKit、通知或分析 SDK。
- Data／Platform 實作上層所需 contracts；外部 payload 不直接成為 Domain model。
- Watch 不成為 iPhone 核心 Domain／Application 的必要依賴。
- 不為尚未出現的第二個實作預建抽象；只有在可測試邊界或平台替換確有需要時才引入 protocol。

## 核心資料流

```text
使用者操作
→ Presentation
→ Application use case
→ Domain 規則與授權判斷
→ Data／Platform adapter
→ 本機 outbox 或 Supabase 受管服務
→ 明確的成功／失敗／重試狀態
→ Presentation
```

任何遠端寫入都必須由 Supabase session 與伺服器端伴侶關係範圍驗證。Realtime 事件只作變更提示，client 必須重新經 RLS 讀取；同步事件與重試使用穩定 client UUID，避免重複建立訊息或 Moment。正式產品資料模型由後續垂直切片依已驗證的不變量最小化建立。

## 敏感資料邊界

- 私密訊息、照片、Moment 內容與伴侶關係屬敏感資料。
- 完整內容由受 relationship RLS 保護的 Supabase 產品資料與私有 Storage 保存，作為跨裝置同步、重新安裝恢復、共同歷史、匯出與個人封存的來源；分析資料不是備份來源。
- 手機遺失、損壞或換機後的恢復只依賴已成功同步的遠端產品資料與 Private Storage，不依賴原裝置 cache；聊天正文、server timestamp、照片、Moment、共同約定、討論、時間線與本人個人封存必須能由新裝置重新取得。只存在遺失裝置 Outbox 的未同步內容不屬於可恢復資料。
- 新裝置恢復採漸進式讀取：先取得 Supabase session、relationship／membership、名稱與仍有效狀態，再取得最近聊天與 Moment；較舊歷史使用穩定 server timestamp＋client UUID 游標分頁，媒體依可見範圍下載。完整歷史可恢復不代表每次啟動一次載入全部資料，任何單頁或單一 object 失敗須可獨立重試。
- 裝置 session 管理與產品資料生命週期分離：撤銷遺失裝置只終止該裝置後續授權，不解除 relationship、不刪除共同內容或 owner-only 個人封存；實際 session inventory、撤銷與再驗證設計須由 Supabase Auth 能力及真機測試關閉。
- 通知預設只帶最小路由資訊；鎖定畫面不得預設揭露內容。
- 分析只記錄產品驗證所需的 relationship、interaction／內容參照、表面與參與種類、participant 與時間，不複製訊息文字、照片、Emoji 值或回答內容。
- production 內容不得提供日常任意瀏覽；必要的 break-glass 維運存取採最小權限、指定原因、限時與 audit log。內容研究須由 relationship 兩位伴侶分別明確同意且可撤回，不得作為功能或權益條件。
- 產品資料庫與 Storage 的雲端災難復原須有獨立備份、還原與演練 gate，不以分析事件或裝置快取替代。
- Log、crash report、測試 fixture 與 Eval 不得包含真實私人資料或 secrets。
- 匯出、刪除與解除配對必須共享同一套已核准的資料生命週期規則。

## 雲端可靠性與成本營運

- Supabase 維持唯一遠端系統紀錄；不為供應商事故或成本焦慮預建 CloudKit／Supabase 雙寫。替代方案必須先有真實瓶頸與遷移證據。
- 資料庫備份與 Storage object 保護是兩個獨立控制；正式上市前須分別定義復原方式並演練，不能把資料庫備份視為照片備份。
- Database restore 與 Storage restore 必須對準同一恢復點，並以 object identity、byte size／checksum 及產品引用清單核對 metadata 與實體檔案；使用者匯出、分析事件、本機 cache 與 Supabase Database backup 都不能單獨取代 Storage object 備份。
- Realtime 只提示變更，client 經 RLS 重讀；離線操作留在持久 outbox，避免短暫事故造成資料遺失或重複送出。
- 照片依 PD-019 在裝置端產生適合共同回顧的版本，不保存相機原檔。確切 display／thumbnail 規格須由畫質、載入、Storage 與 egress 實測決定。
- 照片依 PD-022 不按時間自動到期；配額或方案降級只阻止新增，不刪除既有內容。active relationship 及 owner-only 個人封存持續保存，直到使用者明確刪除；最後一份封存引用刪除後才由既有 GC 清理 Storage object。
- 每週監控 p95 latency、錯誤率、DB／連線、Realtime、outbox age、Storage、origin／cached egress，以及每個活躍伴侶對的直接成本。
- 不對外承諾固定人工事故回覆或復原時間；以自動警報、狀態頁、降級模式、runbook、憑證復原與定期 restore drill 降低單人營運風險。
- TD-003 接受一人可營運的冷備援：Supabase production 是唯一可寫主站；以受管 PITR、供應商外加密 Database／Storage 副本、recovery manifest、deletion journal、signed service manifest 與人工冷重建處理 region／vendor 事故。不得因文件已接受而宣稱 production 備份、切換或 RPO／RTO 已完成。

完整災難復原架構、事故模式與 runbook 見[一人營運災難復原規格](architecture/01-disaster-recovery.md)；客服、版本公告、成本情境與上市 gate 見[上市、客服與版本發布營運](operations/03-launch-support-and-release.md)。

## 測試接縫

- Domain／Application 規則應可在不啟動 Simulator 或遠端服務下測試。
- Data／Platform adapters 使用受控測試環境或 deterministic fakes 驗證錯誤、離線與重試。
- UI tests 以可注入的測試啟動狀態執行，避免依賴 production 帳號或資料；任何略過啟動動畫的行為必須由明確的 `--ui-testing` launch argument 啟用。
- Apple ID、推播、背景、Face ID 與真實跨裝置同步保留真機驗證，不偽裝成純 unit coverage。

## 架構不變量

1. 一位使用者最多只有一個有效伴侶關係。
2. 任何共同資料讀寫都必須驗證正確的伴侶範圍。
3. 訊息、共同約定與 Moment 的重試不能造成重複資料；排序規則必須可預期。
4. 通知與分析預設採資料最小化，不洩漏私密內容。
5. 刪除、匯出與解除配對依同一份明確規則執行。
6. iPhone 核心流程不依賴 Watch 或非 MVP 平台。
7. 未通過 G1 實測的外部技術選擇維持 provisional，不寫成既定事實。
8. 已成功同步的完整共同歷史必須能在遺失原裝置後由新裝置恢復；本機待送內容必須誠實顯示尚未備份。

其中第 1–5 項由 Supabase constraint、RLS、RPC、私有 Storage 與受控 Edge Function 執行伺服器端 enforcement；精確產品資料模型仍須在後續垂直切片中補充，並轉成 unit／integration／real-device regression gates。
