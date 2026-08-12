# Plan 3：ArkTS 客户端 geek-reader feature 模块

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans.

**Goal:** 在 `arkts/` 壳里加 `entry/src/main/ets/features/geek-reader/`——ArkUI 实现的 HN 阅读 + 沉浸翻译，调 `backend/`（默认 `http://localhost:8787`），是 RN 模块的 ArkTS 对位实现。

**Architecture:** 独立 `GeekReaderApiClient`（`@ohos.net.http`，per-request 实例，baseUrl 常量，`x-install-id`+`Bearer` 经 setter 注入，token/installId 复用 `localStore`）；`@Observed GeekReaderStore` 持 top/latest `AsyncState` + selectedStoryId；`AsyncStatus` 复用壳约定；翻译批处理移植自 RN `translationCache`。

**Tech Stack:** ArkTS / ArkUI（HarmonyOS NEXT API 18，Stage 模型）· `@ohos.net.http` · `@ohos.data.preferences`。

**ArkTS 关键约定**（来自壳调研）：
- `AppRoute` 是数字 enum（顺序敏感，RouteHost 用 `<=` 分段）。新增 `GeekReader` 放末尾（落 `SettingsHost` 的 else 分支）。
- HTTP：`const client = http.createHttp(); await client.request(url, opts); finally client.destroy()`。后端**不**包 `{data}` 信封，直接 JSON。
- 组件：`@Component struct` + `@ObjectLink store: AppStore`；列表用 `ForEach`（壳惯例，数据集小）；加载在 `aboutToAppear()` 触发。
- 复用：`AppStore.navigate(route)`、`localStore.readToken()`/`localStore.installationId()`、`AsyncState<T>`/`AsyncStatus`、`AppColors/AppSpacing/AppRadii`、`localized(zh,en,lang)`、`PageHeader`（自带返回）。
- 递归评论树：ArkUI 用 `@Builder` 自调用实现递归。

**验证**：ArkTS 单测需设备/模拟器（`@ohos/hypium` + DevEco），本环境只能静态校验——用 `arkts-code-check`/`ets-lsp-check` skill + 结构评审；真机/模拟器验证留最终测试阶段。

---

## 文件结构

```
arkts/entry/src/main/ets/features/geek-reader/
├── domain/Models.ets                 HNItem/Story/Comment/TargetLanguage + toStory/toComment
├── application/Locale.ets            deriveTargetLanguage
├── application/Comments.ets          buildCommentTree（CommentNode）
├── application/TranslationCache.ets  批处理(50ms/≤20/≤12k)+去重+缓存
├── data/GeekReaderApiClient.ets      stories/items/translate；setter 注入 token/installId
├── state/GeekReaderStore.ets         @Observed：top/latest AsyncState + selectedStoryId
├── components/ImmersiveTranslation.ets  双语渲染（@Component）
├── components/CommentTree.ets        递归（@Builder）
├── pages/GeekReaderPage.ets          精选/最新 + 列表
└── pages/StoryDetailPage.ets         文章 + 评论树
```

**接线**：`AppRoute.ets`（+枚举+routeTitle）、`Index.ets`（SettingsHost case）、`HomePage.ets`（QuickAction）、`AppStore.ets`（ROUTE_BY_NAME + initialize 注入 client setter）。

---

### Task A1: 接线骨架（AppRoute + routeTitle + ROUTE_BY_NAME + HomePage QuickAction）

**Files:** Modify `navigation/AppRoute.ets`, `state/AppStore.ets`, `pages/HomePage.ets`

- [ ] **Step 1: `AppRoute.ets`** 末尾 `ProductFeedback,` 后加 `GeekReader,`；`routeTitle` switch 加 `case AppRoute.GeekReader: return localized('极客译读', 'Geek Reader', language)`（若 routeTitle 无 language 入参，直接 `return '极客译读'`）。
- [ ] **Step 2: `AppStore.ets` `ROUTE_BY_NAME`** 加 `'GeekReader': AppRoute.GeekReader` 与别名 `'geekReader.home': AppRoute.GeekReader`。
- [ ] **Step 3: `HomePage.ets` `QuickActions`** 加一项 `QuickAction({ store, label: localized('极客译读','Geek Reader', store.language), icon: AppIconName.Globe, route: AppRoute.GeekReader })`。
- [ ] **Step 4: 提交** `feat(arkts): wire GeekReader route + home quick action`

