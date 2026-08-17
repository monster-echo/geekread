import common from '@ohos.app.ability.common'
import { AppStore } from '../../../state/AppStore'
import { appString, AppString } from '../../../localization/AppStrings'
import { AppColors, AppSpacing } from '../../../theme/AppTokens'
import { fetchItems, fetchStoryTree, reportComment, summarizeStory } from '../data/GeekReaderApiClient'
import { Comment, Story, toComment, toStory } from '../domain/Models'
import { buildCommentTree, CommentNode, FlatComment, flattenTree } from '../application/Comments'
import { htmlToText, ImmersiveTranslation } from '../components/ImmersiveTranslation'
import { savePixelMapToCache, shareImage } from '../../../media/ShareImage'
import { deriveTargetLanguage } from '../application/Locale'
import { translate } from '../application/TranslationCache'
import { telemetry, TelemetryValue } from '../../../telemetry/Telemetry'

function timeAgo(unix: number): string {
  const now = Math.floor(Date.now() / 1000)
  const d = Math.max(0, now - unix)
  if (d < 60) return `${d}s`
  if (d < 3600) return `${Math.floor(d / 60)}m`
  if (d < 86400) return `${Math.floor(d / 3600)}h`
  return `${Math.floor(d / 86400)}d`
}

interface CardComment {
  by: string
  text: string
}

interface DialogIndex {
  index: number
}

// 每批挂载评论数：单条评论含 Markdown 富文本组件，批量过大会同帧建几十棵组件树，
// 曾触发 APP_FREEZE 冻屏（IntactRender 整树同步渲染占满主线程）。10 条 + Markdown
// 懒渲染（ImmersiveTranslation 内 setLazyRender）把单帧爆发切小。
const RENDER_BATCH = 10

@Component
export struct StoryDetailPage {
  @ObjectLink store: AppStore
  @State story: Story | null = null
  @State tree: CommentNode[] = []
  @State collapsed: number[] = []
  @State loading: boolean = true
  @State commentsLoading: boolean = false
  @State summary: string = ''
  @State topComments: CardComment[] = []
  @State refreshing: boolean = false
  // 分屏渲染：先挂载前 RENDER_BATCH 条评论（重量级 Markdown 组件），
  // 滚动接近底部再挂下一批，避免 200 条同时 mount 卡顿；未挂载的评论
  // 不实例化 ImmersiveTranslation，其翻译也推迟到挂载时才触发（懒翻译）。
  @State renderLimit: number = RENDER_BATCH
  // 加载耗时埋点（detail_timing 事件）：各阶段毫秒数
  private timingStart: number = 0
  private timingStoryMs: number = -1
  private timingTreeMs: number = -1
  private timingTreePath: string = ''
  private timingTreeCached: boolean = false
  private timingCommentCount: number = 0
  private timingSummaryMs: number = -1

  aboutToAppear(): void {
    this.load()
  }

  private async load(): Promise<void> {
    const id = this.store.geekReaderStoryId
    if (id <= 0) { this.loading = false; return }
    this.loading = true
    this.timingStart = Date.now()
    this.timingStoryMs = -1
    this.timingTreeMs = -1
    this.timingSummaryMs = -1
    try {
      const storyStart = Date.now()
      const top = await fetchItems([id])
      const s = toStory(top.items[0] ?? null)
      this.timingStoryMs = Date.now() - storyStart
      this.story = s
      // 写入共享标题，NavDestination 标题栏据此显示文章标题
      this.store.detailTitle = s?.title ?? ''
      // 正文先显示（loading=false），评论树异步加载，避免等全部评论拉完才出内容
      this.loading = false
      if (s !== null) this.loadComments(s, id)
      else this.tree = []
    } finally {
      this.loading = false
    }
  }

