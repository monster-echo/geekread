import vibrator from '@ohos.vibrator'
import { AppStore } from '../../../state/AppStore'
import { AppRoute } from '../../../navigation/AppRoute'
import { AsyncStatus } from '../../../state/AsyncState'
import { PageHeader } from '../../../design_system/Components'
import { AppIcon, AppIconName } from '../../../design_system/AppIcon'
import { AppColors, AppRadii, AppSpacing } from '../../../theme/AppTokens'
import { fetchStories, fetchStoriesResolved } from '../data/GeekReaderApiClient'
import { Story } from '../domain/Models'
import { ImmersiveTranslation } from '../components/ImmersiveTranslation'

const PAGE: number = 20
const SKELETON_COUNT: number = 8

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
      this.errorMessage = e instanceof Error ? e.message : '加载失败'
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
    try {
      vibrator.startVibration({ type: 'time', duration: 18 }, { id: 0, usage: 'notification' })
    } catch (e) {
      // 无震动权限或硬件不支持时忽略
    }
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

  @Builder
  SkeletonRow() {
    Column({ space: AppSpacing.x1 }) {
      Row().width('90%').height(18).borderRadius(AppRadii.small).backgroundColor(AppColors.surfaceMuted)
      Row().width('55%').height(18).borderRadius(AppRadii.small).backgroundColor(AppColors.surfaceMuted)
      Row().width('40%').height(12).borderRadius(AppRadii.small).backgroundColor(AppColors.border)
    }
    .alignItems(HorizontalAlign.Start)
    .padding(AppSpacing.x4)
    .border({ width: { bottom: 1 }, color: AppColors.border })
  }

  @Builder
  EmptyState(message: string) {
    Column({ space: AppSpacing.x3 }) {
      AppIcon({ name: AppIconName.Globe, iconSize: 48, color: AppColors.border })
      Text(message)
        .fontColor(AppColors.textSecondary)
        .fontSize(14)
        .textAlign(TextAlign.Center)
        .padding({ left: AppSpacing.x6, right: AppSpacing.x6 })
      Text('后端：192.168.20.120:8787（手机需与 Mac 同一 WiFi）')
        .fontColor(AppColors.border)
        .fontSize(11)
        .textAlign(TextAlign.Center)
      Button('重试').onClick(() => this.refresh())
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .layoutWeight(1)
  }

  build() {
    Column() {
      PageHeader({ store: this.store, title: '极客译读' })
      Row() {
        Text('精选')
          .padding(AppSpacing.x4)
          .fontColor(this.tab === 'top' ? AppColors.brand : AppColors.text)
          .fontWeight(this.tab === 'top' ? FontWeight.Bold : FontWeight.Normal)
          .onClick(() => { this.tab = 'top' })
        Text('最新')
          .padding(AppSpacing.x4)
          .fontColor(this.tab === 'latest' ? AppColors.brand : AppColors.text)
          .fontWeight(this.tab === 'latest' ? FontWeight.Bold : FontWeight.Normal)
          .onClick(() => {
            this.tab = 'latest'
            if (this.latestStatus === AsyncStatus.Idle) this.load('latest')
          })
      }.width('100%')

      if (this.currentStatus === AsyncStatus.Loading) {
        // 骨架屏：8 行灰色占位
        List({ space: AppSpacing.x3 }) {
          ForEach([0, 1, 2, 3, 4, 5, 6, 7], (i: number) => {
            ListItem() { this.SkeletonRow() }
          }, (i: number) => `sk-${i}`)
        }.layoutWeight(1)
      } else if (this.currentStatus === AsyncStatus.Empty) {
        this.EmptyState('暂无内容，下拉刷新重试')
      } else if (this.currentStatus === AsyncStatus.Error) {
        this.EmptyState(`加载失败：${this.errorMessage}`)
      } else {
        Refresh({ refreshing: $$this.refreshing }) {
          List({ space: AppSpacing.x3 }) {
            ForEach(this.currentStories, (s: Story) => {
              ListItem() {
                Column({ space: AppSpacing.x1 }) {
                  ImmersiveTranslation({ text: s.title, locale: this.store.language })
                  Text(`${s.score} 分 · ${s.by} · ${s.commentsCount} 评论`)
                    .fontSize(12).fontColor(AppColors.textSecondary)
                }
                .alignItems(HorizontalAlign.Start)
                .padding(AppSpacing.x4)
                .border({ width: { bottom: 1 }, color: AppColors.border })
              }
              .onClick(() => this.openStory(s.id))
            }, (s: Story) => `${s.id}`)
          }
        }
        .onRefreshing(() => this.refresh())
        .layoutWeight(1)
      }
    }.width('100%').height('100%')
  }
}
