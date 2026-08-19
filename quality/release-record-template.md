# CoupleSpace 版本驗證紀錄

> 複製本文件為 `quality/releases/<version>-<build>.md` 後填寫。不得覆寫歷史 release record。

## 身分

- App version：
- Build：
- Commit：
- Branch：
- Schema／migration：
- 驗證開始／完成時間：
- 驗證者：

## 環境

- Xcode／Swift：
- macOS：
- Simulator：
- iPhone A／iOS：
- iPhone B／iOS：
- Multi-device 階段身分拓撲：iPhone A／B 同一測試身分；local logout／重新登入順序：
- 整合階段身分拓撲：iPhone A／B 兩個 relationship 測試身分；切換方式：
- W13 scope decision：PD-044；inventory／remote-revoke UI 與 runtime 移除證據：
- W13 migration 040：local evidence／linked remote history／deployment result（未部署須填 `PENDING`，不可用 unit／UI 代替）：
- Backend：local／staging／production-like
- Source／target region：
- DR mode／service manifest version：

## 自動化證據

| Gate | 結果 | executions／failure／skip | Artifact／log | 備註 |
| --- | --- | --- | --- | --- |
| Local database reset＋pgTAP |  |  |  |  |
| Local schema lint |  |  |  |  |
| Edge Function tests |  |  |  |  |
| Appointment read boundary（migration 040） |  |  |  | 記錄空資料庫 001–040、pgTAP／schema lint 與 linked remote 040；focused client tests 不等於部署完成 |
| Full iPhone scheme |  |  |  |  |
| SESSION-CAPABILITY-PREFLIGHT |  |  |  | 只記 SDK／no-inventory evidence；不得支持 shipping remote revoke |
| Watch suite（適用時） |  |  |  |  |
| Harness／Evals／diff check |  |  |  |  |

## 人工證據

| ID | 結果 | 裝置／環境 | 安全證據 | 備註 |
| --- | --- | --- | --- | --- |
| DEVICE-001 |  |  |  |  |
| NETWORK-001 |  |  |  |  |
| PUSH-002 |  |  |  |  |
| UPGRADE-001 |  |  |  |  |
| DR-001 |  |  |  |  |
| LIFECYCLE-001 |  |  |  |  |
| LOCK-001 |  |  |  |  |
| SESSION-001 | NOT_APPLICABLE (REMOVED) | 不重跑 | `manual/session-capability.md` | PD-044；保留 2026-08-19 歷史 FAIL，不得填 PASS |
| W13-INTEGRATION-001 | PENDING |  | `manual/w13-integration.md` | 只有 full automation、remote 040 與引用的 multi-device／LOCK／PUSH／badge／reminder／lifecycle／W8–W11 gate 全數通過後才能改為 PASS |

## 發布判定

### 災難復原證據（Gate C／D 適用時）

- Recovery point／Database artifact／Storage manifest／deletion journal sequence：
- Schema／backup workflow version：
- Database／Storage／journal last successful time：
- Counts／checksum／reference／RLS 結果：
- Signed manifest／read-only／recovery 結果：
- 實測資料缺口／RPO／RTO：
- 暫時 restore 環境清理結果：

- 未通過／未執行項目：
- `NOT_APPLICABLE` 理由：
- 已知限制：
- 監控與 phased release 設定：
- 暫停／降級／回復方案：
- 最終判定：PASS／FAIL／BLOCKED
- 判定人與時間：