  /** 下拉刷新：重拉文章 + 评论树 + 精华卡片。 */
  private async refresh(): Promise<void> {
    const id = this.store.geekReaderStoryId
    if (id <= 0) { this.refreshing = false; return }
    this.renderLimit = RENDER_BATCH // 重置分屏渲染，回顶部重新渐进挂载
    this.timingStart = Date.now() // 重置计时起点，避免 total_ms 混入页面停留时间
    try {
      const storyStart = Date.now()
      const top = await fetchItems([id])
      const s = toStory(top.items[0] ?? null)
      this.timingStoryMs = Date.now() - storyStart
      this.story = s
      this.store.detailTitle = s?.title ?? ''
      if (s !== null) {
        this.tree = []
        await this.loadComments(s, id) // 内部完成后会触发 prepareCard + timing 上报
      }
    } catch (e) {
      // 刷新失败保留原内容
    } finally {
      this.refreshing = false
    }
  }

  /** 异步拉取评论树（不阻塞正文显示）。优先整树接口（后端并发解析），失败回退逐层。 */
  private async loadComments(s: Story, id: number): Promise<void> {
    this.commentsLoading = true
    const treeStart = Date.now()
    try {
      try {
        await this.loadTreeFast(id)
        this.timingTreePath = 'tree'
      } catch (e) {
        telemetry.report(new Error(`comment_tree_failed: ${e instanceof Error ? e.message : String(e)}`))
        await this.loadTreeBfs(s, id)
        this.timingTreePath = 'bfs'
      }
      this.timingTreeMs = Date.now() - treeStart
      this.timingCommentCount = this.buildFlat().length
      this.reportTiming('ok')
      this.prepareCard()
    } catch {
      this.timingTreeMs = Date.now() - treeStart
      this.reportTiming('tree_error')
      // 评论加载失败不影响正文展示
    } finally {
      this.commentsLoading = false
    }
  }

  /** 埋点：详情页各阶段耗时（ms）。 */
  private reportTiming(result: string): void {
    const props = new Map<string, TelemetryValue>()
    props.set('story_id', this.story?.id ?? 0)
    props.set('result', result)
    props.set('path', this.timingTreePath)
    props.set('story_ms', this.timingStoryMs)
    props.set('tree_ms', this.timingTreeMs)
    props.set('comments', this.timingCommentCount)
    props.set('summary_ms', this.timingSummaryMs)
    props.set('total_ms', Date.now() - this.timingStart)
    props.set('cached_tree', this.timingTreeCached)
    telemetry.track('detail_timing', props)
  }

  /** 整树一次拉取（服务端并发，快）。 */
  private async loadTreeFast(id: number): Promise<void> {
    const res = await fetchStoryTree(id)
    this.timingTreeCached = res.cached === true
    const all: Comment[] = []
    for (let i = 0; i < res.items.length; i++) {
      const cm = toComment(res.items[i])
      if (cm !== null) all.push(cm)
    }
    const story = this.story
    if (story !== null) this.tree = buildCommentTree(all, story.id)
  }

  /** 逐层 BFS 拉取（回退路径）。 */
  private async loadTreeBfs(s: Story, id: number): Promise<void> {
    const all: Comment[] = []
    const seen: Set<number> = new Set<number>()
    let frontier: number[] = s.kids ?? []
    while (frontier.length > 0 && all.length < 200) {
      const res = await fetchItems(frontier)
      frontier = []
      for (let i = 0; i < res.items.length; i++) {
        const cm = toComment(res.items[i])
        if (cm === null || seen.has(cm.id)) continue
        seen.add(cm.id)
        all.push(cm)
        for (let k = 0; k < cm.kids.length; k++) frontier.push(cm.kids[k])
      }
    }
    this.tree = buildCommentTree(all, s.id)
  }

  private toggle(id: number): void {
    const next: number[] = []
    let found = false
    for (let i = 0; i < this.collapsed.length; i++) {
      if (this.collapsed[i] === id) { found = true; continue }
      next.push(this.collapsed[i])
    }
    if (!found) next.push(id)
    this.collapsed = next
  }

