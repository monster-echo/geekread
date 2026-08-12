import vibrator from '@ohos.vibrator'
import { AppStore } from '../../../state/AppStore'
import { AppRoute } from '../../../navigation/AppRoute'
import { AsyncStatus } from '../../../state/AsyncState'
import { AppIcon, AppIconName } from '../../../design_system/AppIcon'
import { AppColors, AppRadii, AppSpacing } from '../../../theme/AppTokens'
import { localized } from '../../../localization/AppStrings'
import { fetchStories, fetchStoriesResolved } from '../data/GeekReaderApiClient'
import { Story } from '../domain/Models'
import { ImmersiveTranslation } from '../components/ImmersiveTranslation'

const PAGE: number = 20

// 模块级缓存：从文章详情返回时不重新请求，直接还原列表数据。
class TabCache {
  stories: Story[] = []
  status: AsyncStatus = AsyncStatus.Idle
  loaded: boolean = false
}
class GeekCache {
  top: TabCache = new TabCache()
  latest: TabCache = new TabCache()
}
const cache: GeekCache = new GeekCache()

@Component
export struct GeekReaderPage {
  @ObjectLink store: AppStore
  @State topStories: Story[] = cache.top.stories
  @State topStatus: AsyncStatus = cache.top.status
  @State latestStories: Story[] = cache.latest.stories
  @State latestStatus: AsyncStatus = cache.latest.status
  @State activeTab: number = 0
  @State errorMessage: string = ''
  @State headerVisible: boolean = true
  @State refreshing: boolean = false
  @State drawerOpen: boolean = false

  aboutToAppear(): void {
    // 还原缓存；未加载过的 tab 才发请求。
    if (!cache.top.loaded) this.load('top')
    if (!cache.latest.loaded) this.load('latest')
  }

