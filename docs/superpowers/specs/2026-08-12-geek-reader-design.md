# 极客译读（GeekRead）— 设计文档

- **状态**：已批准，进入实施规划
- **日期**：2026-08-12
- **来源**：将 `Hacki-OH`（Flutter 版极客译读）的核心业务抽出，落地到 `MobileStarter`（多端母模板）之上

---

## 1. 目标

把 Hacki-OH 验证过的「HN 阅读 + 沉浸式翻译」业务，以**商业化 + 合规**形态重新落地：

1. **沉浸式翻译**：把 HN 阅读器升级为「极客译读」——标题、评论、自贴文正文双语呈现。
2. **鸿蒙原生**：HarmonyOS NEXT 走 ArkTS 原生；iOS/Android 走 React Native。
3. **商业化**：Freemium 订阅（免费日额度 + Pro 月/年订阅）。
4. **大厂合规**：隐私同意门、隐私政策/服务条款/EULA、第三方 SDK 清单、账户注销、订阅披露、内容举报。

MobileStarter 提供「除核心业务外的一切辅助功能」（账号、支付、设置、法律、路由壳、多租户等），极客译读只注入核心阅读/翻译业务模块 + 专属后端。

---

## 2. 背景：两个源项目

### Hacki-OH（Flutter，参考实现）
- Flutter HN 客户端 + 沉浸翻译，已适配鸿蒙（`ohos/` 可构建，真机验证过），只读（`isReadOnly=true`）。
- **可复用资产**：
  - `lib/screens/widgets/immersive_translation.dart`（196 行，双语渲染 widget）
  - `lib/repositories/translation_repository.dart`（222 行，批处理/去重/缓存）
  - `lib/repositories/hacker_news_repository.dart` + `lib/models/item/`（HN 数据层 + 模型）
  - `lib/screens/widgets/comment_tile.dart` + `lib/screens/item/`（评论树）
  - `backend/src/{hacker-news,model,storage,function}.ts`（HN 代理 + MaaS 翻译 prompt + 配额）
  - `lib/screens/widgets/launch_consent_gate.dart`（首次启动隐私同意门）
  - `assets/{privacy_policy.md,terms_of_service.md,eula.md}`（法律文档）
  - `lib/repositories/entitlement_repository.dart`（HMAC entitlement token，订阅权益）
- **不复用**：Flutter/Dart 运行时（改 ArkTS + RN）、AGC Cloud Function 部署形态（改 Next.js）、华为 IAP MethodChannel（改 MobileStarter IAP）。

### MobileStarter（多端母模板）
- 四子工程：`arkts/`（HarmonyOS NEXT 原生，一等公民）+ `react-native/`（Expo）+ `flutter/`（不用）+ `server/`（Next.js，**共享通用后端**）+ `tool/mobileui/`（CLI 脚手架）。
- **现成辅助功能（全部保留复用）**：auth（邮箱/社交/手机）、IAP + membership、设置（主题/语言/字号/关于/法律/账户安全）、路由框架 + 守卫、Tab 壳、Toast/Confirm、AsyncState 语义、埋点、离线缓存、客服工单、通知、法律页、账户注销、多租户（`app_id`）、运营控制台。
- **feature-first 约定**：`features/<id>/{domain,application,data,presentation}`，由 `mobileui feature add` 生成。

---

## 3. 已锁定决策

| 维度 | 决定 |
|---|---|
| 客户端平台 | **ArkTS（鸿蒙原生）+ React Native（iOS/Android）**；Flutter 不用；Hacki-OH Dart 作参考实现 |
| v1 范围 | 商业化 + 合规 + 核心阅读（详见 §11） |
| 共享后端 | **MobileStarter `server/`** 保持 100% 通用，一行业务代码不进 |
| 专属后端 | **极客译读专用 Next.js**（新建，移植自 Hacki-OH `backend/`），**完全替换 AGC**；MaaS 可继续作 LLM |
| 仓库 | **独立产品 repo `geekread/`**：带 `arkts/` + `react-native/` + `backend/` + `shared/`，**不带 `server/`**（共享部署，靠 `app_id=geekread` 消费） |
| 收费模型 | **Freemium 订阅**（免费日额度/设备 + Pro 月/年订阅，沿用 Hacki-OH） |
| 翻译 UX | 沿用 Hacki-OH 双语渲染（原文 + 彩色竖线 + 「译」标签 + 译文） |
| 正文翻译边界 | **v1 = 自贴文 + 评论**；**外链网页翻译 = v2**（WebView 注入） |
| ArkTS↔RN 共享 | **共享契约（api-schema/strings/tokens）+ 各自原生实现** |

