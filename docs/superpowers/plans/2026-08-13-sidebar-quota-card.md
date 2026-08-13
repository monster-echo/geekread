# 侧边栏额度进度卡片 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在阅读器侧边栏底部展示今日翻译额度进度（进度条 + 已用/总量 + 档位），点击进入登录页或会员页购买 Pro。

**Architecture:** 后端新增只读额度查询接口 `GET /api/reader/quota`（按 `(day, x-install-id)` 读今日已用，返回 `{ used, limit, remaining, isPro }`）；前端 `GeekReaderApiClient` 加 `fetchQuota()`，`GeekReaderPage` 打开侧边栏时拉取，在 `DrawerMenu` 底部渲染进度卡片。

**Tech Stack:** 后端 Node.js（Next.js route handler + vitest，内存/Redis 存储）；前端 ArkTS（ArkUI）+ hvigor。

**Spec:** `docs/superpowers/specs/2026-08-13-sidebar-quota-card-design.md`

---

### Task 1: 后端 quota 路由测试（红）

**Files:**
- Create: `backend/test/routes/quota.test.ts`

- [ ] **Step 1: 写测试文件**

```typescript
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

describe('GET /api/reader/quota', () => {
  beforeEach(() => {
    vi.resetModules();
    delete process.env.REDIS_URL;
    process.env.ENTITLEMENT_SIGNING_SECRET = 's';
    process.env.FREE_DAILY_TRANSLATIONS = '20';
    process.env.PRO_DAILY_TRANSLATIONS = '500';
  });
  afterEach(() => vi.restoreAllMocks());

  it('returns free quota without entitlement', async () => {
    const { GET } = await import('../../app/api/reader/quota/route.js');
    const res = await GET(new Request('http://localhost/api/reader/quota', {
      headers: { 'x-install-id': 'c1' },
    }));
    const body = await res.json();
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ used: 0, limit: 20, remaining: 20, isPro: false });
  });

  it('reflects today usage after reserving one', async () => {
    const { reserveDaily, today } = await import('../../lib/quota.js');
    await reserveDaily(today(), 'c1', false);
    const { GET } = await import('../../app/api/reader/quota/route.js');
    const res = await GET(new Request('http://localhost/api/reader/quota', {
      headers: { 'x-install-id': 'c1' },
    }));
    const body = await res.json();
    expect(body).toMatchObject({ used: 1, limit: 20, remaining: 19, isPro: false });
  });

  it('returns pro quota with valid entitlement', async () => {
    const { signEntitlement } = await import('../../lib/entitlement.js');
    const token = signEntitlement({ exp: Math.floor(Date.now() / 1000) + 3600 });
    const { GET } = await import('../../app/api/reader/quota/route.js');
    const res = await GET(new Request('http://localhost/api/reader/quota', {
      headers: { 'x-install-id': 'c2', authorization: `Bearer ${token}` },
    }));
    const body = await res.json();
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ limit: 500, isPro: true });
  });

  it('400 when install id missing', async () => {
    const { GET } = await import('../../app/api/reader/quota/route.js');
    const res = await GET(new Request('http://localhost/api/reader/quota'));
    expect(res.status).toBe(400);
  });
});
```

- [ ] **Step 2: 运行确认失败**

```bash
cd backend && npx vitest run test/routes/quota.test.ts
```
Expected: FAIL —— 找不到 `../../app/api/reader/quota/route.js`。

### Task 2: 后端实现 peekTranslation + quota 路由（绿）

**Files:**
- Modify: `backend/lib/storage.ts`（在 `reserveTranslation` 附近加 `peekTranslation`）
- Create: `backend/app/api/reader/quota/route.ts`

- [ ] **Step 1: storage.ts 加只读查询**

在 `backend/lib/storage.ts` 的 `reserveTranslation` 函数下方追加（`localUsage`、`redis()` 都是本模块作用域，直接可用）：

```typescript
export async function peekTranslation(day: string, clientId: string): Promise<number> {
  const key = `geekread:translation:${day}:${clientId}`;
  const client = await redis();
  if (!client) return localUsage.get(key) ?? 0;
  return Number(await client.get(key) ?? 0);
}
```

- [ ] **Step 2: 新建 quota 路由**

创建 `backend/app/api/reader/quota/route.ts`：

