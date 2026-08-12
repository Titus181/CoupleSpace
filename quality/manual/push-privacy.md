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

## 通過證據

記錄 build、APNs environment、狀態、送達次數與去識別截圖。錯誤收件者、私密內容外洩或重複通知立即阻擋發布。