---

### Task A2: domain/Models.ets + application/{Locale,Comments}.ets

**Files:** Create the three files.

- [ ] `Models.ets`：`interface HNItem`、`interface Story`、`interface Comment`、`export type TargetLanguage = 'en'|'ja'|'ko'|'zh-Hans'|'zh-Hant'`、`toStory(item: HNItem | null): Story | null`、`toComment(...)`。（ArkTS 用 `interface` + 显式 null 返回；`kids: number[]` 默认 `[]`。）
- [ ] `Locale.ets`：`export function deriveTargetLanguage(locale: string): TargetLanguage | null`（同 RN 逻辑）。
- [ ] `Comments.ets`：`export interface CommentNode extends Comment { replies: CommentNode[] }`、`export function buildCommentTree(flat: Comment[], rootParentId: number): CommentNode[]`（用 `Map<number, CommentNode>`，ArkTS 需显式类型）。
- [ ] **静态校验**：用 `arkts-code-check` skill 检这三个文件。
- [ ] **提交** `feat(arkts): geek-reader domain + locale + comment-tree`

---

### Task A3: data/GeekReaderApiClient.ets

**Files:** Create `data/GeekReaderApiClient.ets`

- [ ] 实现要点：
  - `const GEEK_READER_BASE: string = 'http://localhost:8787'`
  - `import http from '@ohos.net.http'`；`let installId: string = ''`、`let authToken: string = ''`；`export function setInstallId(v: string)`、`export function setToken(v: string)`。
  - `async function send(path: string, method: string, body?: string): Promise<string>`：`const client = http.createHttp(); const headers: Record<string,string> = { 'content-type':'application/json' }; if (installId) headers['x-install-id']=installId; if (authToken) headers['authorization']=`Bearer ${authToken}`; const res = await client.request(`${BASE}${path}`, { method, header: headers, extraData: body, expectDataType: http.HttpDataType.STRING }); if (res.responseCode >= 400) throw new Error(`geekreader_${res.responseCode}`); return res.result as string; finally client.destroy();`
  - `fetchStories(type)`、`fetchItems(ids: number[])`、`translateBatch(req)`：`JSON.parse(await send(...))` 并 `as` 到 interface。
- [ ] `AppStore.initialize`（约第 90 行，`apiClient.setInstallationId` 旁）加：`geekReaderClient.setInstallId(localStore.installationId()); geekReaderClient.setToken(localStore.readToken());`（注：token 在登录后变化——更稳的是每次 send 时直接读 localStore，避免过期。实现里 send 内 `import { localStore } from '../../data/LocalStore'` 读最新 token/installId。）
- [ ] **静态校验 + 提交** `feat(arkts): GeekReaderApiClient (http + x-install-id + bearer)`

---

### Task A4: application/TranslationCache.ets

**Files:** Create `application/TranslationCache.ets`

- [ ] 移植 RN `translationCache.ts`：`cache: Map<string,string>`、`inFlight: Map<string,Promise<string>>`、`pending`、50ms `setTimeout`（ArkTS 支持 `setTimeout`）、`flush` 按 lang 分组 + chunk + 调 `translateBatch`。`translate(text, lang): Promise<string>`。注意 ArkTS Promise/generics 语法、`interface Pending` 显式类型。
- [ ] **静态校验 + 提交** `feat(arkts): translation batch cache`

---

### Task A5: state/GeekReaderStore.ets + 组件 ImmersiveTranslation / CommentTree

**Files:** Create `state/GeekReaderStore.ets`, `components/ImmersiveTranslation.ets`, `components/CommentTree.ets`

