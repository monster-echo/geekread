import vibrator from '@ohos.vibrator'
import { AppStore } from '../../../state/AppStore'
import { AppRoute } from '../../../navigation/AppRoute'
import { AsyncStatus } from '../../../state/AsyncState'
import { AppColors, AppSpacing } from '../../../theme/AppTokens'
import { AppIcon, AppIconName } from '../../../design_system/AppIcon'
import { localized, appString, AppString } from '../../../localization/AppStrings'
import { fetchQuota, fetchStories, ReaderQuota } from '../data/GeekReaderApiClient'
import { readStories, saveStories } from '../data/StoryCache'
import { resetQuotaGate } from '../application/TranslationCache'
import { Story } from '../domain/Models'
import { telemetry } from '../../../telemetry/Telemetry'
import { ImmersiveTranslation } from '../components/ImmersiveTranslation'

@Component
export struct GeekReaderPage {
  @ObjectLink store: AppStore
  @State topStories: Story[] = []
  @State topStatus: AsyncStatus = AsyncStatus.Idle
  @State topIds: number[] = []
  @State latestStories: Story[] = []
  @State latestStatus: AsyncStatus = AsyncStatus.Idle
  @State latestIds: number[] = []
  @State loadingMore: boolean = false
  @State activeTab: number = 0
  @State errorMessage: string = ''
  @State headerVisible: boolean = true
  @State refreshing: boolean = false
  @State drawerOpen: boolean = false
  @State quota: ReaderQuota | null = null

  aboutToAppear(): void {
    // 页面由 Navigation 压栈保留，aboutToAppear 只在首次触发——回来不会重刷。
    // 先同步渲染上次缓存（毫秒级秒开），再后台刷新覆盖。
    this.renderFromCache()
    this.load('top')
    this.load('latest')
  }

  /** 冷启动从磁盘缓存同步填充列表，立即渲染（不闪 loading）。 */
  private renderFromCache(): void {
    const top = readStories('top')
    if (top !== null && top.length > 0) {
      this.topStories = top
      this.topIds = top.map((s: Story) => s.id)
      this.topStatus = AsyncStatus.Success
    }
    const latest = readStories('latest')
    if (latest !== null && latest.length > 0) {
      this.latestStories = latest
      this.latestIds = latest.map((s: Story) => s.id)
      this.latestStatus = AsyncStatus.Success
    }
  }

  private async load(type: string): Promise<void> {
    const hasContent = (type === 'top' ? this.topStories : this.latestStories).length > 0
    // 有缓存时保持内容可见（后台刷新），无缓存才显示 loading。
    if (!hasContent) this.setStatus(type, AsyncStatus.Loading)
    try {
      const stories = await fetchStories(type)
      this.putStories(type, stories)
      this.putIds(type, stories.map((s: Story) => s.id))
      saveStories(type, stories)
      this.setStatus(type, stories.length === 0 ? AsyncStatus.Empty : AsyncStatus.Success)
    } catch (e) {
      // 有缓存内容时静默保留（避免 Error 覆盖已渲染列表）；无缓存才报错。
      if (!hasContent) {
        this.errorMessage = e instanceof Error ? e.message : '网络错误'
        telemetry.report(new Error(`stories_fetch_failed_${type}: ${this.errorMessage}`))
        this.setStatus(type, AsyncStatus.Error)
      }
    } finally {
      this.refreshing = false
    }
  }

  private async loadMore(type: string): Promise<void> {
    // 列表已由 fetchStories 一次拉全（完整 story），无需再分页请求；保留空实现。
  }

  private isNoMore(type: string): boolean {
    const ids = type === 'top' ? this.topIds : this.latestIds
    const stories = type === 'top' ? this.topStories : this.latestStories
    return ids.length > 0 && stories.length >= ids.length
  }

  private setStatus(type: string, s: AsyncStatus): void {
    if (type === 'top') this.topStatus = s; else this.latestStatus = s
  }

  private putStories(type: string, arr: Story[]): void {
    if (type === 'top') this.topStories = arr; else this.latestStories = arr
  }

  private putIds(type: string, ids: number[]): void {
    if (type === 'top') this.topIds = ids; else this.latestIds = ids
  }

  private refresh(): void {
    this.refreshing = true
    this.vibrate()
    const type = this.activeTab === 0 ? 'top' : 'latest'
    this.load(type).then(() => {
      const ok = (type === 'top' ? this.topStatus : this.latestStatus) === AsyncStatus.Success
      this.store.showToast(ok ? appString(AppString.RefreshSuccess, this.store.language) : appString(AppString.RefreshFail, this.store.language), !ok)
    })
  }

  private vibrate(): void {
    try { vibrator.startVibration({ type: 'time', duration: 18 }, { id: 0, usage: 'notification' }) } catch (e) {}
  }

  private openStory(id: number): void {
    telemetry.click('article_open', 'geekreader')
    // 详情走外层导航栈（route_GeekReaderDetail），全局一条返回栈；返回回本页，滚动位置保留。
    this.store.geekReaderStoryId = id
    this.store.navigate(AppRoute.GeekReaderDetail)
  }

