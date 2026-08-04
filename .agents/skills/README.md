# Project Skills

這個目錄同時包含：

- 從 `harness-version.yaml` 指定 release vendoring 的共享 Skills。
- 只屬於本專案的 Skills。

共享 Skill 不應直接修改。若問題跨專案成立，應修改 `agent-harness`、發布新 tag，再透過本專案升級 PR 更新。

專案 Skill 可以直接放在：

```text
.agents/skills/<project-skill>/SKILL.md
```

新增前確認名稱不會覆蓋 vendored shared Skill。
