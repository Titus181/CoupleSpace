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
- Apple 身分：兩個不同測試身分／其他（說明）
- Backend：local／staging／production-like
- Source／target region：
- DR mode／service manifest version：

## 自動化證據

| Gate | 結果 | executions／failure／skip | Artifact／log | 備註 |
| --- | --- | --- | --- | --- |
| Local database reset＋pgTAP |  |  |  |  |
| Local schema lint |  |  |  |  |
| Edge Function tests |  |  |  |  |
| Full iPhone scheme |  |  |  |  |
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