  private goto(route: string): void {
    this.drawerOpen = false
    this.store.navigateByName(route)
  }

  private async loadQuota(): Promise<void> {
    try {
      this.quota = await fetchQuota()
      // 服务端确认配额有剩余时解除客户端熔断（如跨日刷新、服务端配额变化）
      if (this.quota.remaining > 0) resetQuotaGate()
    } catch (e) {
      this.quota = null
    }
  }

  private onScrollDir(offset: number): void {
    if (offset > 1) this.headerVisible = false
    else if (offset < -1) this.headerVisible = true
  }

  @Builder
  ListFooter(type: string) {
    // 始终占位 48px，作为列表末尾的底部安全间距（只在滚到底时可见，不常驻空白）。
    Row() {
      if (this.loadingMore) {
        Row({ space: AppSpacing.x2 }) {
          LoadingProgress().width(20).height(20).color(AppColors.brand)
          Text(appString(AppString.LoadingMore, this.store.language)).fontSize(12).fontColor(AppColors.textSecondary)
        }
      } else if (this.isNoMore(type)) {
        Text(appString(AppString.NoMore, this.store.language)).fontSize(12).fontColor(AppColors.textSecondary)
      }
    }.width('100%').height(48).justifyContent(FlexAlign.Center)
  }

  @Builder
  DrawerMenu() {
    Column() {
      // ── 品牌 logo ──
      Row({ space: AppSpacing.x2 }) {
        Image($r('app.media.app_icon'))
          .width(36).height(36).borderRadius(9)
        Column({ space: 2 }) {
          Text(this.store.config?.brand.appName ?? '极客译读')
            .fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppColors.text)
          Text('GeekRead').fontSize(11).fontColor(AppColors.textSecondary)
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: AppSpacing.x5, right: AppSpacing.x5, top: AppSpacing.x5, bottom: AppSpacing.x2 })
      .alignItems(VerticalAlign.Center)
      this.MenuRow(appString(AppString.Settings, this.store.language), 'settings.home')
      this.MenuRow(appString(AppString.About, this.store.language), 'settings.about')
      this.MenuRow(appString(AppString.Legal, this.store.language), 'settings.legal')
      Blank()
      // ── 底部：用户信息 + 今日翻译额度 ──
      // 用户信息（头像 + 昵称/登录提示），点击 → 个人资料 / 登录
      Row({ space: AppSpacing.x3 }) {
        // 头像：有 avatarUrl 显示图片，否则用品牌色占位图标
        if ((this.store.user?.avatarUrl ?? '').length > 0) {
          Image(this.store.user?.avatarUrl ?? '')
            .width(48).height(48).borderRadius(24)
            .objectFit(ImageFit.Cover)
            .backgroundColor(AppColors.surfaceMuted)
        } else {
          Column() {
            AppIcon({ name: AppIconName.User, color: AppColors.brand, iconSize: 24 })
          }
          .width(48).height(48).borderRadius(24)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(AppColors.brandSoft)
        }
        Column({ space: AppSpacing.x1 }) {
          Text(this.store.signedIn ? (this.store.user?.displayName ?? appString(AppString.NotLoggedIn, this.store.language)) : appString(AppString.NotLoggedIn, this.store.language))
            .fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppColors.text)
          Text(this.store.signedIn ? '' : appString(AppString.Login, this.store.language)).fontSize(12).fontColor(AppColors.brand)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: AppSpacing.x5, right: AppSpacing.x5 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => this.goto(this.store.signedIn ? 'profile.home' : 'SignIn'))
      // 今日翻译额度进度 footer（点击 → 未登录登录页 / 已登录会员页）
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
    }.width('100%').height('100%').backgroundColor(AppColors.surface).alignItems(HorizontalAlign.Start)
  }

  @Builder
  MenuRow(title: string, route: string) {
    Row({ space: AppSpacing.x3 }) {
      Text(title).fontSize(16).fontColor(AppColors.text).layoutWeight(1)
    }.width('100%').height(56).padding({ left: AppSpacing.x5, right: AppSpacing.x4 }).onClick(() => { telemetry.click(`menu_${route}`, 'geekreader'); this.goto(route) })
  }

  @Builder
  StoryItem(s: Story) {
    Column({ space: AppSpacing.x1 }) {
      ImmersiveTranslation({ text: s.title, locale: this.store.language, displayMode: this.store.translationDisplayMode, free: true, rich: false })
      Text(`${s.score}${appString(AppString.PointsComments, this.store.language)}${s.by} · ${s.commentsCount} ${appString(AppString.Comments, this.store.language)}`)
        .fontSize(12).fontColor(AppColors.textSecondary)
    }.alignItems(HorizontalAlign.Start).padding(AppSpacing.x4)
    .border({ width: { bottom: 1 }, color: AppColors.border })
  }

  @Builder
  StatusView(status: AsyncStatus, msg: string) {
    if (status === AsyncStatus.Loading) {
      Column() { LoadingProgress().width(48).height(48).color(AppColors.brand) }
        .justifyContent(FlexAlign.Center).layoutWeight(1).width('100%')
    } else if (status === AsyncStatus.Empty) {
      Column({ space: AppSpacing.x3 }) {
        Text(appString(AppString.NoContent, this.store.language)).fontColor(AppColors.textSecondary).fontSize(14)
      }.justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).layoutWeight(1)
    } else if (status === AsyncStatus.Error) {
      Column({ space: AppSpacing.x3 }) {
        Text(`${appString(AppString.LoadFailed, this.store.language)}：${msg}`).fontColor(AppColors.textSecondary).fontSize(14)
          .padding({ left: AppSpacing.x6, right: AppSpacing.x6 }).textAlign(TextAlign.Center)
        Button(appString(AppString.Retry, this.store.language)).onClick(() => this.refresh())
      }.justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).layoutWeight(1)
    }
  }

  build() {
    SideBarContainer() {
      this.DrawerMenu()
      Column() {
          // 顶栏：汉堡 + 标题（向上滚收起，向下滚展开）
          Row() {
            Row() { Text('☰').fontSize(24).fontColor(AppColors.brand) }
              .width(48).height(48).justifyContent(FlexAlign.Center)
              .onClick(() => { telemetry.click('menu_open', 'geekreader'); this.vibrate(); this.drawerOpen = true })
            Text(this.store.config?.brand.appName ?? '极客译读').fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppColors.text)
              .layoutWeight(1).textAlign(TextAlign.Center)
            Blank().width(48)
          }.width('100%').height(this.headerVisible ? 56 : 0)
          .padding({ left: AppSpacing.x2, right: AppSpacing.x2 })
          .border({ width: { bottom: this.headerVisible ? 1 : 0 }, color: AppColors.border })
          .clip(true).animation({ duration: 220, curve: Curve.EaseOut })

          Tabs({ barPosition: BarPosition.Start, index: this.activeTab }) {
            TabContent() {
              if (this.topStatus === AsyncStatus.Success) {
                Refresh({ refreshing: $$this.refreshing }) {
                  List({ space: AppSpacing.x3 }) {
                    ForEach(this.topStories, (s: Story) => {
                      ListItem() { this.StoryItem(s) }.onClick(() => this.openStory(s.id))
                    }, (s: Story) => `${s.id}`)
                    ListItem() { this.ListFooter('top') }
                  }
                  .onScroll((offset: number, state: ScrollState) => this.onScrollDir(offset))
                  .onScrollIndex((start: number, end: number) => {
                    if (this.topStories.length > 0 && end >= this.topStories.length - 5) this.loadMore('top')
                  })
                }.onRefreshing(() => this.refresh()).layoutWeight(1).width('100%')
              } else {
                this.StatusView(this.topStatus, this.errorMessage)
              }
            }.tabBar(new SubTabBarStyle(appString(AppString.TopStories, this.store.language))
              .labelStyle({
                selectedColor: AppColors.brand,
                unselectedColor: AppColors.textSecondary
              })
              .indicator({ color: AppColors.brand }))

            TabContent() {
              if (this.latestStatus === AsyncStatus.Success) {
                Refresh({ refreshing: $$this.refreshing }) {
                  List({ space: AppSpacing.x3 }) {
                    ForEach(this.latestStories, (s: Story) => {
                      ListItem() { this.StoryItem(s) }.onClick(() => this.openStory(s.id))
                    }, (s: Story) => `${s.id}`)
                    ListItem() { this.ListFooter('latest') }
                  }
                  .onScroll((offset: number, state: ScrollState) => this.onScrollDir(offset))
                  .onScrollIndex((start: number, end: number) => {
                    if (this.latestStories.length > 0 && end >= this.latestStories.length - 5) this.loadMore('latest')
                  })
                }.onRefreshing(() => this.refresh()).layoutWeight(1).width('100%')
              } else {
                this.StatusView(this.latestStatus, this.errorMessage)
              }
            }.tabBar(new SubTabBarStyle(appString(AppString.LatestStories, this.store.language))
              .labelStyle({
                selectedColor: AppColors.brand,
                unselectedColor: AppColors.textSecondary
              })
              .indicator({ color: AppColors.brand }))
          }
          .onChange((i: number) => { telemetry.click(`tab_${i}`, 'geekreader'); this.activeTab = i })
          .barMode(BarMode.Fixed)
          .scrollable(true)
          .layoutWeight(1).width('100%')
        }.width('100%').height('100%')
    }
    .showSideBar(this.drawerOpen)
    .sideBarPosition(SideBarPosition.Start)
    .sideBarWidth('78%')
    .autoHide(true)
    .showControlButton(false)
    .onChange((show: boolean) => { this.drawerOpen = show; if (show) this.loadQuota() })
    .width('100%').height('100%')
  }
}
