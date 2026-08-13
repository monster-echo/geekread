import common from '@ohos.app.ability.common'
import { AppStore } from '../../../state/AppStore'
import { appString, AppString } from '../../../localization/AppStrings'
import { AppColors, AppSpacing } from '../../../theme/AppTokens'
import { fetchItems } from '../data/GeekReaderApiClient'
import { Comment, Story, toComment, toStory } from '../domain/Models'
import { buildCommentTree, CommentNode, FlatComment, flattenTree } from '../application/Comments'
import { ImmersiveTranslation } from '../components/ImmersiveTranslation'
import { savePixelMapToCache, shareImage } from '../../../media/ShareImage'

function timeAgo(unix: number): string {
  const now = Math.floor(Date.now() / 1000)
  const d = Math.max(0, now - unix)
  if (d < 60) return `${d}s`
  if (d < 3600) return `${Math.floor(d / 60)}m`
  if (d < 86400) return `${Math.floor(d / 3600)}h`
  return `${Math.floor(d / 86400)}d`
}

@Component
export struct StoryDetailPage {
  @ObjectLink store: AppStore
  @State story: Story | null = null
  @State tree: CommentNode[] = []
  @State collapsed: number[] = []
  @State loading: boolean = true
  @State commentsLoading: boolean = false

  aboutToAppear(): void {
    this.load()
  }

  private async load(): Promise<void> {
    const id = this.store.geekReaderStoryId
    if (id <= 0) { this.loading = false; return }
    this.loading = true
    try {
      const top = await fetchItems([id])
      const s = toStory(top.items[0] ?? null)
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

  /** 异步拉取评论树（不阻塞正文显示）。 */
  private async loadComments(s: Story, id: number): Promise<void> {
    this.commentsLoading = true
    try {
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
    } catch {
      // 评论加载失败不影响正文展示
    } finally {
      this.commentsLoading = false
    }
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

  /** 用系统浏览器打开外部链接（阅读原文）。 */
  private openUrl(url: string): void {
    if (url.length === 0) return
    const ctx = getContext(this) as common.UIAbilityContext
    ctx.openLink(url)
  }

  /** 分享卡片：离屏构建 → 截图 → 打包保存 → 系统分享。 */
  @Builder
  shareCardBuilder() {
    Column({ space: AppSpacing.x4 }) {
      Text(this.story?.title ?? '')
        .fontSize(28).fontWeight(FontWeight.Bold).fontColor(AppColors.text)
        .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(`${this.story?.by ?? ''} · ${this.story?.score ?? 0} 分 · ${timeAgo(this.story?.time ?? 0)}`)
        .fontSize(16).fontColor(AppColors.textSecondary)
        .width('100%')
      Blank()
      Text('极客译读')
        .fontSize(20).fontWeight(FontWeight.Bold).fontColor(AppColors.brand)
    }
    .width(600).height(800)
    .padding(AppSpacing.x6)
    .backgroundColor(AppColors.surface)
    .alignItems(HorizontalAlign.Start)
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

              // 评论异步加载期间、且还没有任何评论渲染出来时，显示一个小号转圈
              if (this.commentsLoading && this.buildFlat().length === 0) {
                Row() { LoadingProgress().width(20).height(20).color(AppColors.brand) }
                  .width('100%').justifyContent(FlexAlign.Center).padding({ top: AppSpacing.x4 })
              }

              ForEach(this.buildFlat(), (fc: FlatComment) => {
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
              }, (fc: FlatComment) => `${fc.node.id}`)
            }
            .padding(AppSpacing.x4)
            .alignItems(HorizontalAlign.Start)
            .align(Alignment.TopStart)
          }
          // Scroll 的 align 默认是 Alignment.Center，内容矮于视口时会被居中；
          // 显式设为 TopStart，让内容从顶部开始排列
          .width('100%')
          .align(Alignment.TopStart)
          .layoutWeight(1)
        }
    }.width('100%').height('100%')
  }
}