  /** 长按评论 → 举报弹窗（内容合规反馈入口）。 */
  private promptReport(fc: FlatComment): void {
    const reasons = ['spam', 'illegal', 'false_info']
    const labels = ['垃圾广告', '违法违规', '不实信息']
    this.getUIContext().getPromptAction().showDialog({
      title: '举报该评论',
      message: '内容由社区用户发布并经 AI 翻译，如发现违规可举报。',
      buttons: [
        { text: '取消', color: '#667085' },
        { text: '垃圾广告', color: '#D24B4B' },
        { text: '违法违规', color: '#D24B4B' },
        { text: '不实信息', color: '#D24B4B' },
      ],
    }).then((result: DialogIndex) => {
      const reason = reasons[result.index - 1]
      if (reason === undefined) return
      reportComment(this.story?.id ?? 0, fc.node.id, reason)
        .then(() => this.store.showToast('已提交举报，感谢反馈'))
        .catch(() => this.store.showToast('举报提交失败', true))
    }).catch(() => { /* 用户取消 */ })
  }

  /** 用系统浏览器打开外部链接（阅读原文）。 */
  private openUrl(url: string): void {
    if (url.length === 0) return
    const ctx = getContext(this) as common.UIAbilityContext
    ctx.openLink(url)
  }

  /** 选精选评论：按回复数降序取前 2 条（排除删除/空评论）。 */
  private pickTopComments(): CardComment[] {
    const candidates: CommentNode[] = []
    for (let i = 0; i < this.tree.length; i++) {
      const n = this.tree[i]
      if (n.deleted || n.dead) continue
      if (n.text.trim().length === 0) continue
      candidates.push(n)
    }
    candidates.sort((a: CommentNode, b: CommentNode) => b.replies.length - a.replies.length)
    const out: CardComment[] = []
    for (let i = 0; i < candidates.length && i < 2; i++) {
      const c = candidates[i]
      const clean = htmlToText(c.text)
      const text = clean.length > 80 ? clean.slice(0, 80) + '…' : clean
      out.push({ by: c.by, text: text })
    }
    return out
  }

