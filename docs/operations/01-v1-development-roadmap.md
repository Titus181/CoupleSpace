---
title: 第一版開發路線圖
status: active
last_updated: 2026-08-11
---

# 第一版開發路線圖

## 文件目的

本文件將 [iPhone 首版範圍](../product/04-iphone-mvp-scope.md) 轉換為依時間與依賴排序、可個別驗收的開發目標。第一版在此定義為：

> 可先由熟人圈完成短期 TestFlight 煙霧測試，再安全接續至 App Store 正式上市的 iPhone MVP。

本路線圖是目前的規劃基準，不代表尚待確認的技術方案已成為產品決策。若產品範圍或技術風險改變，應更新本文件並在 [產品決策紀錄](../decisions/product-decisions.md) 保留決策脈絡。

## 時程假設

- **起始日期：** 2026-08-04。
- **人力假設：** 一位全職開發者，產品與設計決策能及時提供。
- **封閉測試版：** 15 週，預計 2026-11-16 開始 TestFlight。
- **封閉驗證：** TestFlight 候選版完成後，以 3–7 天、最低開發者加一位朋友的兩帳號／兩真機煙霧測試為基準；可再加入熟人圈 1–3 對情侶驗證無口頭引導流程。
- **上市驗證：** 通過 release gate 後進入 App Store 正式供應，執行一個月繁中上市活動，再依伴侶對行為、品質、成本與回饋進行第一輪版本決策；實際日期取決於 gate 與 App Review，不作固定交付保證。
- **兼職換算：** 若每週投入約 20 小時，整體時程初估需延長至 26–30 週。
- **重新估算點：** W1 技術風險驗證完成後，依實測結果調整時程；上述日期不是保證交付日。

## 排程原則

- 先完成會影響整體資料模型的技術決策，再開始大量功能實作。
- 以可在兩支真實 iPhone 上驗收的垂直流程為單位，不先完成所有畫面再補同步能力。
- 優先完成 `配對 → Moment／共同約定 → 雙向互動／約定討論 → 對話 → 收藏 → 共同時間線` 的核心循環。
- 每個目標必須有明確完成條件；畫面存在但資料無法可靠跨裝置同步，不算完成。
- iPhone 核心流程完成前，不投入 Watch、macOS、visionOS、Widget、訂閱或 AI 功能。

## 開發目標與時間順序

