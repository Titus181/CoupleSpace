# 版本驗證紀錄

每個 TestFlight 或正式 release candidate 都從 `../release-record-template.md` 建立獨立紀錄，檔名使用 `<version>-<build>.md`。同一 build 重跑時更新同一份紀錄並保留每次執行時間與結果；不同 build 不覆寫彼此。

Release record 不保存 secrets、完整 Apple／Supabase 身分、device token、私人訊息、照片或未去識別截圖。大型 `.xcresult` 與 DerivedData 保存於本機受控位置或 CI artifact，紀錄中只放安全路徑／連結及 executions、failure、skip、exit status。
