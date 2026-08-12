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

@Component
export struct GeekReaderPage {
  @ObjectLink store: AppStore
  @State topStories: Story[] = []
  @State latestStories: Story[] = []
  @State topStatus: AsyncStatus = AsyncStatus.Idle
  @State latestStatus: AsyncStatus = AsyncStatus.Idle
  @State tab: string = 'top'
  @State errorMessage: string = ''
  @State refreshing: boolean = false
  @State drawerOpen: boolean = false

  aboutToAppear(): void {
    this.load('top')
  }

  private async load(type: string): Promise<void> {
    if (type === 'top') this.topStatus = AsyncStatus.Loading
    else this.latestStatus = AsyncStatus.Loading
    try {
      const ids = await fetchStories(type)
      const slice = ids.ids.slice(0, PAGE)
      const stories = await fetchStoriesResolved(slice)
      if (type === 'top') {
        this.topStories = stories
        this.topStatus = stories.length === 0 ? AsyncStatus.Empty : AsyncStatus.Success
      } else {
        this.latestStories = stories
        this.latestStatus = stories.length === 0 ? AsyncStatus.Empty : AsyncStatus.Success
      }
    } catch (e) {
      this.errorMessage = e instanceof Error ? e.message : '网络错误'
      if (type === 'top') this.topStatus = AsyncStatus.Error
      else this.latestStatus = AsyncStatus.Error
    } finally {
      this.refreshing = false
    }
  }

  private refresh(): void {
    this.refreshing = true
    this.vibrate()
    this.load(this.tab).then(() => {
      const ok = this.currentStatus === AsyncStatus.Success
      this.store.showToast(ok ? '已刷新' : '刷新失败', !ok)
    })
  }

  private vibrate(): void {
    try { vibrator.startVibration({ type: 'time', duration: 18 }, { id: 0, usage: 'notification' }) } catch (e) {}
  }

  private get currentStories(): Story[] {
    return this.tab === 'top' ? this.topStories : this.latestStories
  }

  private get currentStatus(): AsyncStatus {
    return this.tab === 'top' ? this.topStatus : this.latestStatus
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
    }.width('100%').height(56).padding({ left: AppSpacing.x5, right: AppSpacing.x4 })
    .onClick(() => this.goto(route))
  }

  @Builder
  ReaderContent() {
    Column() {
      // 顶栏：汉堡 + 标题
      Row() {
        Row() { Text('☰').fontSize(24).fontColor(AppColors.text) }
          .width(48).height(48).justifyContent(FlexAlign.Center)
          .onClick(() => { this.vibrate(); this.drawerOpen = true })
        Text('极客译读').fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppColors.text)
          .layoutWeight(1).textAlign(TextAlign.Center)
        Blank().width(48)
      }.width('100%').height(56).padding({ left: AppSpacing.x2, right: AppSpacing.x2 })
      .border({ width: { bottom: 1 }, color: AppColors.border })

      Row() {
        Text('精选').padding(AppSpacing.x4)
          .fontColor(this.tab === 'top' ? AppColors.brand : AppColors.text)
          .fontWeight(this.tab === 'top' ? FontWeight.Bold : FontWeight.Normal)
          .onClick(() => { this.tab = 'top' })
        Text('最新').padding(AppSpacing.x4)
          .fontColor(this.tab === 'latest' ? AppColors.brand : AppColors.text)
          .fontWeight(this.tab === 'latest' ? FontWeight.Bold : FontWeight.Normal)
          .onClick(() => { this.tab = 'latest'; if (this.latestStatus === AsyncStatus.Idle) this.load('latest') })
      }.width('100%')

      if (this.currentStatus === AsyncStatus.Loading) {
        Column() { LoadingProgress().width(48).height(48).color(AppColors.brand) }
          .justifyContent(FlexAlign.Center).layoutWeight(1).width('100%')
      } else if (this.currentStatus === AsyncStatus.Empty || this.currentStatus === AsyncStatus.Error) {
        Column({ space: AppSpacing.x3 }) {
          AppIcon({ name: AppIconName.Globe, iconSize: 48, color: AppColors.border })
          Text(this.currentStatus === AsyncStatus.Error ? `加载失败：${this.errorMessage}` : '暂无内容，下拉刷新重试')
            .fontColor(AppColors.textSecondary).fontSize(14).textAlign(TextAlign.Center)
            .padding({ left: AppSpacing.x6, right: AppSpacing.x6 })
          Text('后端 192.168.20.120:8787').fontColor(AppColors.border).fontSize(11)
          Button('重试').onClick(() => this.refresh())
        }.justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).layoutWeight(1)
      } else {
        Refresh({ refreshing: $$this.refreshing }) {
          List({ space: AppSpacing.x3 }) {
            ForEach(this.currentStories, (s: Story) => {
              ListItem() {
                Column({ space: AppSpacing.x1 }) {
                  ImmersiveTranslation({ text: s.title, locale: this.store.language })
                  Text(`${s.score} 分 · ${s.by} · ${s.commentsCount} 评论`)
                    .fontSize(12).fontColor(AppColors.textSecondary)
                }.alignItems(HorizontalAlign.Start).padding(AppSpacing.x4)
                .border({ width: { bottom: 1 }, color: AppColors.border })
              }.onClick(() => this.openStory(s.id))
            }, (s: Story) => `${s.id}`)
          }
        }.onRefreshing(() => this.refresh()).layoutWeight(1)
      }
    }.width('100%').height('100%')
  }

  build() {
    // 原生 SideBarContainer：左抽屉 + 主内容；autoHide 点击遮罩收起，左滑手势原生支持。
    SideBarContainer() {
      this.DrawerMenu()
      this.ReaderContent()
    }
    .showSideBar(this.drawerOpen)
    .sideBarPosition(SideBarPosition.Start)
    .sideBarWidth('78%')
    .autoHide(true)
    .onChange((show: boolean) => { this.drawerOpen = show })
    .width('100%').height('100%')
  }
}
