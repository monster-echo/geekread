# 侧边栏额度进度卡片（Quota Footer）

日期：2026-08-13

## 背景

阅读器（GeekReaderPage）的 `SideBarContainer` 侧边栏目前中间有一行"解锁 Pro / 每日 500 次翻译"，点击进会员页。用户希望在**侧边栏最底部作为 footer** 展示今日翻译额度的使用进度，点击可购买 Pro。

## 需求

- 侧边栏底部 footer 显示**额度进度卡片**：进度条 + "今日已用 X/Y 次翻译" + 档位（免费/Pro）。
- 点击卡片：未登录 → 登录页；已登录 → 会员页（购买 Pro）。
- **删除**中间那行"解锁 Pro"（footer 卡片承担 Pro 入口，避免重复）。
- 版本号小字保留在卡片下方。

```
┌──────────────────────┐
│ logo  极客译读        │
│ 用户名 / 登录         │
│ 设置                 │
│ 关于                 │
│ 协议                 │
│        (Blank)       │
│ ┌──────────────────┐ │
│ │ 今日翻译额度      │ │  ← 底部 footer 卡片
│ │ ▓▓▓▓▓░░░░ 5/20   │ │     Progress 进度条
│ │ 免费 · 升级 Pro   │ │     点击 → 登录/会员页
│ └──────────────────┘ │
│ GeekRead · 极客译读   │  ← 版本号小字
└──────────────────────┘
```

## 数据源

额度目前无独立查询接口，`remainingTranslations` 只在 `/api/translate` 响应中返回。采用**新增后端接口**方案。

- 额度按 `(day, clientId)` 存储（`clientId` = `x-install-id`）。
- 免费：每日 20 次；Pro：每日 500 次（`lib/quota.ts` 的 `limitFor(isPro)`）。
- 打开侧边栏时拉取额度。

## 后端改动

### 1. `lib/storage.ts` 加只读查询

新增 `peekTranslation(day, clientId)`：返回当前已用次数，**不递增**（区别于 `reserveTranslation`）。

```typescript
export async function peekTranslation(day: string, clientId: string): Promise<number> {
  const key = `geekread:translation:${day}:${clientId}`;
  const client = await redis();
  if (!client) return localUsage.get(key) ?? 0;
  return Number(await client.get(key) ?? 0);
}
```

### 2. 新路由 `app/api/reader/quota/route.ts`

`GET /api/reader/quota`：
- 请求头：`x-install-id`（必填，校验规则同 translate）、`Authorization: Bearer <entitlement>`（判定 Pro）。
- 逻辑：
  - `clientId` = installId；`isPro` = Bearer 存在且 `hasProEntitlement`。
  - `limit` = `limitFor(isPro)`；`used` = `peekTranslation(today(), clientId)`。
  - `remaining` = `max(0, limit - used)`。
- 响应：`{ used, limit, remaining, isPro }`。
- 未登录（无 Bearer）也返回，表示免费额度。

### 3. 后端测试

`test/routes/quota.test.ts`：内存模式验证 used/limit/remaining、isPro 判定、installId 缺失 400。

## 前端改动

### 1. `data/GeekReaderApiClient.ets` 加 `fetchQuota()`

```typescript
export interface ReaderQuota {
  used: number
  limit: number
  remaining: number
  isPro: boolean
}

export async function fetchQuota(): Promise<ReaderQuota> {
  const text = await send('/api/reader/quota', http.RequestMethod.GET)
  return JSON.parse(text) as ReaderQuota
}
```

（复用现有 `send` / `authHeaders`，自动带 `x-install-id` 与 Bearer。）

### 2. `GeekReaderPage` 状态与拉取

- `@State quota: ReaderQuota | null = null`。
- 侧边栏打开时拉取（`showSideBar` 变化 / 汉堡按钮 onClick 里触发）。
- 拉取失败置 null（走兜底）。

### 3. `DrawerMenu` 布局

- **删除**中间 `Row`："解锁 Pro / 每日 500 次翻译"（`goto('membership.home')`）。
- 底部（`Blank()` 之后、版本号之前）加额度 footer 卡片：
  - ArkUI `Progress({ value: used, total: limit, type: ProgressType.Linear })` + 文案。
  - 文案：`今日已用 ${used}/${limit} 次翻译`；档位：`isPro ? 'Pro ✓' : '免费 · 升级 Pro'`。
  - 点击：`this.goto(this.store.signedIn ? 'membership.home' : 'SignIn')`。
- 版本号 `Text('GeekRead · ...')` 保留在卡片下方。

### 4. 失败兜底

`quota === null` 时，卡片显示"今日额度暂不可用"，但保留"升级 Pro"按钮（仍可点击购买）。

## 数据流

```
打开侧边栏 → fetchQuota() → 更新进度卡片
点击卡片 → 未登录 ? SignIn : membership.home
```

## 错误处理

- 接口失败/超时 → 卡片占位文案 + 升级 Pro 入口仍在。
- 未登录 → 返回免费额度（正常显示 20 次/日）。

## 测试

- 后端：`vitest` 单测 quota 路由（内存模式）。
- 前端：`arkts-code-check` + `assembleHap` 构建通过。

## 范围说明

- 不做"翻译后实时递减"的本地乐观更新；打开侧边栏时拉取即认为足够（额度变化频率低）。
- 不处理 Pro 购买流程本身（已有会员页/支付链路），本功能只做入口 + 展示。