  private async load(type: string): Promise<void> {
    this.setStatus(type, AsyncStatus.Loading)
    try {
      const ids = await fetchStories(type)
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

  private setStatus(type: string, s: AsyncStatus): void {
    this.tabOf(type).status = s
    if (type === 'top') this.topStatus = s; else this.latestStatus = s
  }

  private putStories(type: string, arr: Story[]): void {
    const c: TabCache = this.tabOf(type)
    c.stories = arr
    c.loaded = true
    if (type === 'top') this.topStories = arr; else this.latestStories = arr
  }

  private tabOf(type: string): TabCache {
    return type === 'top' ? cache.top : cache.latest
  }

  private refresh(): void {
    this.refreshing = true
    this.vibrate()
    const type = this.activeTab === 0 ? 'top' : 'latest'
    this.load(type).then(() => {
      const ok = (type === 'top' ? this.topStatus : this.latestStatus) === AsyncStatus.Success
      this.store.showToast(ok ? '已刷新' : '刷新失败', !ok)
    })
  }

  private vibrate(): void {
    try { vibrator.startVibration({ type: 'time', duration: 18 }, { id: 0, usage: 'notification' }) } catch (e) {}
  }

  private openStory(id: number): void {
    this.store.geekReaderStoryId = id
    this.store.navigate(AppRoute.GeekReaderDetail)
  }

  private goto(route: AppRoute): void {
    this.drawerOpen = false
    this.store.navigate(route)
  }

  @Builder
  DrawerMenu() {
    Column() {
      Column({ space: AppSpacing.x1 }) {
        Text(this.store.signedIn ? (this.store.user?.displayName ?? '已登录') : '未登录')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppColors.text)
        Text(this.store.signedIn ? '' : '点击登录').fontSize(12).fontColor(AppColors.brand)
      }.width('100%').alignItems(HorizontalAlign.Start).padding(AppSpacing.x5)
      .onClick(() => this.goto(this.store.signedIn ? AppRoute.Profile : AppRoute.SignIn))
      this.MenuRow(localized('设置', 'Settings', this.store.language), AppRoute.Settings)
      this.MenuRow(localized('关于与版本', 'About', this.store.language), AppRoute.About)
      this.MenuRow(localized('协议与政策', 'Legal', this.store.language), AppRoute.Legal)
      Blank()
      Text('GeekRead · 极客译读').fontSize(11).fontColor(AppColors.textSecondary).padding(AppSpacing.x5)
    }.width('100%').height('100%').backgroundColor(AppColors.surface).alignItems(HorizontalAlign.Start)
  }

  @Builder
  MenuRow(title: string, route: AppRoute) {
    Row({ space: AppSpacing.x3 }) {
      Text(title).fontSize(16).fontColor(AppColors.text).layoutWeight(1)
      AppIcon({ name: AppIconName.ChevronRight, iconSize: 18, color: AppColors.textSecondary })
    }.width('100%').height(56).padding({ left: AppSpacing.x5, right: AppSpacing.x4 }).onClick(() => this.goto(route))
  }

  @Builder
  StoryItem(s: Story) {
    Column({ space: AppSpacing.x1 }) {
      ImmersiveTranslation({ text: s.title, locale: this.store.language })
      Text(`${s.score} 分 · ${s.by} · ${s.commentsCount} 评论`)
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
        AppIcon({ name: AppIconName.Globe, iconSize: 48, color: AppColors.border })
        Text('暂无内容，下拉刷新重试').fontColor(AppColors.textSecondary).fontSize(14)
      }.justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).layoutWeight(1)
    } else if (status === AsyncStatus.Error) {
      Column({ space: AppSpacing.x3 }) {
        AppIcon({ name: AppIconName.Globe, iconSize: 48, color: AppColors.border })
        Text(`加载失败：${msg}`).fontColor(AppColors.textSecondary).fontSize(14)
          .padding({ left: AppSpacing.x6, right: AppSpacing.x6 }).textAlign(TextAlign.Center)
        Button('重试').onClick(() => this.refresh())
      }.justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).layoutWeight(1)
    }
  }

  @Builder
  TabList(stories: Story[], status: AsyncStatus, msg: string) {
    if (status === AsyncStatus.Success) {
      Refresh({ refreshing: $$this.refreshing }) {
        List({ space: AppSpacing.x3 }) {
          ForEach(stories, (s: Story) => {
            ListItem() { this.StoryItem(s) }.onClick(() => this.openStory(s.id))
          }, (s: Story) => `${s.id}`)
        }
        .onScroll((offset: number, state: ScrollState) => {
          if (offset > 1) this.headerVisible = false
          else if (offset < -1) this.headerVisible = true
        })
      }.onRefreshing(() => this.refresh()).layoutWeight(1)
    } else {
      this.StatusView(status, msg)
    }
  }

  build() {
    SideBarContainer() {
      this.DrawerMenu()
      Column() {
        // 顶栏：汉堡 + 标题（向上滚收起，向下滚展开）
        Row() {
          Row() { Text('☰').fontSize(24).fontColor(AppColors.text) }
            .width(48).height(48).justifyContent(FlexAlign.Center)
            .onClick(() => { this.vibrate(); this.drawerOpen = true })
          Text('极客译读').fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppColors.text)
            .layoutWeight(1).textAlign(TextAlign.Center)
          Blank().width(48)
        }.width('100%').height(this.headerVisible ? 56 : 0)
        .padding({ left: AppSpacing.x2, right: AppSpacing.x2 })
        .border({ width: { bottom: this.headerVisible ? 1 : 0 }, color: AppColors.border })
        .clip(true).animation({ duration: 220, curve: Curve.EaseOut })

        // 原生 Tabs：左右滑动切换 精选/最新
        Tabs({ barPosition: BarPosition.Start, index: this.activeTab }) {
          TabContent() {
            this.TabList(this.topStories, this.topStatus, this.errorMessage)
          }.tabBar('精选')
          TabContent() {
            this.TabList(this.latestStories, this.latestStatus, this.errorMessage)
          }.tabBar('最新')
        }
        .onChange((i: number) => { this.activeTab = i })
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
    .onChange((show: boolean) => { this.drawerOpen = show })
    .width('100%').height('100%')
  }
}