---

## 4. 整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│  MobileStarter server（共享部署 · 100% 通用 · 所有 app）           │
│  auth · IAP · membership · multi-tenant · console · push         │
└───────────────▲───────────────────────────────────▲──────────────┘
                │ entitlement JWT (IAP 验证后签发)    │ 账号/支付/会员
┌───────────────┴──────────┐   ┌────────────────────┴─────────────┐
│ 极客译读 Next.js（专属）  │   │ 客户端                             │
│ /reader/stories·items·   │◄──┤ ArkTS（HarmonyOS）+ RN（iOS/And）  │
│   comments  /translate   │   │  阅读/翻译 → 极客译读 Next.js      │
│ HN 代理(SWR)·翻译·配额   │   │  账号/支付 → MobileStarter server  │
│   → MaaS LLM             │   └────────────────────────────────────┘
└──────────────────────────┘
```

**关键边界**：
- 阅读/翻译打**专属 Next.js**；账号/支付/会员打**共享 MobileStarter server**。
- Pro 配额靠 **entitlement JWT 桥接**：MobileStarter server 验证 IAP 后签发短期 JWT → 客户端带给极客译读 Next.js → Next.js 本地 HMAC 验签放 Pro 额度（Hacki-OH 已有此设计，零新发明）。
- v1 匿名用户配额按 **install ID（请求头）**；v1 Pro 用户按 JWT。

---

## 5. 产品仓库布局

```
geekread/                              ← 独立 repo（git init）
├── arkts/                             ← mobileui create --profile arkts 生成
│   └── entry/src/main/ets/
│       └── features/geek-reader/      ← mobileui feature add + 填业务
├── react-native/                      ← mobileui create --profile react-native 生成
│   └── src/features/geek-reader/
├── backend/                           ← 极客译读专用 Next.js（移植自 Hacki-OH backend/）
│   ├── app/api/reader/{stories,items,comments}/route.ts
│   ├── app/api/translate/route.ts
│   ├── lib/{hacker-news,model,storage,quota,entitlement}.ts
│   └── test/                          ← 移植自 Hacki-OH backend/test
├── shared/                            ← 跨端契约（单一真理源）
│   ├── api-schema.json                ← codegen → ArkTS interface + TS types
│   ├── strings.json                   ← i18n 文案
│   └── tokens.json                    ← 设计令牌（颜色/间距/字体）
├── docs/                              ← 本 spec + 法律文档 + 决策记录
└── .mobileui/template.json
```

**不带 `server/`**——它是共享部署，客户端通过 `app_id=geekread` + 配置中的 server URL 消费。

**生成顺序**（实现期注意）：`mobileui create` 要求空目标目录。因此先生成到临时目录，再把 `arkts/`、`react-native/`、`.mobileui/`、`.github/` 合并进已含 `docs/`+`backend/`+`shared/` 的 `geekread/`。

---

## 6. 极客译读业务模块结构（两端对称）

两端遵循 MobileStarter feature-first 四层，语义对齐：

```
features/geek-reader/
├── domain/          纯领域模型（无依赖）
│   ├── Story · Comment · ItemType · StoryType
│   └── TranslationResult · TranslateRequest · QuotaStatus
├── data/            数据适配层
│   ├── GeekReaderApiClient   调专属 Next.js（stories/items/comments/translate）
│   └── GeekReaderStore       列表/详情/评论的 RemoteDataCache
├── application/     状态/用例
│   ├── StoriesState          idle/loading/success/empty/error/offline
│   ├── CommentsState         评论树 + 折叠态 + 懒加载
│   └── TranslationCache      批处理(50ms/≤20条/≤12k字符) + 去重 + 缓存
└── presentation/    UI
    ├── ReaderHomePage        精选/最新 双 Tab
    ├── ItemDetailPage        文章 + 评论树
    ├── CommentTree           递归折叠/缩进/懒加载
    └── ImmersiveTranslation  双语渲染（移植自 Hacki-OH widget）
