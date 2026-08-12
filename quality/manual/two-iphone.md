# DEVICE-001：雙 iPhone／雙身分核心流程

## 前置條件

- 兩支真實 iPhone、兩個不同測試 Apple 身分；不得使用 production 私人內容。
- 安裝同一個 release candidate，記錄 App build、iOS 版本與 backend。
- 測試前確認兩台目前帳號與 relationship，避免把舊 fixture 誤認為新結果。

## 步驟與預期

1. A、B 分別登入；取消、登出、強制結束後重開都不造成錯誤登入狀態。
2. 建立邀請、拒絕並重試，再由另一方接受；兩台 relationship ID 相同且只存在一段 active relationship。
3. A、B 分別建立文字與照片 Moment；雙方 Realtime 收斂、順序一致、沒有重複。
4. 雙方互留 Emoji／短文字回應；同一 Moment 只出現一份預期回應。
5. 發起共同問答；第二人回答前看不到第一份答案，回答後兩台共同揭曉。
6. 分別設定顯示名稱、私人稱呼與此刻狀態；私人稱呼只在設定者裝置可見。
7. A、B 分別傳送基本文字訊息；時間與未讀數正確，介面不顯示已讀狀態。
8. 兩台強制結束後重開；relationship、Moment、回應、答案、名稱、有效狀態與聊天均恢復。

## 通過證據

記錄 build、兩台 iOS、relationship 前 8 碼、每一步 PASS／FAIL，以及不含私人正文／完整身分識別碼的必要截圖。任一資料錯交、提前揭曉、消失、重複或錯序都阻擋發布。