- [ ] `GeekReaderStore.ets`：`@Observed export class GeekReaderStore { topState: AsyncState<Story[]> = ...; latestState: ...; selectedStoryId: number = -1; async load(type) {...} }`（load 模式同 RemoteDataStore：set Loading → try fetchStories+fetchItems → Success/Empty → catch Error/Offline）。
- [ ] `ImmersiveTranslation.ets`：`@Component struct ImmersiveTranslation { @Prop text: string; @State result: string = ''; @State loading: boolean = false; @State failed: boolean = false; @State armed: boolean = false; build() { Column() { Text(this.text); ... if (loading) LoadingProgress(); else if (result) Column(){ Text('译 · '+label).fontColor(AppColors.brand); Text(result) }.borderWidth({left:3}).borderColor(AppColors.brand).padding({left:8}); else if (failed) Text('翻译失败'); else Button('译 · '+label).onClick(()=>{ this.armed=true; this.doTranslate(); }) } } doTranslate(){ ... translate(text, lang).then(...) } }`。lang 从 `AppStore.language` 推（或注入 @Prop locale）。
- [ ] `CommentTree.ets`：递归用 `@Builder`：`@Builder function CommentNodes(nodes: CommentNode[], depth: number) { ForEach(nodes, (n: CommentNode) => { CommentRow({node:n, depth}) }) }` + `@Component CommentRow { @State collapsed; build(){ Column(){ Text(`${by} · ${timeAgo}`); if (!collapsed) { ImmersiveTranslation({text: node.text}); if (node.replies.length) CommentNodes(node.replies, depth+1) } } } }`。ArkUI `@Builder` 可自调用实现递归。
- [ ] **静态校验 + 提交** `feat(arkts): geek-reader store + immersive + comment tree`

---

### Task A6: pages/GeekReaderPage.ets + StoryDetailPage.ets + Index.ets 分发

**Files:** Create two pages; Modify `pages/Index.ets` (import + SettingsHost case)

- [ ] `GeekReaderPage.ets`：`@Component struct GeekReaderPage { @ObjectLink store: AppStore; @State geekStore: GeekReaderStore = new GeekReaderStore(); @State tab: string = 'top'; aboutToAppear(){ this.geekStore.load('top') } build(){ Column(){ PageHeader({store, title:'极客译读'}); Row(){ Text('精选').onClick(...); Text('最新').onClick(...) }; if (state.status===Loading) LoadingProgress(); else if (Success) List(){ ForEach(data, (s:Story)=>{ ListItem(){ Column(){ ImmersiveTranslation({text:s.title}); Text(`${s.score} · ${s.by}`) }.onClick(()=>{ this.geekStore.selectedStoryId = s.id; this.store.navigate(AppRoute.GeekReaderDetail) }) } }) } } } }`。
- [ ] **A1 的 AppRoute 再加一个 `GeekReaderDetail`**（详情页路由）。
- [ ] `StoryDetailPage.ets`：`aboutToAppear` 里 BFS 抓评论（同 RN），`build` 渲染标题翻译 + 原文链接 + CommentTree。读 `geekStore.selectedStoryId`——但 GeekReaderPage 与 StoryDetailPage 是不同组件实例，store 不共享。解决：用 AppStore 上的一个字段 `selectedStoryId`（在 AppStore 加 `geekReaderStoryId: number = -1`），或用模块级单例 store（`export const geekReaderStore = new GeekReaderStore()`）跨页共享。**采模块级单例**（最简，ArkTS 支持）。
- [ ] `Index.ets`：import 两个 page；SettingsHost 加 `else if (route === AppRoute.GeekReader) GeekReaderPage({store})` 与 `else if (route === AppRoute.GeekReaderDetail) StoryDetailPage({store})`。
- [ ] **静态校验 + 提交** `feat(arkts): geek-reader pages + route dispatch`

---

### Task A7: 全模块静态校验 + 收尾

- [ ] 用 `arkts-code-check` skill 全量扫 `features/geek-reader/`；用 `ets-lsp-check` skill 补。
- [ ] 按报错修（ArkTS 常见：禁 `any`/`Object`、显式类型、`Map` 显式泛型、不可变 `@State` 更新需赋新值、@Builder 递归规则）。
- [ ] 更新 spec 验收勾选（ArkTS 端静态通过；真机留最终测试）。
- [ ] **提交** `docs: arkts geek-reader module verified (static)`

---

## Self-Review

**Spec 覆盖**：§3 ArkTS feature 模块 → A2-A6 ✓；§4 数据流 → A3+A6 ✓；§5 翻译 UX → A5 ✓；§9 ArkTS 原生实现 → 全模块 ✓。
**ArkTS 特定风险**：递归 @Builder、@Observed 跨页共享（用模块级单例 store）、token 过期（send 时读 localStore 而非缓存）—— 已在任务里标注对策。
**验证边界**：静态校验（arkts-code-check/ets-lsp-check）；真机/模拟器在最终测试阶段。