```

- ArkTS：`@Observed` + `@ObjectLink` + `AsyncState`（MobileStarter 约定）。
- RN：Context + hooks + `AsyncState`。
- **状态语义两端完全一致**（MobileStarter 已确立的统一模型）。
- 路由接入：两端 `AppRoute` 加 `reader` / `item` 项 → 路由分发器加 case → `RouteGuard` 决定可见性（首页 Tab 或 QuickAction 入口）。

---

## 7. 数据流

**列表**：`ReaderHomePage` → `GeekReaderStore.top/latest` → `GET /reader/stories?type=top&cursor=` → Next.js SWR 缓存（60s fresh / 10min stale，复用 Hacki-OH `hacker-news.ts`）→ `Story[]`。下拉刷新 + 上拉分页。

**详情 + 评论**：进 `ItemDetailPage` → 并行：① `GET /reader/items/:id` 拿 story；② `GET /reader/comments/:id` 拿评论树（Next.js 并发抓取 + 客户端本地缓存）。

**翻译**（核心）：任何文本块挂 `ImmersiveTranslation` → 按 locale 推导目标语言（`en` 不译）→ postFrame 自动触发 → `TranslationCache.translate(text, lang)`（批处理/去重/缓存）→ `POST /translate {texts[], lang, installId|jwt}` → Next.js 4 并发 worker 调 MaaS → `results[]`。

**配额**：匿名按 install ID（请求头 `x-install-id`），Pro 按 `Authorization: Bearer <jwt>`。Next.js 每日重置计数（Redis/KV）。耗尽返回 `quota_exceeded`，客户端组件显示升级提示。

**错误处理**：统一 `AsyncState`（loading/empty/error/offline）。翻译失败**静默降级**（只显原文 + 小图标），不阻塞阅读。网络错误可重试（MobileStarter 现有重试机制）。

---

## 8. 沉浸翻译 UX + 正文翻译边界

### UX（沿用 Hacki-OH 验证设计）
- 未译：原文 + 「译」按钮 + 目标语言标签
- 译中：细进度条
- 已译：原文保留 + 左侧彩色竖线 + 「译 · 简体中文」标签 + 译文
- 配额耗尽：原文 + 「今日免费翻译已用完 · 解锁 Pro」（点击进 MobileStarter 会员页）
- 目标语言：跟随系统 locale（zh-Hans / zh-Hant / ja / ko；en 跳过）

### 正文翻译边界（已确认）
HN 文章两种：① 自贴文（`text`，Ask/Show HN 正文）；② 外链（`url`，外部网页）。
- **自贴文正文**：v1 做，与评论同机制（`ImmersiveTranslation` 直接翻译 `text` 字段）。
- **外链网页正文**：v2 做（WebView 注入 JS 抓正文 + 批量翻译 + 双语注入渲染，工程量大）。v1 外链点击跳系统浏览器/WebView 显示原文。

---

## 9. ArkTS ↔ RN 代码共享策略

ArkTS 与 RN **无法共享运行时代码**。策略：**共享契约 + 各自原生实现**。

- `shared/api-schema.json`（单一真理源）→ codegen 脚本生成 ArkTS interface + TS types。
- `shared/strings.json` → 两端 i18n 生成器。
- `shared/tokens.json` → 两端设计令牌生成器（喂给 ArkTS `AppTokens` / RN theme）。
- 两端 domain/application/data/presentation 各自原生实现，**接口签名、状态语义、错误模型完全对齐**。
- Hacki-OH 的 `TranslationRepository`（批处理）与 `ImmersiveTranslation`（渲染）作**参考实现**，两端各写一遍。
- 代价：业务逻辑写两遍；收益：每端地道、类型安全、过 ArkTSCheck / tsc。

---

## 10. 后端移植（Hacki-OH `backend/` → 专用 Next.js）

| Hacki-OH 源 | → Next.js 落点 | 改动 |
|---|---|---|
| `hacker-news.ts`（HN 代理 + SWR 缓存） | `lib/hacker-news.ts` | 原样 |
| `model.ts`（MaaS 翻译 prompt） | `lib/model.ts` | 原样（LLM 可 MaaS/DeepSeek/OpenAI，env 配置） |
| `storage.ts`（Redis 缓存/配额） | `lib/storage.ts` + `lib/quota.ts` | 原样 |
| `function.ts`（callable 路由 + 批处理 worker） | `app/api/translate/route.ts` + `app/api/reader/*/route.ts` | `myHandler` → route handlers |
| `function.ts`（HMAC entitlement 验签） | `lib/entitlement.ts` | 原样（JWT 验签放 Pro 额度） |
| `agc-function.ts`（AGC 入口） | 删除 | 不再需要 |
| `server.ts`（dev HTTP server） | 删除 | Next.js 自带 dev server |
| `test/*.test.ts` | `test/*.test.ts` | 原样移植 |

**部署**：Vercel / Docker / 华为云 CCE 均可（国内低延迟选华为云）。Redis 可换 Vercel KV / Upstash / 自建。国内部署需备案。

---

## 11. 商业化 + 合规层（v1 必备）

| 要素 | 落地 | 来源 |
|---|---|---|
| 首次启动隐私同意门 | 移植 `LaunchConsentGate`，两端各实现 | Hacki-OH |
| 隐私政策 / 服务条款 / EULA | 法律页 + 文档，适配极客译读 | Hacki-OH `assets/*.md` + MobileStarter 法律页 |
| 第三方 SDK 清单 / 数据收集说明 | 隐私政策内列（IAP、埋点、翻译后端、MaaS） | 新写 |
| 账号系统（登录/注册/社交/手机） | 直接用 | MobileStarter |
| 账户注销（个保法） | 直接用 | MobileStarter |
| IAP 订阅 + 恢复购买 + 续订披露 | 直接用 + entitlement JWT 桥接 | MobileStarter IAP + Hacki-OH 验签 |
| 设置页（偏好/主题/语言/字号/关于/法律/账户安全） | 直接用，换极客译读品牌 | MobileStarter |
| 内容举报（翻译/评论） | 移植 | Hacki-OH |
| Freemium 配额 | 免费 20 次/天/设备 + Pro 500 次/天（沿用 Hacki-OH，env 可调） | Hacki-OH |

**Pro 权益闭环**：客户端调 MobileStarter IAP → 验证购买 → MobileStarter server 签发 entitlement JWT → 客户端带 JWT 调极客译读 Next.js `/translate` → Next.js HMAC 验签 → 放 Pro 额度。订阅过期后 JWT 失效，自动降级免费。

**商品 ID**（沿用 Hacki-OH 命名）：`geekread.pro.monthly` / `geekread.pro.yearly`，在 Apple App Store / 华为 AppGallery 配置，MobileStarter server 的 `products` 配置里登记。

---

## 12. v1 / v2 范围边界

### v1（商业化 + 合规 + 核心阅读）
- 客户端壳（ArkTS + RN，`app_id=geekread`，极客译读品牌）
- 账号 / 设置 / 法律页 / 注销 / 首次同意门（复用 MobileStarter + Hacki-OH）
- IAP 订阅 + Pro 权益 + entitlement JWT 桥接
- 核心阅读器：列表 + 标题翻译 + 评论树 + 评论翻译 + 自贴文正文翻译 + 跳原文
- 翻译配额：免费日额度 + Pro 日额度
- 内容举报

### v2
- Algolia 搜索
- 离线阅读 + 阅读历史
- 外链网页沉浸翻译（WebView 注入）
- 推送通知

---

## 13. 测试策略
- **后端**：移植 Hacki-OH `backend/test/*.test.ts`（HN 解析、翻译批处理、配额、entitlement 验签）→ Next.js route handler 测试（vitest）。
- **客户端 domain/data 层**：mock API，单测（RN: vitest；ArkTS: `@ohos/hypium` 或等价）。
- **presentation 层**：关键组件快照/交互测试（评论树折叠、ImmersiveTranslation 状态机、配额耗尽态）。
- **契约**：codegen 生成的类型保证两端 API 形状一致；CI 跑 ArkTSCheck + tsc + 架构检查脚本。

---

## 14. 风险与缓解
1. **ArkTS + RN 双写工作量大**：靠契约对齐（§9）+ 分阶段（先后端 + 一端验证，再另一端）缓解。
2. **外链网页翻译延后到 v2**：产品差异化大招延后；v1 靠评论/自贴文翻译 + 双语 UX 仍显著优于纯 HN 阅读器。
3. **MaaS 可用性/成本**：`lib/model.ts` 抽象 LLM provider，env 切换 DeepSeek/OpenAI。
4. **国内合规/备案**：后端部署选华为云，备案前置；隐私政策请法务过。
5. **mobileui 空目标约束**：生成到临时目录再合并（§5）。
6. **两端状态语义漂移**：统一 `AsyncState` 语义 + 共享契约 codegen。

---

## 15. v1 验收标准
- [ ] ArkTS 端在 HarmonyOS NEXT 真机/模拟器跑通：浏览精选/最新 → 进详情 → 看评论树 → 标题/评论/自贴文双语翻译 → 跳原文。
- [ ] RN 端在 iOS/Android 跑通同样流程。
- [ ] 匿名用户翻译达免费额度后触发配额提示。
- [ ] Pro 订阅流程跑通：购买 → JWT → Pro 额度生效 → 过期降级。
- [ ] 首次启动隐私同意门、法律页、账户注销可用。
- [x] 极客译读 Next.js 后端独立运行：HN 代理（SWR 缓存）+ 配额 reserve/rollback + entitlement 验签链路冒烟通过（端到端 curl 验证 stories/items/translate/400）；翻译完整闭环待配置真实 LLM 密钥（model.ts 单测已覆盖）。
- [ ] MobileStarter `server/` 无任何极客译读业务代码（保持通用纯净）。
- [ ] 两端过 ArkTSCheck / tsc / 架构检查；后端过 vitest。

---

## 16. 实施顺序（高层，writing-plans 细化）
1. 建 `geekread/` repo + `shared/` 契约 + codegen 脚本。
2. 极客译读 Next.js 后端（移植 Hacki-OH backend + entitlement 验签 + HTTP 形态）。
3. `mobileui create` 生成两端壳 + `mobileui feature add geek-reader`，合并进 `geekread/`，配置 `app_id=geekread` + 品牌 + 法律 + 同意门 + IAP 商品。
4. RN 端 feature 模块（domain→data→application→presentation），先跑通列表+翻译。
5. ArkTS 端 feature 模块，对齐 RN。
6. 评论树 + 自贴文翻译 + 跳原文。
7. Pro 订阅 + entitlement JWT 桥接闭环。
8. 配额、举报、设置/法律/注销完善。
9. 两端验收 + 后端部署。

---

## 17. 最终验证（2026-08-12，Plan 1–4 完成后）

**已通过（自动化）**
- ✅ 后端 `backend/`：31 vitest 单测全过；`tsc --noEmit` 干净；`/api/translate` 端到端 200（配额 reserve/rollback、entitlement 路径、400 校验）。
- ✅ RN `react-native/`：geek-reader 26 vitest 单测全过（models/locale/comments/translationCache/GeekReaderApiClient/entitlement）；**全项目** `tsc --noEmit` 干净（含接线改动）。
- ✅ 共享契约 `shared/`：codegen 确定性复生成无 diff。

**已通过（人工/架构）**
- ✅ 架构边界：MobileStarter `server/` 零极客译读业务代码；极客译读后端独立 Next.js；entitlement 签发（MobileStarter）↔ 验签（geekread 后端）两侧 payload 格式与密钥对齐。
- ✅ 法律文档：privacy/terms/EULA 落到 `docs/legal/`（多平台 IAP）。
- ✅ ArkTS 模块结构：9 个 `.ets`（domain/application×3/data×2/components/pages×2）+ 接线（AppRoute/AppStore/Index/HomePage），import 解析、遵循壳惯例（NotificationPage/ApiTransport 模式），已规避 ArkTS iterator 协议限制。

**待办（部署/设备相关，非代码缺陷）**
- ⚠️ 后端 HN 代理：本机直连 `hacker-news.firebaseio.com` 超时（需代理或部署在可达区域）；HN/SWR 逻辑由单测覆盖，Plan 1 在网络可达时已端到端冒烟过。生产建议在受限网络用 undici `ProxyAgent` 或部署在可达节点。
- ⚠️ ArkTS 真机/模拟器：需 DevEco Studio 跑 `hvigorw assembleHap` + ArkTSCheck + 真机渲染验证（本环境无 GUI/设备）。
- ⚠️ 真实 LLM：配 `MODEL_API_URL/KEY/NAME` 后 `/api/translate` 完整译文闭环（model.ts 单测已 mock 覆盖）。
- ⚠️ MobileStarter `server/` 依赖未本地安装，其 `tsc` 在 CI/装依赖后跑（entitlement 端点逐行仿 `membership/current`）。
- v2：搜索（Algolia）/ 离线+历史 / 外链网页沉浸翻译 / 推送 / 内容举报（PG 表）。

**仓库状态**
- `geekread/`（main）：Plan 1–4 全部合并，commit 历史清晰（每 plan 独立分支 + merge）。
- `MobileStarter/`（`feat/entitlement-signing` 分支，未合）：entitlement 签发端点 + .env，待用户决定合并。
