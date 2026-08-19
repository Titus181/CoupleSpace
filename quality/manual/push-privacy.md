# PUSH-002：真實推播與隱私

## 前置條件

- 兩支真實 iPhone、兩個測試身分；確認 development、TestFlight 或 production-like APNs 環境。
- 使用無私密內容的 fixture；記錄 sender／receiver，不記錄完整 token。

## 步驟與預期

1. A 觸發只應送給 B 的事件；A、第三人與其他裝置不收到。
2. B 在前景、背景、App 已終止與鎖定畫面各驗證至少一次。
3. 每個事件只送達一次；retry／worker reclaim 不造成重複。
4. 標題、正文、category、custom data、log 與測試 artifact 均不含訊息、照片、Moment、答案、relationship ID 或完整 device token。
5. Apple Watch 鏡像通知若適用，顯示同一泛化文案。
6. TestFlight／production push 必須在對應 APNs environment 重測；development sandbox 結果不能代替。

## W13 切片 5：共同約定本機提醒／badge 回歸

1. A、B 以相同 active relationship 建立一筆至少五分鐘後的約定；兩台各自允許通知。B 收到約定建立的遠端通知後保持在背景且不點開 App，確認兩台仍各只收到一次本機提醒。鎖定畫面只可見「共同約定提醒／你有一筆即將開始的共同約定。」，不得出現標題、地點、註記、relationship、訊息或 UUID。
2. 在提醒送達前由 A 改期；兩台各只在新時間收到一次，舊時間不得送達。強制結束並重開後再確認不會累積第二則。
3. 取消該約定；兩台舊的待送通知與通知中心內同一約定的已送達通知均須移除，且之後不再送達。
4. 另建一筆未來提醒後，先由 A 登出，再由 B 點「開始解除配對（closing）」；B 的該 relationship 待送提醒與通知中心既有提醒須立即移除。離開該 relationship 的裝置不得保留或送達舊提醒，重新登入或重新配對也不得令它復活。
5. 每一步前後記錄「對話」tab badge 與 App icon badge；本機提醒本身不得新增未讀、改變兩者，或改變 server-authoritative `relationship_unread_counts` 結果。以遠端約定建立／改期／取消通知另外依其既有案例驗證，不能用本機提醒代替。
6. 拒絕通知權限後建立有提醒的約定；約定仍正常同步，畫面須明示這支手機不會在指定時間提醒，不得顯示已排入或假稱已送達。
7. 以可控制的延遲讓 background appointment refresh／reminder reconcile 在途，分別於完成前執行目前裝置登出、切換帳號／relationship，以及進入 closing。最後完成的舊 refresh 不得重寫舊 relationship cache、重啟 observer 或重新加入已移除的提醒；local logout／closing cleanup 必須勝出。真機只核對可見結果，精確的先後競態以 `CoupleSpaceTests/CoupleSpaceTests.swift` 的 lifecycle generation、background revalidation 與 reminder conditional-activation tests 為準。

## 通過證據

記錄 build、APNs environment、狀態、送達次數與去識別截圖。錯誤收件者、私密內容外洩或重複通知立即阻擋發布。

## 2026-08-20 final candidate 結果

- 結果：`PASS`。
- 遠端推播：使用者在同一最終 W13 候選的兩支真實 iPhone 合併執行 LOCK／PUSH／5C／W8，明確回報流程正常。
- 共同約定本機提醒：使用者另回報約定、討論與提醒正常；最後 lifecycle 階段亦正常，包含本清單延後到 closing 的 cleanup 範圍。
- iPhone 機型／iOS、APNs environment、精確完成時間：`未記錄`。
- 本結果只關閉 W13 引用的 `PUSH-002` 與提醒整合；不宣稱 production APNs、TestFlight Gate D 或全產品 release-ready。