| 時間 | 開發目標 | 完成條件 |
|---|---|---|
| W1，8/4–8/11 | **G1 技術決策與風險驗證（已完成）** | 兩支真實 iPhone、兩個 Apple 身分已完成 development 登入、配對、雙向資料、弱網／跨啟動 Outbox 與雙向推播實測；TD-001 已決定 Supabase 架構及共同資料的所有權、解除配對、刪除與匯出規則 |
| W2，8/10–8/16 | **G2 iPhone App 基礎骨架（已完成）** | 移除預設範例資料模型；建立「今天／對話／我們」三分頁、環境設定、領域模型與測試框架；iPhone target 可穩定建置與執行 |
| W3，8/17–8/23 | **G3 帳號與使用者身分（已完成）** | 使用者可登入、登出，重新啟動後可恢復登入；取消與失敗狀態明確；不建立重複帳號 |
| W4，8/24–8/30 | **G4 邀請與一對一配對** | A 可邀請 B；B 接受後雙方看到同一段伴侶關係；一人只能有一個有效伴侶；邀請可拒絕、失效與重試 |
| W5，8/31–9/6 | **G5 第一個 Moment 垂直切片** | 可建立心情、短句或照片 Moment；另一支手機能同步看到；Moment 自動進入共同時間線 |
| W6，9/7–9/13 | **G6 Moment 雙向互動** | 支援 Emoji、短文字回應及固定題庫版「我們的一題」；雙方互動後形成完整 Moment |
| W7，9/14–9/20 | **G7 基本文字聊天** | 一對一文字訊息可跨裝置同步；顯示訊息時間與未讀數；不顯示已讀狀態 |
| W8，9/21–9/27 | **G8 可靠傳送機制** | 訊息具有傳送中、成功、失敗與重試狀態；離線重連後不遺失、不重複，順序可預期 |
| W9，9/28–10/4 | **G9 聊天首版完整範圍** | 支援聊天照片、Emoji 回應；長按訊息可收藏為 Moment，並能從 Moment 回到相關對話 |
| W10，10/5–10/11 | **G10 基本共同約定與專屬討論** | 可由長按訊息確認、輸入列「＋」、今天或共同日程建立同一筆基本共同約定；主對話卡片、近期列表、月曆、詳情與通知同步同一狀態且重試不重複；雙方可進入同一個專屬討論，活動後可挑選內容建立相關 Moment，且不建立第二套訊息系統 |
| W11，10/12–10/18 | **G11「我們」與基本回顧** | 時間線可依日期瀏覽並顯示參與者與建立時間；可查看過往約定並返回相關討論；基本每週回顧採規則式彙整，不使用 AI |
| W12，10/19–10/25 | **G12 推播與裝置隱私** | 一般對話、約定討論與基本提醒送達正確使用者；鎖定畫面預設不顯示私密內容；Face ID／裝置密碼 App Lock 可用 |
| W13，10/26–11/1 | **G13 資料生命週期** | 解除配對、帳號刪除、共同約定與討論、共同資料處理及基本匯出均依 G1 規則運作；雙方結果一致且可稽核 |
| W14，11/2–11/8 | **G14 分析、監控與端到端測試** | 能以伴侶對追蹤配對、首次互動、Moment、共同約定、討論、聊天與回訪；不記錄私密訊息內容；核心流程具自動化測試 |
| W15，11/9–11/15 | **G15 TestFlight 候選版** | 兩個新帳號能完成首版十項完成條件；通過真機、弱網、離線、通知、約定提醒、刪除與隱私測試；沒有阻斷級問題 |
| G15 後 3–7 天 | **G16 熟人圈 TestFlight 煙霧測試** | 開發者與一位朋友以兩個帳號、兩支真實 iPhone 完成核心流程、弱網／離線、推播隱私、版本更新、資料恢復、匯出、刪除與解除配對；視需要加入 1–3 對熟人情侶無口頭引導驗證；沒有阻斷級問題 |
| G16 通過後 | **G17 正式上架與首月驗證** | TestFlight 使用者的完整關係資料可無刪檔接續至 App Store 正式版；執行一個月繁中上市活動與 30 天 Plus Launch Pass，追蹤雙人啟用、雙向互動、W1／W4 留存、品質、成本及自願訂閱 |
| 上市活動滿一個月 | **G18 第一版決策點** | 依伴侶對行為、使用者回饋、可靠性、客服與成本證據，決定修正核心循環、擴大投放或安排下一版；此時重新評估 Widget、進階回顧與訂閱優先順序 |

## 關鍵里程碑

### M0：技術方案可行（W1）

2026-08-11 已通過。兩個不同 Apple 身分在兩支真實 iPhone 完成 Supabase 登入、配對、雙向資料、五輪弱網／跨啟動 Outbox 與 development sandbox 雙向推播；共同資料的所有權、解除配對、刪除與匯出規則已由 TD-001 及相關決策確立。production／TestFlight 推播、大型封存、實際低磁碟與中斷續傳屬 G13／G15 release gates，不回頭阻擋 W2。

### M1：核心價值可在兩支手機展示（W6）

兩位使用者可完成：

`建立 Moment → 伴侶看見 → 回應 → 進入共同時間線`

這是第一個產品價值閘門。若互動不夠清楚或無法在一分鐘內完成，優先修正核心體驗，不直接擴張功能。

### M2：完整首版循環成立（W11）

兩位使用者可從 Moment 延伸至自由聊天，也可從共同約定進入專屬討論；重要訊息可收藏為 Moment，並能在共同時間線找回內容及返回相關約定或對話。

### M3：隱私與資料處理可驗證（W13）

通知不洩漏私密內容，App Lock、解除配對、刪除與匯出能在真實雙人資料情境下正確完成。

### M4：可進入熟人圈 TestFlight 煙霧測試（W15）

