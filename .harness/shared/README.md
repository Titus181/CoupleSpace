# Vendored Shared Harness

這個目錄保存 `harness-version.yaml` 指定版本的共享 Harness 快照。

- Canonical source：`agent-harness`
- Distribution：vendored
- 更新方式：`project-harness.sh upgrade`
- 驗證方式：`project-harness.sh check`

不要直接編輯這裡的檔案。共享變更必須先在 `agent-harness` 發布版本，再透過專案分支、測試、Eval 與 PR 升級。
