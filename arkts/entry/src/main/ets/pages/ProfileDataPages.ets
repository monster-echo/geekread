import pasteboard from '@ohos.pasteboard'
import { AppStore } from '../state/AppStore'
import { AsyncStatus } from '../state/AsyncState'
import { RemoteDataStore } from '../state/RemoteDataStore'
import { AppButton, AppListRow, PageHeader } from '../design_system/Components'
import { AppIconName } from '../design_system/AppIcon'
import { AppColors, AppRadii, AppSpacing } from '../theme/AppTokens'
import { CouponView, UsageScreen } from '../domain/Models'

@Component
export struct StatisticsPage {
  @ObjectLink store: AppStore
  @ObjectLink remote: RemoteDataStore

  aboutToAppear(): void {
    this.remote.loadUsage()
  }

  build() {
    Column() {
      PageHeader({ store: this.store, title: '使用统计' })
      if (this.remote.usageState.status === AsyncStatus.Loading) {
        LoadingProgress().width(40).height(40).layoutWeight(1)
      } else if (this.remote.usageState.status === AsyncStatus.Empty) {
        StateCopy({ message: '开始使用后，这里会显示匿名聚合数据。' })
      } else if (this.remote.usageState.status === AsyncStatus.Success) {
        Scroll() {
          Column({ space: AppSpacing.x3 }) {
            Column() {
              AppListRow({ store: this.store, label: '会话次数',
                value: `${this.remote.usageState.data?.sessions ?? 0}` })
              AppListRow({ store: this.store, label: '页面浏览',
                value: `${this.remote.usageState.data?.screenViews ?? 0}` })
              AppListRow({ store: this.store, label: '活跃时长',
                value: `${this.remote.usageState.data?.activeMinutes ?? 0} 分钟` })
            }.backgroundColor(AppColors.surface).borderRadius(AppRadii.card)
            ForEach(this.remote.usageState.data?.screens ?? [], (screen: UsageScreen) => {
              AppListRow({ store: this.store, label: screen.screenId,
                value: `${screen.views} 次 · ${Math.round(screen.durationMs / 1000)} 秒` })
            })
          }.padding(AppSpacing.x4)
        }.layoutWeight(1)
        .align(Alignment.TopStart)
        .edgeEffect(EdgeEffect.Spring)
      } else {
        RetryState({ message: this.remote.usageState.message ?? '加载失败',
          retry: () => this.remote.loadUsage() })
      }
    }.width('100%').height('100%')
  }
}

@Component
export struct CouponsPage {
  @ObjectLink store: AppStore
  @ObjectLink remote: RemoteDataStore

  aboutToAppear(): void {
    this.remote.loadCoupons()
  }

  build() {
    Column() {
      PageHeader({ store: this.store, title: '优惠券' })
      if (this.remote.couponState.status === AsyncStatus.Loading) {
        LoadingProgress().width(40).height(40).layoutWeight(1)
      } else if (this.remote.couponState.status === AsyncStatus.Empty) {
        StateCopy({ message: '当前账户暂无可用优惠券。' })
      } else if (this.remote.couponState.status === AsyncStatus.Success) {
        List({ space: AppSpacing.x3 }) {
          ForEach(this.remote.couponState.data ?? [], (coupon: CouponView) => {
            ListItem() {
              Column({ space: AppSpacing.x2 }) {
                Text(coupon.title).fontSize(18).fontWeight(FontWeight.Bold)
                Text(coupon.discountLabel).fontColor(AppColors.brand)
                Text(`券码 ${coupon.code} · ${this.couponStatus(coupon)}`)
                  .fontColor(AppColors.textSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              .padding(AppSpacing.x4)
              .backgroundColor(AppColors.surface)
              .borderRadius(AppRadii.card)
            }
          })
        }.padding(AppSpacing.x4).layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      } else {
        RetryState({ message: this.remote.couponState.message ?? '加载失败',
          retry: () => this.remote.loadCoupons() })
      }
    }.width('100%').height('100%')
  }

  private couponStatus(coupon: CouponView): string {
    if (coupon.usedAt !== null) return '已使用'
    if (coupon.expiresAt !== null && Date.parse(coupon.expiresAt) < Date.now()) return '已过期'
    return '可使用'
  }
}

@Component
export struct InvitePage {
  @ObjectLink store: AppStore
  @ObjectLink remote: RemoteDataStore

  aboutToAppear(): void {
    this.remote.loadReferral()
  }

  build() {
    Column() {
      PageHeader({ store: this.store, title: '邀请好友' })
      if (this.remote.referralState.status === AsyncStatus.Loading) {
        LoadingProgress().width(40).height(40).layoutWeight(1)
      } else if (this.remote.referralState.status === AsyncStatus.Success) {
        Column({ space: AppSpacing.x4 }) {
          Text('我的邀请码').fontColor(AppColors.textSecondary)
          Text(this.remote.referralState.data?.code ?? '')
            .fontSize(30).fontWeight(FontWeight.Bold).copyOption(CopyOptions.LocalDevice)
          Text(`已邀请 ${this.remote.referralState.data?.invited ?? 0} 位好友`)
          AppButton({ label: '复制邀请链接', icon: AppIconName.Check,
            onTap: () => this.copyLink() })
        }
        .padding(AppSpacing.x6)
        .justifyContent(FlexAlign.Center)
        .layoutWeight(1)
      } else {
        RetryState({ message: this.remote.referralState.message ?? '加载失败',
          retry: () => this.remote.loadReferral() })
      }
    }.width('100%').height('100%')
  }

  private copyLink(): void {
    const value = this.remote.referralState.data?.shareUrl ?? ''
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value)
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      this.store.showToast('邀请链接已复制')
    })
  }
}

@Component
struct StateCopy {
  @Prop message: string
  build() {
    Text(this.message).fontColor(AppColors.textSecondary).layoutWeight(1)
      .textAlign(TextAlign.Center).padding(AppSpacing.x6)
  }
}

@Component
struct RetryState {
  @Prop message: string
  retry: () => void = () => {}
  build() {
    Column({ space: AppSpacing.x4 }) {
      Text(this.message).fontColor(AppColors.textSecondary)
      AppButton({ label: '重试', icon: AppIconName.Alert, onTap: this.retry })
    }.padding(AppSpacing.x6).justifyContent(FlexAlign.Center).layoutWeight(1)
  }
}