符合 [iPhone 首版完成定義](../product/04-iphone-mvp-scope.md#首版完成定義)，且不存在會造成資料外洩、資料遺失、錯發訊息或無法解除配對的阻斷問題。煙霧測試還必須證明 TestFlight 建立的 relationship、聊天、照片、Moment、共同約定、討論、時間線及封存可由正式 release build 接續與遠端恢復，才能進入公開上市。

## W1 技術閘門（已完成）

2026-08-11，G1／M0 依原始完成條件正式通過：Supabase 責任邊界與資料生命週期已接受，兩支真實 iPhone／兩個 Apple 身分完成 development 登入、配對、雙向資料、五輪弱網／跨啟動 Outbox 與雙向推播。production／TestFlight、大型封存、實際低磁碟與中斷續傳移至 G13／G15 release gates；它們不再形成 W1→W2 的循環依賴。

### 完成前累積紀錄

以下長段保留 2026-08-10 以前的逐步驗證脈絡；其中 `in_progress` 與「G1／M0 尚未通過」是當時快照，已由上方 2026-08-11 完成結論取代。

目前狀態為 `in_progress`。TD-001 已接受 Supabase 作為 iPhone v1 使用者身分、伴侶關係、共同資料與資料生命週期的唯一遠端系統紀錄，CloudKit Sharing 不進入正式共同資料架構。Supabase 已由兩個 Apple 身分完成 Auth、pairing、active relationship RLS 雙向寫入、Realtime 雙向事件、私有 Storage 照片雙向讀寫、closing 後拒絕共同寫入、雙份 personal archive、archived photo 讀取、owner-only 獨立刪除與最後引用 Storage GC；遠端測試專案另以第三 authenticated UUID 證明共同資料不可見，marker、message、photo finalization 與解除配對 RPC 均拒絕。單筆與三筆 FIFO marker metadata outbox 均已完成斷網、App 重啟、恢復網路重送及雙裝置一致性實測；照片持久 outbox 已完成真機 A＋Simulator B 的單張與三張斷網、跨啟動、恢復網路單次 FIFO drain、順序一致及跨裝置可見性實測。斷網冷啟動的 relationship 顯示已加入依使用者隔離的唯讀快照；大圖縮放、EXIF 方向正規化與 GPS metadata 移除亦已加入實際 JPEG regression，合計通過 `build-for-testing`、26 個 Simulator runtime tests、真機離線冷啟動及高解析直向照片跨裝置回歸。文字訊息契約、FIFO outbox 與封存正文保留已完成 migration 008 雲端部署、81 個 pgTAP、23 個 Simulator tests，以及真機 A＋Simulator B 的在線同步、三筆離線跨啟動 FIFO、恢復網路重送與去重實測。W1 client 現另加入登入／前景恢復後的一次性 outbox recovery：先更新關係，再只依序處理目前 active relationship 的 marker、message、photo，並拒絕 closing、archived、舊關係與並行重入；純規則與完整 `CoupleSpaceTests` 48／48 通過，真機 A＋Simulator B 的背景返回及強制結束後重啟兩條自動 drain 流程也已完整通過，三種內容均送達、清空、跨裝置可見且無重複。前景 unavailable→available 監聽候選已完成本機實作、測試及真機 A＋Simulator B 跨裝置驗證；正式長時間退避、production 網路監聽與背景排程仍未決定。私人推播 migrations 009／010 與 `send-w1-push` version 1 已部署 Supabase 測試專案，限制 token 不可直接讀取、由 active 2/2 relationship 推導另一位收件者，並固定使用不含私人內容的工作與 payload；APNs secrets 已設定且真機 sandbox token 已成功登記。遠端 Function 為 ACTIVE、JWT 驗證開啟且未授權請求回傳 401；Simulator B 已把正確泛化通知送達背景、終止及鎖定狀態的真機 A，Apple Watch 亦正常鏡像相同泛化通知。個人封存匯出已建立 version 1 JSON manifest＋UUID JPEG 資料夾候選，真機「儲存到檔案」、manifest／照片對應及敏感欄位核對均正常；照片現已逐張寫入受保護磁碟 staging，完成／失敗與下次匯出前會清理。真機複驗發現交付名稱與 staging 同名碰撞後已重建無來源名稱的根 wrapper，兩次新位置交付與重試均成功；明確清理其他 relationship 測試 marker 的恢復路徑亦已加入。2026-08-07 本機另完成 message／marker 各 100 筆、photo 32 筆的持久 FIFO drain，以及 64 張各 64 KiB 合成照片的磁碟 staging／輸出與部分 staging 清理 regression；PD-020 的核心雙向互動／每週雙向聊天規則與私密內容不進分析編碼 regression 亦已加入。這些只是結構壓力與純規則樣本，不是正式容量或雲端分析證據。系統選擇器以返回後按 X 取消時，提示 callback 會延至下一次匯出，列為非阻斷 UI 時序限制。照片 closing 競態的 migration 011 與 client orphan reconciliation 已通過本機 125 個 pgTAP、schema lint，migration 011 已部署 Supabase 測試專案，真機 A 離線待送＋Simulator B 觸發 closing 的跨裝置時序亦已通過。PD-022 已接受照片不按時間自動到期，並沿用 active relationship、owner-only 個人封存、明確刪除與最後引用 GC 的既有生命週期，因此不需新增 migration。兩支真實 iPhone、照片頻繁弱網、長佇列與大型封存真機壓力，以及正式訊息仍未完成，因此 G1 與 M0 尚未通過。詳細證據記錄於 [W1 技術驗證紀錄](02-w1-technical-validation.md)，接受脈絡記錄於 [技術決策紀錄](../decisions/technical-decisions.md)。

前景 outbox recovery 已進一步加入有限次短退避：登入／回到前景時立即嘗試，若仍有同一 active relationship 的待送項目，依序等待 1 秒與 4 秒再試，合計最多三次；之後停止並保留 Outbox。真機 A＋Simulator B 已完成短暫斷線後不按人工重試即自動送達、持續斷線至三次耗盡後保留待送項目，以及恢復網路後由下一次前景事件送達且對方只收到一次的驗證。W1 client 現另以 `NWPathMonitor` 觀察前景中的 unavailable→available，才觸發同一 coordinator；初次啟動已連線、重複 available、轉為離線或持續離線均不觸發。完整 `CoupleSpaceTests` 59／59 通過；真機 A 在 App 保持前景時離線建立待送 marker，恢復網路後 Outbox 自動清空，Simulator B 只收到一次。這不包含背景 task、長時間退避或無限輪詢。

照片持久 Outbox 現另在寫入重新編碼 JPEG 前，檢查其所在 volume 的已知可用空間；若明確少於本次 JPEG bytes，會在建立本機檔案與 queue metadata 前拒絕並顯示空間不足。容量無法取得時仍沿用既有原子寫入錯誤保護，不加入任意安全倍數或新的商業配額。完整 `CoupleSpaceTests` 61／61 通過，涵蓋剛好足夠、少一 byte、容量未知，以及拒絕後不留下檔案／queue；2026-08-10 真機 A 的正常上傳路徑亦完成回歸，Simulator B 可讀取該照片且 Outbox 清空。這不代表真機低磁碟或容量壓力已通過。

以下實作細節尚未決定，不得在規劃中默認某一實作方式：

1. 正式訊息資料模型、長佇列真機壓力、正式自動排程、長時間退避、production 網路監聽與背景重試；message／marker 各 100 筆的本機 FIFO regression，以及登入／前景恢復的一次性 immediate retry 與三次有限短退避真機流程均已通過。前景離線→連線觸發已完成本機候選與真機跨裝置驗證；正式長時間重試與背景執行仍未定案。
2. 照片正式 upload outbox、縮圖、壓縮、正式容量與高壓情境下的刪除一致性；保存生命週期已由 PD-022 關閉，本機 Outbox 寫入前的精確 bytes 容量預檢已完成，但真機低磁碟壓力仍待驗證。
3. 個人封存匯出的正式格式、容量與中斷後續傳；W1 資料夾候選已改為逐張下載至磁碟 staging，64 張／4 MiB 合成樣本與部分 staging 清理通過本機測試。migration 013 另把照片 byte size 複製進個人封存，讓 App 在下載前比較 manifest＋照片總大小與暫存 volume 可用空間；140 個 pgTAP、58 個 Simulator tests、本機與 linked `public` schema lint 通過，migration 已部署 Supabase 測試專案，既有 archived relationship 的真機正常匯出路徑亦完成複驗。大型真機壓力、實際低磁碟空間與中斷點續傳仍待驗證，也不代表最終產品格式。
4. 推播 production／TestFlight 送達仍待 G15 實測；兩支真實 iPhone 的 development sandbox 雙向接收者、背景／終止／鎖定與敏感內容隱藏已通過。

PD-020 已關閉「有意義雙向互動」的定義與資料最小化方向：同一 Moment、同一題或同一共同約定內的雙方參與構成核心指標，自由聊天另以每週雙向聊天活躍衡量；完整內容保存在受 RLS 保護的產品資料與私有 Storage，分析事件只保存內容參照與必要 metadata。雲端事件彙整及產品資料／Storage 備份還原仍須在相應垂直切片與 release gate 驗證，不在 W1 建立第二份私密內容資料。PD-021 的 Free 照片研究額度 migration 012 已部署 Supabase 測試專案：伺服器核對 object owner／bytes 並以 relationship lock 執行 UTC 月曆月 30 張與累積 1,000,000,000 bytes，App 不可直接繞過 photo metadata finalization；139 個 pgTAP 與 55 個 Simulator tests 通過，client regression 另要求配額拒絕時先清除遠端 object、成功後才移除本機 Outbox，清理失敗或未知原因則保留待重試。真機 A＋Simulator B 的近同時雙上傳已確認兩筆均建立且雙方收斂至同一張最新照片；另以可回收 fixture 分別建立本月 30 張與累積 999,999,999 bytes 邊界，第 31 張及跨越 1 GB 的照片都正確顯示對應上限、未建立 metadata、清空 Outbox 並刪除新 Storage object。兩組 fixture 清理後遠端均回復原有 5 筆 metadata／5 個 object／1,164,373 bytes；週期與額度仍只是 TestFlight 研究假設。

技術方案至少需以兩支真實裝置與兩個不同 Apple ID 完成小型驗證，不能只依文件或單機模擬結果判斷可行。

## 第一版範圍控制

### 本路線圖包含

- iPhone 帳號、邀請與一對一配對。
- Moment、回應、固定題庫版「我們的一題」。
- 文字與照片聊天、Emoji 回應、未讀數及離線重試。
- 基本共同約定、近期與月曆瀏覽、專屬討論、基本提醒及活動後建立相關 Moment。
- 將聊天訊息收藏為 Moment。
- 共同時間線與最小規則式每週回顧。
- 私密推播、App Lock、匯出、刪除與解除配對。
- 支援產品驗證所需的最小分析與品質監控。

### 本路線圖不包含

- Apple Watch 核心功能。
- macOS 或 visionOS 功能適配。
- Home Screen Widget。
- StoreKit、正式訂閱價格、付費牆與「支持開發者」真實收款。
- AI 回顧、AI 關係分析或伴侶評分。
- 進階搜尋、月度或年度回顧。
- 完整共享行事曆、外部日曆雙向同步、重複行程、多人邀請、多組日曆、投票、任務指派與子討論串。
- 通話、群組、位置、貼圖商城與已讀狀態。

上述功能若要提前加入，必須先說明其驗證目的、對時程的影響，以及要交換掉的既有第一版目標。

## 並行驗證工作

開發期間同步執行 [成功指標與驗證計畫](../product/06-metrics-and-validation.md)：

- W1–W4：訪談 10 對種子客群情侶，伴侶分開訪談。
- W1–W3：以可點擊原型驗證 `建立 Moment → 邀請 → 回應／共同揭曉 → 對話 → 收藏 → 時間線`。
- W1–W3：同步驗證 `建立共同約定 → 專屬討論 → 活動後建立 Moment → 返回原約定`，確認資訊集中但不分散日常對話。
- W4 前：確認第一個 Moment 的預設內容與邀請文案，避免在配對流程中臨時決策。
- G16：以兩帳號、兩支真實 iPhone 執行 3–7 天熟人圈 TestFlight 煙霧測試，不把此階段當作公開獲客或長期留存研究。
- G17：正式上架後執行一個月繁中上市活動，以伴侶對追蹤雙人啟用、雙向互動、W1／W4 留存、Plus Launch Pass 使用、品質、成本與自願訂閱。

研究結果可調整文案、操作與優先順序；若要改變已確認的產品邊界，需先更新產品決策紀錄。

## 時程調整規則

- G1 技術驗證延後時，後續日期整體順延，不以省略資料安全工作追回進度。
- 任一目標未滿足完成條件，不因畫面可展示就標示為完成。
- 若時程不足，先簡化呈現方式，例如固定題庫、規則式每週回顧；不得刪除首版完成定義中的核心流程而不更新產品決策。
- 遇到資料錯發、資料遺失、通知洩漏或解除配對結果不一致時，停止新增功能，先處理可靠性與安全問題。

## G17 正式上市 gate

四語公開上市不納入 15 週 TestFlight 候選版的固定承諾；G16 煙霧測試通過、準備進入 G17 正式上架前，至少完成：

- 以繁中 canonical copy 維護 `zh-Hant`、`zh-Hans`、`en`、`ja`，完成關鍵流程、複數、截斷、日期與權限文案 QA。
- 四語 App Store metadata、版本說明與基本幫助內容；首輪付費投放與持續市場內容只做繁中。
- App 內單一「幫助與意見」入口、可查詢的案件欄位、隱私同意與不承諾回覆時間的確認文案。
- 資料庫與 Storage 分開的 restore drill、成本與容量警報、狀態頁、降級模式及單人事故 runbook。
- 適合共同回顧的照片顯示版／縮圖規格與真機畫質、流量、容量驗證；不宣稱原始畫質備份。
- App Store 版本說明、App 內更新中心、重大事故狀態頁三層公告流程，以及 phased release／回滾檢查表。

若 TestFlight build 提供「支持開發者」流程，只能使用 StoreKit／Sandbox 驗證，不向測試者實際收款。G18 上市首月決策後若決定在 App Store 正式供應版本啟用，必須與訂閱及其他 StoreKit 工作共同排序，並完成當時適用的商品價格、審查說明、交易、取消、失敗與退款驗證。

詳細規格見[上市、客服與版本發布營運](03-launch-support-and-release.md)。
