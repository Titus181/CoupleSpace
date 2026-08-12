# LIFECYCLE-001：匯出、刪除與解除配對

## 步驟與預期

1. 建立包含文字、照片與雙方內容的可回收 relationship fixture。
2. A、B 各自建立個人封存；每人只能讀取、匯出與刪除自己的封存。
3. 匯出 manifest、照片檔名、byte count 與引用一致，且不包含未核准的私密欄位。
4. 單方封存或刪除不影響另一方封存；只有最後引用移除後才執行 Storage GC。
5. 有 pending／sending photo 或其他禁止條件時，解除配對被正確阻擋。
6. 解除配對／closing 後禁止新增共同內容，雙方結果一致且舊 relationship 不會被新內容重用。
7. 實際低磁碟、大型封存與中斷續傳在相關版本重測；合成小樣本不能代替真機壓力證據。

## 通過證據

記錄 fixture 數量、兩位 owner 的可見範圍、匯出核對、刪除前後 metadata／object count 與 relationship 最終狀態。越權、資料遺失、過早 GC 或雙方不一致都阻擋發布。