```typescript
import { hasProEntitlement } from '../../../lib/entitlement';
import { errorResponse, json } from '../../../lib/http';
import { limitFor, today } from '../../../lib/quota';
import { peekTranslation } from '../../../lib/storage';

export async function GET(request: Request): Promise<Response> {
  const installId = request.headers.get('x-install-id');
  if (!installId || installId.trim().length === 0 || installId.length > 128) {
    return errorResponse('invalid_request', 400);
  }
  const auth = request.headers.get('authorization') ?? '';
  const bearer = /^Bearer\s+(.+)$/i.exec(auth)?.[1];
  const isPro = bearer ? hasProEntitlement(bearer.trim()) : false;
  const limit = limitFor(isPro);
  const used = await peekTranslation(today(), installId);
  return json({ used, limit, remaining: Math.max(0, limit - used), isPro });
}
```

- [ ] **Step 3: 运行测试确认通过**

```bash
cd backend && npx vitest run
```
Expected: 全部通过（含 Task 1 的 4 个 quota 测试），原有 31 个测试不回归。

- [ ] **Step 4: Commit**

```bash
git add backend/lib/storage.ts backend/app/api/reader/quota/route.ts backend/test/routes/quota.test.ts
git commit -m "feat(backend): 新增 GET /api/reader/quota 查询今日翻译额度"
```

### Task 3: 前端 GeekReaderApiClient 加 fetchQuota

**Files:**
- Modify: `arkts/entry/src/main/ets/features/geek-reader/data/GeekReaderApiClient.ets`

- [ ] **Step 1: 加 ReaderQuota 接口与 fetchQuota**

在 `GeekReaderApiClient.ets` 文件末尾追加（复用现有的 `send` / `http` / `http.RequestMethod`）：

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

- [ ] **Step 2: Commit**

```bash
git add arkts/entry/src/main/ets/features/geek-reader/data/GeekReaderApiClient.ets
git commit -m "feat(arkts): GeekReaderApiClient 增加 fetchQuota()"
```

### Task 4: GeekReaderPage 加额度状态与拉取

**Files:**
- Modify: `arkts/entry/src/main/ets/features/geek-reader/pages/GeekReaderPage.ets`

- [ ] **Step 1: 更新 imports**

把：
```typescript
import { AppColors, AppSpacing } from '../../../theme/AppTokens'
import { fetchStories, fetchStoriesResolved } from '../data/GeekReaderApiClient'
```
改成：
```typescript
import { AppColors, AppRadii, AppSpacing } from '../../../theme/AppTokens'
import { fetchQuota, fetchStories, fetchStoriesResolved, ReaderQuota } from '../data/GeekReaderApiClient'
```

- [ ] **Step 2: 加 @State quota**

在 `@State drawerOpen: boolean = false`（约第 28 行）后面加：
```typescript
  @State quota: ReaderQuota | null = null
```

- [ ] **Step 3: 加 loadQuota 方法**

在 `private goto(route: string): void`（约第 104 行）后面加：
```typescript
  private async loadQuota(): Promise<void> {
    try {
      this.quota = await fetchQuota()
    } catch (e) {
      this.quota = null
    }
  }
```

- [ ] **Step 4: 侧边栏打开时触发拉取**

把 `SideBarContainer` 的 `.onChange`（约第 269 行）：
```typescript
    .onChange((show: boolean) => { this.drawerOpen = show })
```
改成：
```typescript
    .onChange((show: boolean) => { this.drawerOpen = show; if (show) this.loadQuota() })
```

- [ ] **Step 5: Commit**

```bash
git add arkts/entry/src/main/ets/features/geek-reader/pages/GeekReaderPage.ets
git commit -m "feat(arkts): GeekReaderPage 打开侧边栏时拉取翻译额度"
```

### Task 5: DrawerMenu 底部额度卡片

**Files:**
- Modify: `arkts/entry/src/main/ets/features/geek-reader/pages/GeekReaderPage.ets`（`DrawerMenu` builder，约第 129-165 行）

- [ ] **Step 1: 删除中间"解锁 Pro"行**

删除这段（原约 152-158 行）：
```typescript
      // Pro 会员入口（显示当前档位）
      Row({ space: AppSpacing.x3 }) {
        Text(this.store.user?.tierId === 'pro' ? 'Pro ✓' : '解锁 Pro')
          .fontSize(16).fontColor(AppColors.brand).fontWeight(FontWeight.Bold).layoutWeight(1)
        Text(this.store.user?.tierId === 'pro' ? '每日 500 次翻译' : '每日 500 次翻译').fontSize(11).fontColor(AppColors.textSecondary)
      }.width('100%').height(56).padding({ left: AppSpacing.x5, right: AppSpacing.x4 })
      .onClick(() => this.goto('membership.home'))
```