  /** AI 摘要：标题 + 作者 + 摘要 + 精选评论（large=false 页面内小字号，true 分享截图大字号）。 */
  @Builder
  cardContent(large: boolean) {
    Column({ space: AppSpacing.x4 }) {
      Text(this.story?.title ?? '')
        .fontSize(large ? 28 : 15).fontWeight(large ? FontWeight.Bold : FontWeight.Normal).fontColor(AppColors.text)
        .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(`${this.story?.by ?? ''} · ${this.story?.score ?? 0} 分 · ${timeAgo(this.story?.time ?? 0)}`)
        .fontSize(large ? 14 : 12).fontColor(AppColors.textSecondary)
        .width('100%')
      if (this.summary.length > 0) {
        Divider().color(AppColors.border)
        Text(this.summary)
          .fontSize(large ? 18 : 15).fontColor(AppColors.text).lineHeight(large ? 26 : 22)
          .width('100%')
      }
      if (this.topComments.length > 0) {
        Divider().color(AppColors.border)
        ForEach(this.topComments, (c: CardComment, index: number) => {
          Column({ space: AppSpacing.x1 }) {
            Text(c.by).fontSize(12).fontColor(AppColors.brand)
            Text(c.text).fontSize(large ? 14 : 15).fontColor(AppColors.textSecondary)
              .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }, (c: CardComment, index: number) => `${index}-${c.by}`)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 分享卡片：固定 600×800 截图用（装饰条 + 大字号内容 + 底部水印）。 */
  @Builder
  shareCardBuilder() {
    Column() {
      Row().width('100%').height(6).backgroundColor(AppColors.brand).borderRadius(3)
      this.cardContent(true)
      Blank()
      Text('极客译读')
        .fontSize(20).fontWeight(FontWeight.Bold).fontColor(AppColors.brand)
    }
    .width(600).height(800)
    .padding(AppSpacing.x6)
    .backgroundColor(AppColors.surface)
    .alignItems(HorizontalAlign.Start)
  }

  /** 评论加载完成后生成精选评论（清洗 HTML + 翻译）+ LLM 摘要（后端按 storyId 缓存）。 */
  private async prepareCard(): Promise<void> {
    if (this.story === null) return
    const cardStart = Date.now()
    const lang = deriveTargetLanguage(this.store.language) // null = 英文用户，无需翻译

    // 精选评论：HTML → 干净文本（英文原文，供摘要与翻译用）
    this.topComments = this.pickTopComments()
    const enComments: string[] = this.topComments.map((c: CardComment) => c.text)

    // 翻译精选评论（非英文用户），失败保留原文
    if (lang !== null) {
      const translated: CardComment[] = []
      for (let i = 0; i < this.topComments.length; i++) {
        const c = this.topComments[i]
        try {
          const t = await translate(c.text, lang, true)
          translated.push({ by: c.by, text: t.length > 0 ? t : c.text })
        } catch (e) {
          translated.push(c)
        }
      }
      this.topComments = translated
    }

    console.log(`[geekread][card] after pickTopComments=${this.topComments.length} tree=${this.tree.length}`)
    // LLM 摘要：英文评论给模型，输出目标语言摘要（lang 为 null 时用英文）
    try {
      this.summary = await summarizeStory({
        storyId: this.story.id,
        title: this.story.title,
        text: this.story.text,
        comments: enComments,
        targetLanguage: lang ?? 'en',
      })
    } catch (e) {
      this.summary = ''
      const msg = e instanceof Error ? e.message : String(e)
      telemetry.report(new Error(`summarize_failed: ${msg}`))
    }
    this.timingSummaryMs = Date.now() - cardStart
    // 摘要完成后补报一次（含 summary_ms；tree 阶段已报过的不含）
    const props = new Map<string, TelemetryValue>()
    props.set('story_id', this.story.id)
    props.set('result', this.summary.length > 0 ? 'card_ok' : 'card_no_summary')
    props.set('story_ms', this.timingStoryMs)
    props.set('tree_ms', this.timingTreeMs)
    props.set('summary_ms', this.timingSummaryMs)
    props.set('total_ms', Date.now() - this.timingStart)
    telemetry.track('detail_timing', props)
  }

  private async share(): Promise<void> {
    if (this.story === null) return
    const ctx = getContext(this) as common.UIAbilityContext
    try {
      const pixelMap = await this.getUIContext().getComponentSnapshot()
        .createFromBuilder(() => { this.shareCardBuilder() }, 300, true, { scale: 2, waitUntilRenderFinished: true })
      const uri = await savePixelMapToCache(pixelMap, ctx)
      await shareImage(uri, ctx)
    } catch (e) {
      this.store.showToast('分享失败', true)
    }
  }

  private buildFlat(): FlatComment[] {
    const set: Set<number> = new Set<number>(this.collapsed)
    const acc: FlatComment[] = []
    flattenTree(this.tree, 0, set, acc)
    return acc
  }

  /** 滚到底部：还有未挂载评论时挂下一批（分屏渲染）。 */
  private onCommentsEnd(): void {
    const flat = this.buildFlat()
    if (this.renderLimit < flat.length) {
      this.renderLimit += RENDER_BATCH
    }
  }

  build() {
    // 作为 NavDestination 内容：Index RouteDest 统一用 NavDestination() 包裹，
    // 与其他子页面（Settings/Profile 等）布局一致，不在此重复包 NavDestination。
    Column() {
        if (this.loading) {
          Column() { LoadingProgress().width(40).height(40).color(AppColors.brand) }
            .justifyContent(FlexAlign.Center).layoutWeight(1).width('100%')
        }
        else if (this.story === null) {
          Column() { Text(appString(AppString.NoContent, this.store.language)).fontColor(AppColors.textSecondary) }
            .justifyContent(FlexAlign.Center).layoutWeight(1).width('100%')
        }
        else {
          Refresh({ refreshing: $$this.refreshing }) {
            Scroll() {
            Column({ space: AppSpacing.x3 }) {
              ImmersiveTranslation({ text: this.story.title, locale: this.store.language, displayMode: this.store.translationDisplayMode, free: true, rich: false })
              Row({ space: AppSpacing.x4 }) {
                if (this.story.url !== undefined && this.story.url.length > 0) {
                  Text(appString(AppString.ReadOriginal, this.store.language))
                    .fontColor(AppColors.brand).fontSize(14)
                    .onClick(() => this.openUrl(this.story?.url ?? ''))
                }
                Text(appString(AppString.Share, this.store.language))
                  .fontColor(AppColors.brand).fontSize(14)
                  .onClick(() => this.share())
              }.width('100%')
              if (this.story.text !== undefined && this.story.text.length > 0) {
                ImmersiveTranslation({ text: this.story.text, locale: this.store.language, displayMode: this.store.translationDisplayMode, free: true })
              }
              Text(`${this.story.score}${appString(AppString.PointsComments, this.store.language)}${this.story.by} · ${this.story.commentsCount} ${appString(AppString.Comments, this.store.language)}`)
                .fontSize(12).fontColor(AppColors.textSecondary)

              // AI 摘要：正文与评论之间展示（有摘要或精选评论时才显示），与正文/评论同风格无背景
              if (this.summary.length > 0 || this.topComments.length > 0) {
                this.cardContent(false)
              }

              // 评论异步加载期间、且还没有任何评论渲染出来时，显示一个小号转圈
              if (this.commentsLoading && this.buildFlat().length === 0) {
                Row() { LoadingProgress().width(20).height(20).color(AppColors.brand) }
                  .width('100%').justifyContent(FlexAlign.Center).padding({ top: AppSpacing.x4 })
              }

              ForEach(this.buildFlat().slice(0, this.renderLimit), (fc: FlatComment) => {
                Column({ space: AppSpacing.x1 }) {
                  if (fc.node.deleted || fc.node.dead) {
                    Text(appString(AppString.Deleted, this.store.language)).fontSize(12).fontColor(AppColors.textSecondary)
                  } else {
                    Text(`${fc.node.by} · ${timeAgo(fc.node.time)}` +
                      (fc.node.replies.length > 0 ? ` · ${this.collapsed.includes(fc.node.id) ? '+' : '−'}${fc.node.replies.length}` : ''))
                      .fontSize(12).fontColor(AppColors.textSecondary)
                      .onClick(() => this.toggle(fc.node.id))
                    ImmersiveTranslation({ text: fc.node.text, locale: this.store.language, displayMode: this.store.translationDisplayMode })
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .padding({ left: fc.depth * 12, top: AppSpacing.x2, bottom: AppSpacing.x2 })
                .border({ width: { left: fc.depth > 0 ? 1 : 0 }, color: AppColors.border })
                .gesture(LongPressGesture().onAction(() => this.promptReport(fc)))  // 长按评论 → 举报
              }, (fc: FlatComment) => `${fc.node.id}`)
            }
            .padding(AppSpacing.x4)
            .alignItems(HorizontalAlign.Start)
            .align(Alignment.TopStart)
          }
            // Scroll 的 align 默认是 Alignment.Center，内容矮于视口时会被居中；
            // 显式设为 TopStart，让内容从顶部开始排列。
            // onReachEnd：分屏渲染挂载下一批评论
            .width('100%')
            .align(Alignment.TopStart)
            .layoutWeight(1)
            .onReachEnd(() => this.onCommentsEnd())
          }
          .onRefreshing(() => this.refresh())
          .layoutWeight(1)
        }
    }.width('100%').height('100%')
  }
}
