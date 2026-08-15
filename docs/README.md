---
title: 方心（CoupleSpace）產品文件索引
status: active
last_updated: 2026-08-15
---

# 方心（CoupleSpace）產品文件

本目錄是方心的產品規劃 SSOT（Single Source of Truth）；`CoupleSpace` 保留為目前的內部專案名稱與歷史決策識別。目前以 iPhone 首版為主要範圍；尚未確認的技術方案不會在此假設為既定事實。

## 快速摘要

- **產品定位：** 給忙碌情侶維持生活互動、分享日常並保持連結的私人共同空間。
- **繁中品牌名稱：** `方心`；規劃中的 App Store 名稱為「方心｜情侶的私密日常」，副標題為「聊天、回憶與共享約定」。
- **核心承諾：** 再忙，也能每天留一點位置給彼此。
- **品牌延伸句：** 把零碎日常，慢慢變成我們的生活。
- **品牌氣質：** 80% 溫柔成熟的共同生活，20% 可愛療癒感。
- **核心功能名稱：** `Moment・此刻`。
- **產品邊界：** 自願性此刻狀態表達現在但不追蹤在線活動；聊天承接日常，基本共同約定集中規劃與討論，Moment 保存值得留下的此刻，共同時間線累積兩人的生活。
- **開發基準：** 16 週完成 iPhone TestFlight 候選版，經 3–7 天熟人圈煙霧測試通過 release gate 後正式上架，再進行一個月上市驗證。
- **上市語言：** App UI 同時支援繁中、簡中、英文、日文；繁中是文案 SSOT，首輪只主動投放繁中市場。
- **營運模式：** 產品、工程與客服皆由一人負責；客服不承諾固定回覆時間，成長速度必須服從可持續營運容量。

## 建議閱讀順序

1. [產品願景與定位](product/01-vision-and-positioning.md)
2. [目標客群與使用需求](product/02-target-audience-and-jobs.md)
3. [核心體驗與資訊架構](product/03-experience-and-information-architecture.md)
4. [iPhone 首版範圍](product/04-iphone-mvp-scope.md)
5. [商業模式與市場成長](product/05-business-and-growth.md)
6. [成功指標與驗證計畫](product/06-metrics-and-validation.md)
7. [Apple 平台產品策略](product/07-apple-platform-strategy.md)
8. [第一版開發路線圖](operations/01-v1-development-roadmap.md)
9. [產品決策紀錄](decisions/product-decisions.md)
10. [技術決策紀錄](decisions/technical-decisions.md)
11. [一人營運災難復原規格](architecture/01-disaster-recovery.md)
12. [品牌識別與角色宇宙](design/01-brand-identity.md)
13. [iPhone 核心畫面與功能佈局概念](design/02-iphone-core-screen-concepts.md)
14. [上市、客服與版本發布營運](operations/03-launch-support-and-release.md)

## 文件維護原則

- 已確認的產品決策，以[產品決策紀錄](decisions/product-decisions.md)為準。
- 技術候選、接受狀態與取代脈絡，以[技術決策紀錄](decisions/technical-decisions.md)為準。
- 各主題文件負責解釋決策的脈絡、行為與範圍，不重複建立另一套互相衝突的規則。
- 未有證據的數字應標示為「假設」或「測試區間」，不可描述成已驗證結果。
- 新增功能前，先確認它屬於核心循環、首版支援能力或未來擴充。
- 技術架構、資料模型、API、設計系統與研究紀錄，未來應建立獨立子目錄，不混入產品定位文件。

## 目錄結構與未來擴充

```text
docs/
├── README.md
├── product/       # 產品定位、體驗、MVP、商業與指標
├── decisions/     # 已確認決策與變更原因
├── operations/    # 第一版路線圖、TestFlight、發布與事件處理
├── architecture/  # 系統架構、同步、資料與安全
├── design/        # 視覺、元件、文案與互動規範
└── research/      # 使用者訪談、競品研究與實驗結果
```