- [ ] **Step 2: 底部加额度卡片 footer**

把：
```typescript
      Blank()
      Text('GeekRead · ' + appString(AppString.GeekReaderTitle, this.store.language)).fontSize(11).fontColor(AppColors.textSecondary).padding(AppSpacing.x5)
```
改成：
```typescript
      Blank()
      // 底部：今日翻译额度进度 footer（点击 → 未登录登录页 / 已登录会员页）
      Column({ space: AppSpacing.x2 }) {
        Text('今日翻译额度').fontSize(13).fontColor(AppColors.textSecondary).width('100%')
        if (this.quota !== null) {
          Progress({ value: this.quota.used, total: this.quota.limit, type: ProgressType.Linear })
            .color(AppColors.brand).backgroundColor(AppColors.surfaceMuted).width('100%')
        }
        Row() {
          Text(this.quota === null ? '额度暂不可用' : `已用 ${this.quota.used}/${this.quota.limit} 次`)
            .fontSize(12).fontColor(AppColors.text).layoutWeight(1)
          Text(this.store.user?.tierId === 'pro' ? 'Pro ✓' : '升级 Pro')
            .fontSize(14).fontColor(AppColors.brand).fontWeight(FontWeight.Bold)
        }.width('100%')
      }
      .width('100%')
      .padding({ left: AppSpacing.x5, right: AppSpacing.x5, top: AppSpacing.x3, bottom: AppSpacing.x2 })
      .onClick(() => this.goto(this.store.signedIn ? 'membership.home' : 'SignIn'))
      Text('GeekRead · ' + appString(AppString.GeekReaderTitle, this.store.language)).fontSize(11).fontColor(AppColors.textSecondary).padding(AppSpacing.x5)
```

> 说明：`Progress` / `ProgressType` 是 ArkUI 内置组件，无需 import；`AppRadii` 本任务未用到可不加，但 Task 4 Step 1 已一并导入以便后续卡片圆角，无副作用。

- [ ] **Step 3: Commit**

```bash
git add arkts/entry/src/main/ets/features/geek-reader/pages/GeekReaderPage.ets
git commit -m "feat(arkts): 侧边栏底部加今日额度进度卡片，点击进入登录/会员"
```

### Task 6: 验证

**Files:** 无新增

- [ ] **Step 1: 后端全量测试**

```bash
cd backend && npx vitest run
```
Expected: 全部通过（35 个测试：原 31 + 新 quota 4）。

- [ ] **Step 2: 前端代码检查**

```bash
python3 ~/.claude/skills/arkts-code-check/tools/review_engine.py \
  arkts/entry/src/main/ets/features/geek-reader/pages/GeekReaderPage.ets \
  arkts/entry/src/main/ets/features/geek-reader/data/GeekReaderApiClient.ets
```
Expected: 0 Critical。

- [ ] **Step 3: 前端构建**

```bash
cd arkts && HVIGOR=/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw
$HVIGOR --mode module -p product=default -p driver=module assembleHap --no-daemon
```
Expected: `BUILD SUCCESSFUL`。

- [ ] **Step 4: 真机安装验证（可选）**

```bash
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
$HDC install -r entry/build/default/outputs/default/entry-default-signed.hap
```
打开侧边栏 → 底部应出现"今日翻译额度"进度卡片；点击 → 未登录进登录页 / 已登录进会员页。

---

## Self-Review 记录

- **Spec 覆盖**：额度接口（Task 1-2）、fetchQuota（Task 3）、侧边栏状态+拉取（Task 4）、底部卡片+删 Pro 行（Task 5）、失败兜底（Task 5 卡片 `quota===null` 显示"额度暂不可用"）、未登录点击（Task 5 `signedIn ? membership : SignIn`）。全部覆盖。
- **占位符**：无 TBD/TODO，每个代码步骤含完整代码。
- **类型一致**：`ReaderQuota` 在 Task 3 定义、Task 4 使用；`peekTranslation` 在 Task 2 定义、Task 2 路由使用；`loadQuota` 在 Task 4 定义、Task 4 onChange 调用、Task 5 卡片读 `this.quota`。命名一致。
