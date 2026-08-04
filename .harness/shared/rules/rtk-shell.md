# RTK Shell 規則

## 適用範圍

在已安裝 RTK（Rust Token Killer）的開發環境中，優先使用 RTK 包裝支援的 shell 命令，以降低 Agent 上下文中的輸出量。

## 規則

預設使用：

```bash
rtk git status
rtk cargo test
rtk ls src/
rtk rg "pattern" src/
rtk docker ps
rtk gh pr list
```

以下情況使用原始命令：

- RTK 不支援該命令形態。
- 驗證需要未過濾的精確輸出。
- 長時間或互動式命令無法由 RTK 正確代理。
- 正在診斷 RTK 本身造成的問題。

## Meta Commands

```bash
rtk gain
rtk gain --history
rtk discover
rtk proxy <cmd>
```

## 安全邊界

RTK 只改變輸出呈現方式，不改變命令的風險等級。破壞性操作仍須先解析明確目標、確認授權，且不得依賴寬泛路徑或未解析變數。
