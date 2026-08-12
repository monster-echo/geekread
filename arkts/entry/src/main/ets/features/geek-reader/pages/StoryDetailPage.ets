import { AppStore } from '../../../state/AppStore'
import { appString, AppString } from '../../../localization/AppStrings'
import { AppColors, AppSpacing } from '../../../theme/AppTokens'
import { fetchItems } from '../data/GeekReaderApiClient'
import { Comment, Story, toComment, toStory } from '../domain/Models'
import { buildCommentTree, CommentNode, FlatComment, flattenTree } from '../application/Comments'
import { ImmersiveTranslation } from '../components/ImmersiveTranslation'

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
      const all: Comment[] = []
      const seen: Set<number> = new Set<number>()
      let frontier: number[] = s?.kids ?? []
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
      this.story = s
      this.tree = s === null ? [] : buildCommentTree(all, s.id)
    } finally {
      this.loading = false
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

  private buildFlat(): FlatComment[] {
    const set: Set<number> = new Set<number>(this.collapsed)
    const acc: FlatComment[] = []
    flattenTree(this.tree, 0, set, acc)
    return acc
  }

  build() {
    // 作为 Navigation 的 NavDestination：返回由 Navigation 标题栏的返回箭头/系统手势自动 pop。
    NavDestination() {
      Column() {
        if (this.loading) {
          Column() { LoadingProgress().width(40).height(40).color(AppColors.brand) }
            .justifyContent(FlexAlign.Center).layoutWeight(1).width('100%')
        } else if (this.story === null) {
          Column() { Text(appString(AppString.NoContent, this.store.language)).fontColor(AppColors.textSecondary) }
            .justifyContent(FlexAlign.Center).layoutWeight(1).width('100%')
        } else {
          Scroll() {
            Column({ space: AppSpacing.x3 }) {
              ImmersiveTranslation({ text: this.story.title, locale: this.store.language, displayMode: this.store.translationDisplayMode, free: true })
              if (this.story.url !== undefined && this.story.url.length > 0) {
                Text(appString(AppString.ReadOriginal, this.store.language)).fontColor(AppColors.brand).fontSize(14)
              } else if (this.story.text !== undefined && this.story.text.length > 0) {
                ImmersiveTranslation({ text: this.story.text, locale: this.store.language, displayMode: this.store.translationDisplayMode, free: true })
              }
              Text(`${this.story.score}${appString(AppString.PointsComments, this.store.language)}${this.story.by} · ${this.story.commentsCount} ${appString(AppString.Comments, this.store.language)}`)
                .fontSize(12).fontColor(AppColors.textSecondary)

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
          }.layoutWeight(1)
        }
      }.width('100%').height('100%')
    }
    .title(this.story?.title ?? appString(AppString.Article, this.store.language))
    .hideTitleBar(false)
    .mode(NavDestinationMode.STANDARD)
  }
}
