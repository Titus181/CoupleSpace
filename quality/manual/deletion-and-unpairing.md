# LIFECYCLE-001：匯出、刪除與解除配對

## 步驟與預期

1. 建立包含文字、照片與雙方內容的可回收 relationship fixture。
2. A、B 各自建立個人封存；每人只能讀取、匯出與刪除自己的封存。
3. 匯出 manifest、照片檔名、byte count 與引用一致，且不包含未核准的私密欄位。
4. 單方封存或刪除不影響另一方封存；只有最後引用移除後才執行 Storage GC。
5. 有 pending／sending photo 或其他禁止條件時，解除配對被正確阻擋。
6. 解除配對／closing 後禁止新增共同內容，雙方結果一致且舊 relationship 不會被新內容重用。
7. 實際低磁碟、大型封存與中斷續傳在相關版本重測；合成小樣本不能代替真機壓力證據。

## W11 約定與專屬討論加驗（尚未執行）

1. 在解除配對前建立一筆有來源訊息的約定，加入雙方文字、照片及 Emoji，接著改期並取消；記錄 appointment、來源 message、discussion message、operation 與重大事件 ID 前 8 碼。
2. A、B 各自完成個人封存後，在 Debug「W1 技術驗證工具」重新整理資料生命週期狀態；兩台各自顯示正確的「封存共同約定／封存專屬討論項目／封存重大事件」數量及「約定封存關聯完整」。來源訊息、專屬討論文字／照片、原始建立者與改期／取消事件須仍指向同一 appointment UUID，seal 重試不得增加副本。
3. A 不得讀取 B 的封存，B 不得讀取 A 的封存，第三個帳號不得讀取任一份；刪除 A 的封存後，B 的約定、討論關聯、重大事件與照片仍完整可讀。
4. 本輪只驗證 W11 archive-local 關聯與 owner 隔離；完整 manifest 匯出、Reaction／Moment 等其他衍生資料與帳號刪除仍依 W14 的整體生命週期清單驗收。

## 通過證據

記錄 fixture 數量、兩位 owner 的可見範圍、匯出核對、刪除前後 metadata／object count 與 relationship 最終狀態；W11 另記錄上述穩定 ID 前 8 碼、每份封存的 appointment／discussion／event count 及 archive-local 關聯核對。越權、資料遺失、關聯斷裂、重複、過早 GC 或雙方不一致都阻擋發布。
