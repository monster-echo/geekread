import vibrator from '@ohos.vibrator'
import { AppStore } from '../../../state/AppStore'
import { AppRoute } from '../../../navigation/AppRoute'
import { AsyncStatus } from '../../../state/AsyncState'
import { AppColors, AppSpacing } from '../../../theme/AppTokens'
import { localized, appString, AppString } from '../../../localization/AppStrings'
import { fetchStories, fetchStoriesResolved } from '../data/GeekReaderApiClient'
import { Story } from '../domain/Models'
import { ImmersiveTranslation } from '../components/ImmersiveTranslation'
import { StoryDetailPage } from './StoryDetailPage'

const PAGE: number = 20

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
  private pathStack: NavPathStack = new NavPathStack()

  aboutToAppear(): void {
    // 页面由 Navigation 压栈保留，aboutToAppear 只在首次触发——回来不会重刷。
    this.load('top')
    this.load('latest')
  }

  private async load(type: string): Promise<void> {
    this.setStatus(type, AsyncStatus.Loading)
    try {
      const ids = await fetchStories(type)
      if (type === 'top') this.topIds = ids.ids; else this.latestIds = ids.ids
      const result = await fetchStoriesResolved(ids.ids.slice(0, PAGE))
      this.putStories(type, result)
      this.setStatus(type, result.length === 0 ? AsyncStatus.Empty : AsyncStatus.Success)
    } catch (e) {
      this.errorMessage = e instanceof Error ? e.message : '网络错误'
      this.setStatus(type, AsyncStatus.Error)
    } finally {
      this.refreshing = false
    }
  }

  private async loadMore(type: string): Promise<void> {
    if (this.loadingMore) return
    const ids = type === 'top' ? this.topIds : this.latestIds
    const stories = type === 'top' ? this.topStories : this.latestStories
    if (ids.length === 0 || stories.length >= ids.length) return
    this.loadingMore = true
    try {
      const next = ids.slice(stories.length, stories.length + PAGE)
      const result = await fetchStoriesResolved(next)
      this.putStories(type, stories.concat(result))
    } catch (e) {
      // 静默：footer 状态自动随 loadingMore 消失
    } finally {
      this.loadingMore = false
    }
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
    // 压栈进详情；源页面（本阅读器）由 Navigation 保留不动，返回时不刷新、滚动位置不变。
    this.store.geekReaderStoryId = id
    this.pathStack.pushPathByName('detail', '')
  }

  private goto(route: string): void {
    this.drawerOpen = false
    this.store.navigateByName(route)
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
      Column({ space: AppSpacing.x1 }) {
        Text(this.store.signedIn ? (this.store.user?.displayName ?? appString(AppString.NotLoggedIn, this.store.language)) : appString(AppString.NotLoggedIn, this.store.language))
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppColors.text)
        Text(this.store.signedIn ? '' : appString(AppString.Login, this.store.language)).fontSize(12).fontColor(AppColors.brand)
      }.width('100%').alignItems(HorizontalAlign.Start).padding(AppSpacing.x5)
      .onClick(() => this.goto(this.store.signedIn ? 'profile.home' : 'SignIn'))
      // Pro 会员入口（显示当前档位）
      Row({ space: AppSpacing.x3 }) {
        Text(this.store.user?.tierId === 'pro' ? 'Pro ✓' : '解锁 Pro')
          .fontSize(16).fontColor(AppColors.brand).fontWeight(FontWeight.Bold).layoutWeight(1)
        Text(this.store.user?.tierId === 'pro' ? '每日 500 次翻译' : '每日 500 次翻译').fontSize(11).fontColor(AppColors.textSecondary)
      }.width('100%').height(56).padding({ left: AppSpacing.x5, right: AppSpacing.x4 })
      .onClick(() => this.goto('membership.home'))
      this.MenuRow(appString(AppString.Settings, this.store.language), 'settings.home')
      this.MenuRow(appString(AppString.About, this.store.language), 'settings.about')
      this.MenuRow(appString(AppString.Legal, this.store.language), 'settings.legal')
      Blank()
      Text('GeekRead · ' + appString(AppString.GeekReaderTitle, this.store.language)).fontSize(11).fontColor(AppColors.textSecondary).padding(AppSpacing.x5)
    }.width('100%').height('100%').backgroundColor(AppColors.surface).alignItems(HorizontalAlign.Start)
  }

  @Builder
  MenuRow(title: string, route: string) {
    Row({ space: AppSpacing.x3 }) {
      Text(title).fontSize(16).fontColor(AppColors.text).layoutWeight(1)
    }.width('100%').height(56).padding({ left: AppSpacing.x5, right: AppSpacing.x4 }).onClick(() => this.goto(route))
  }

  @Builder
  StoryItem(s: Story) {
    Column({ space: AppSpacing.x1 }) {
      ImmersiveTranslation({ text: s.title, locale: this.store.language, displayMode: this.store.translationDisplayMode })
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

  @Builder
  DetailDest(name: string, param: object) {
    if (name === 'detail') {
      StoryDetailPage({ store: this.store })
    }
  }

  build() {
    SideBarContainer() {
      this.DrawerMenu()
      Navigation(this.pathStack) {
        Column() {
          // 顶栏：汉堡 + 标题（向上滚收起，向下滚展开）
          Row() {
            Row() { Text('☰').fontSize(24).fontColor(AppColors.text) }
              .width(48).height(48).justifyContent(FlexAlign.Center)
              .onClick(() => { this.vibrate(); this.drawerOpen = true })
            Text(appString(AppString.GeekReaderTitle, this.store.language)).fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppColors.text)
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
            }.tabBar(appString(AppString.TopStories, this.store.language))

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
            }.tabBar(appString(AppString.LatestStories, this.store.language))
          }
          .onChange((i: number) => { this.activeTab = i })
          .barMode(BarMode.Fixed)
          .scrollable(true)
          .layoutWeight(1).width('100%')
        }.width('100%').height('100%')
      }
      .navDestination(this.DetailDest)
      .hideTitleBar(true)
      .mode(NavigationMode.Stack)
      .width('100%').height('100%')
    }
    .showSideBar(this.drawerOpen)
    .sideBarPosition(SideBarPosition.Start)
    .sideBarWidth('78%')
    .autoHide(true)
    .showControlButton(false)
    .onChange((show: boolean) => { this.drawerOpen = show })
    .width('100%').height('100%')
  }
}
