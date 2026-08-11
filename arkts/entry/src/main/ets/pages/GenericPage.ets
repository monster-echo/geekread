import { AppStore } from '../state/AppStore'
import { AppButton, PageHeader } from '../design_system/Components'
import { AppIcon, AppIconName } from '../design_system/AppIcon'
import { AsyncState, AsyncStatus } from '../state/AsyncState'
import { AppColors, AppSpacing } from '../theme/AppTokens'

@Component
export struct StateGalleryPage {
  @ObjectLink store: AppStore
  @State index: number = 0
  private states: AsyncState<string[]>[] = [
    new AsyncState<string[]>(AsyncStatus.Loading),
    new AsyncState<string[]>(AsyncStatus.Empty),
    new AsyncState<string[]>(AsyncStatus.Error, undefined, '服务暂时不可用'),
    new AsyncState<string[]>(AsyncStatus.Offline),
    new AsyncState<string[]>(AsyncStatus.Unauthorized),
    new AsyncState<string[]>(AsyncStatus.Success, ['状态加载成功'])
  ]

  build() {
    Column() {
      PageHeader({ store: this.store, title: '状态库' })
      Column({ space: AppSpacing.x4 }) {
        AppIcon({
          name: this.iconFor(this.states[this.index].status),
          color: AppColors.brand,
          iconSize: 56
        })
        Text(this.labelFor(this.states[this.index]))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
        Text('状态互斥，由统一状态机驱动。')
          .fontColor(AppColors.textSecondary)
        AppButton({
          label: '切换状态',
          onTap: () => this.index = (this.index + 1) % this.states.length
        })
      }
      .padding(AppSpacing.x6)
      .justifyContent(FlexAlign.Center)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  private iconFor(status: AsyncStatus): AppIconName {
    if (status === AsyncStatus.Error) return AppIconName.Alert
    if (status === AsyncStatus.Offline) return AppIconName.Globe
    if (status === AsyncStatus.Unauthorized) return AppIconName.Lock
    if (status === AsyncStatus.Empty) return AppIconName.Gift
    if (status === AsyncStatus.Loading) return AppIconName.Settings
    return AppIconName.Check
  }

  private labelFor(state: AsyncState<string[]>): string {
    switch (state.status) {
      case AsyncStatus.Idle: return '等待操作'
      case AsyncStatus.Loading: return '正在加载'
      case AsyncStatus.Success: return '加载成功'
      case AsyncStatus.Empty: return '暂无数据'
      case AsyncStatus.Error: return state.message ?? '发生错误'
      case AsyncStatus.Offline: return '网络连接已断开'
      case AsyncStatus.Unauthorized: return '请先登录'
    }
  }
}

