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
  @State stories: Story[] = []
  @State status: AsyncStatus = AsyncStatus.Idle
  @State tab: string = 'top'
  @State errorMessage: string = ''
  @State refreshing: boolean = false
  @State drawerOpen: boolean = false

  aboutToAppear(): void {
    this.load(this.tab)
  }

  private async load(type: string): Promise<void> {
    this.status = AsyncStatus.Loading
    try {
      const ids = await fetchStories(type)
      const slice = ids.ids.slice(0, PAGE)
      const result = await fetchStoriesResolved(slice)
      this.stories = result
      this.status = result.length === 0 ? AsyncStatus.Empty : AsyncStatus.Success
    } catch (e) {
      this.errorMessage = e instanceof Error ? e.message : '网络错误'
      this.status = AsyncStatus.Error
    } finally {
      this.refreshing = false
    }
  }

  private refresh(): void {
    this.refreshing = true
    this.vibrate()
    this.load(this.tab).then(() => {
      const ok = this.status === AsyncStatus.Success
      this.store.showToast(ok ? '已刷新' : '刷新失败', !ok)
    })
  }

  private switchTab(type: string): void {
    if (this.tab === type) return
    this.tab = type
    this.load(type)
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
    }.width('100%').height(56).padding({ left: AppSpacing.x5, right: AppSpacing.x4 })
    .onClick(() => this.goto(route))
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

  build() {
    SideBarContainer() {
      this.DrawerMenu()
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

        // Tab
        Row() {
          Text('精选').padding(AppSpacing.x4)
            .fontColor(this.tab === 'top' ? AppColors.brand : AppColors.text)
            .fontWeight(this.tab === 'top' ? FontWeight.Bold : FontWeight.Normal)
            .onClick(() => this.switchTab('top'))
          Text('最新').padding(AppSpacing.x4)
            .fontColor(this.tab === 'latest' ? AppColors.brand : AppColors.text)
            .fontWeight(this.tab === 'latest' ? FontWeight.Bold : FontWeight.Normal)
            .onClick(() => this.switchTab('latest'))
        }.width('100%')

        if (this.status === AsyncStatus.Loading) {
          Column() { LoadingProgress().width(48).height(48).color(AppColors.brand) }
            .justifyContent(FlexAlign.Center).layoutWeight(1).width('100%')
        } else if (this.status === AsyncStatus.Empty) {
          Column({ space: AppSpacing.x3 }) {
            AppIcon({ name: AppIconName.Globe, iconSize: 48, color: AppColors.border })
            Text('暂无内容，下拉刷新重试').fontColor(AppColors.textSecondary).fontSize(14)
          }.justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).layoutWeight(1)
        } else if (this.status === AsyncStatus.Error) {
          Column({ space: AppSpacing.x3 }) {
            AppIcon({ name: AppIconName.Globe, iconSize: 48, color: AppColors.border })
            Text(`加载失败：${this.errorMessage}`).fontColor(AppColors.textSecondary).fontSize(14)
              .padding({ left: AppSpacing.x6, right: AppSpacing.x6 }).textAlign(TextAlign.Center)
            Button('重试').onClick(() => this.refresh())
          }.justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).layoutWeight(1)
        } else {
          Refresh({ refreshing: $$this.refreshing }) {
            List({ space: AppSpacing.x3 }) {
              ForEach(this.stories, (s: Story) => {
                ListItem() { this.StoryItem(s) }.onClick(() => this.openStory(s.id))
              }, (s: Story) => `${s.id}`)
            }
          }.onRefreshing(() => this.refresh()).layoutWeight(1)
        }
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
