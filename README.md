# 极客译读（GeekRead）

沉浸式翻译的 Hacker News 阅读器。商业化 Freemium，覆盖 HarmonyOS（ArkTS 原生）+ iOS/Android（React Native）。

## 仓库结构

| 目录 | 说明 |
|---|---|
| `arkts/` | HarmonyOS NEXT ArkTS 原生客户端（一等公民） |
| `react-native/` | iOS/Android React Native（Expo）客户端 |
| `backend/` | 极客译读专属 Next.js 后端（HN 代理 + 翻译 + 配额 + entitlement 验签） |
| `shared/` | 跨端 API 契约（JSON Schema + codegen） |
| `docs/` | 设计文档 + 实施计划 |

> MobileStarter 共享 server（auth/IAP/多租户）独立部署，本仓库通过 `app_id=geekread` 消费，不 vendor。

详见 `docs/superpowers/specs/` 与 `docs/superpowers/plans/`。
