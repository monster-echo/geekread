import { AppRoute } from '../navigation/AppRoute'
import { AppStore } from '../state/AppStore'
import { AppIcon, AppIconName } from '../design_system/AppIcon'
import { AppButton, AppListRow, PageHeader } from '../design_system/Components'
import { AppColors, AppRadii, AppSpacing } from '../theme/AppTokens'
import { BillingPlan, MembershipTier } from '../domain/Models'
import { appString, AppString } from '../localization/AppStrings'
import { BottomTabs } from './HomePage'

// 方案价格展示：与 RN/Flutter 端保持一致（如 CNY 18.00/月）
export function formatPlanPrice(plan: BillingPlan): string {
  const period = planIntervalLabel(plan.interval)
  const amount = (plan.priceMinor / 100).toFixed(2)
  return `¥${amount}/${period}`
}

function planIntervalLabel(interval: string): string {
  if (interval === 'month' || interval === 'monthly') return '月'
  if (interval === 'year' || interval === 'yearly') return '年'
  if (interval === 'lifetime') return '终身'
  if (interval === 'one_time') return '次'
  return interval
}

@Component
export struct ProfilePage {
  @ObjectLink store: AppStore

  build() {
    Column() {
      PageHeader({ store: this.store,
        title: appString(AppString.ProfileTitle, this.store.language) })
      if (!this.store.signedIn) {
        Column({ space: AppSpacing.x4 }) {
          AppIcon({ name: AppIconName.User, color: AppColors.brand, iconSize: 56 })
          Text(appString(AppString.SignInPrompt, this.store.language))
            .fontSize(22).fontWeight(FontWeight.Bold)
          Text(appString(AppString.SignInDescription, this.store.language))
            .fontColor(AppColors.textSecondary)
          AppButton({
            label: appString(AppString.SignInAction, this.store.language),
            onTap: () => this.store.navigate(AppRoute.SignIn)
          })
        }
        .padding(AppSpacing.x6)
        .justifyContent(FlexAlign.Center)
        .layoutWeight(1)
      } else {
        Scroll() {
          Column({ space: AppSpacing.x4 }) {
            ProfileIdentityCard({ store: this.store })
            Column() {
              AppListRow({
                store: this.store,
                label: appString(AppString.ProfileEdit, this.store.language),
                route: AppRoute.ProfileEdit,
                icon: AppIconName.User
              })
              AppListRow({
                store: this.store,
                label: appString(AppString.Membership, this.store.language),
                route: AppRoute.Membership,
                icon: AppIconName.Crown
              })
              if (this.store.config?.features['statistics'] === true) {
                AppListRow({
                  store: this.store,
                  label: appString(AppString.Statistics, this.store.language),
                  route: AppRoute.Statistics,
                  icon: AppIconName.Home
                })
              }
              if (this.store.config?.features['coupons'] === true) {
                AppListRow({
                  store: this.store,
                  label: '优惠券',
                  route: AppRoute.Coupons,
                  icon: AppIconName.Gift
                })
              }
              if (this.store.config?.features['invites'] === true) {
                AppListRow({
                  store: this.store,
                  label: '邀请好友',
                  route: AppRoute.Invite,
                  icon: AppIconName.Gift
                })
              }
              AppListRow({
                store: this.store,
                label: appString(AppString.Orders, this.store.language),
                route: AppRoute.Orders,
                icon: AppIconName.Gift
              })
              AppListRow({
                store: this.store,
                label: appString(AppString.Settings, this.store.language),
                route: AppRoute.Settings,
                icon: AppIconName.Settings
              })
            }
            .backgroundColor(AppColors.surface)
            .borderRadius(AppRadii.card)
            AppButton({
              label: appString(AppString.SignOut, this.store.language),
              destructive: true,
              onTap: () => this.confirmSignOut()
            })
          }
          .padding(AppSpacing.x4)
          .width('100%')
          .constraintSize({ minHeight: '100%' })
          .justifyContent(FlexAlign.Start)
        }
        .layoutWeight(1)
        .align(Alignment.TopStart)
      }
    }
    .width('100%')
    .height('100%')
  }

  private confirmSignOut(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '退出登录？',
      message: '本机仍会保留非敏感偏好设置。',
      buttons: [
        { text: '取消', color: '#667085' },
        { text: '退出', color: '#D24B4B' }
      ]
    }).then(result => {
      if (result.index === 1) {
        this.store.signOut().then(() => this.store.goHome())
      }
    })
  }
}

@Component
export struct ProfileIdentityCard {
  @ObjectLink store: AppStore

  private identityLine(): string {
    const user = this.store.user
    if (user === null) return ''
    const email = user.email ?? ''
    const username = user.username ?? ''
    // 无真实邮箱（华为/手机号登录）不展示 email，只显示 @用户名
    const isFake = user.hasEmail !== true
    return isFake || email.length === 0 ? `@${username}` : `@${username} · ${email}`
  }

  build() {
    Row({ space: AppSpacing.x4 }) {
      if ((this.store.user?.avatarUrl ?? '').length > 0) {
        Image(this.store.user?.avatarUrl ?? '')
          .width(64).height(64).borderRadius(32)
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          AppIcon({ name: AppIconName.User, color: AppColors.brand, iconSize: 28 })
        }
        .width(64).height(64).borderRadius(32)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(AppColors.brandSoft)
      }
      Column({ space: AppSpacing.x1 }) {
        Text(this.store.user?.displayName ?? '')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppColors.text)
        Text(this.identityLine())
          .fontSize(13).fontColor(AppColors.textSecondary)
        if ((this.store.user?.bio ?? '').length > 0) {
          Text(this.store.user?.bio ?? '').fontSize(13).fontColor(AppColors.textSecondary)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(AppSpacing.x4)
    .backgroundColor(AppColors.surface)
    .borderRadius(AppRadii.card)
  }
}

@Component
export struct MembershipPage {
  @ObjectLink store: AppStore

  build() {
    Column() {
      PageHeader({ store: this.store, title: '会员中心' })
      Scroll() {
        Column({ space: AppSpacing.x4 }) {
          ForEach(this.store.config?.tiers ?? [], (tier: MembershipTier) => {
            Column({ space: AppSpacing.x3 }) {
              Row() {
                Text(tier.name)
                  .fontColor(AppColors.membershipText)
                  .fontWeight(FontWeight.Bold)
                  .fontSize(22)
                  .layoutWeight(1)
                if (this.store.user?.tierId === tier.id) {
                  Text('当前').fontColor(AppColors.membershipText).fontSize(12)
                }
                if (tier.recommended && this.store.user?.tierId !== tier.id) {
                  Text('推荐').fontColor(AppColors.membershipText).fontSize(12)
                }
              }.width('100%')
              if (tier.summary.length > 0) {
                Text(tier.summary).fontColor(AppColors.membershipText)
              }
              ForEach(tier.entitlements, (entitlement: string) => {
                Text(`· ${entitlement}`).fontColor(AppColors.membershipText).fontSize(13)
              })
            }
            .alignItems(HorizontalAlign.Start)
            .padding(AppSpacing.x6)
            .backgroundColor(AppColors.membershipSurface)
            .borderRadius(AppRadii.card)
          })
          if ((this.store.config?.plans ?? []).length > 0) {
            Column({ space: AppSpacing.x3 }) {
              Text('可订阅方案')
                .fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppColors.text)
              ForEach(this.store.config?.plans ?? [], (plan: BillingPlan) => {
                Column({ space: AppSpacing.x2 }) {
                  Row() {
                    Text(plan.name)
                      .fontColor(AppColors.text)
                      .fontWeight(FontWeight.Bold)
                      .fontSize(16)
                      .layoutWeight(1)
                    Text(formatPlanPrice(plan))
                      .fontColor(AppColors.textSecondary)
                      .fontSize(14)
                  }.width('100%')
                  Text(`支付渠道：${plan.provider}`)
                    .fontColor(AppColors.textSecondary)
                    .fontSize(13)
                  AppButton({
                    label: '确认订阅',
                    onTap: () => this.confirmPlan(plan.id)
                  })
                }
                .alignItems(HorizontalAlign.Start)
                .padding(AppSpacing.x4)
                .backgroundColor(AppColors.surface)
                .borderRadius(AppRadii.card)
                .width('100%')
              })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }
          Column() {
            AppListRow({
              store: this.store,
              label: '完整权益与方案对比',
              route: AppRoute.MembershipPlans,
              icon: AppIconName.Crown
            })
            AppListRow({
              store: this.store,
              label: '订阅确认',
              route: AppRoute.Checkout,
              icon: AppIconName.Check
            })
            AppListRow({
              store: this.store,
              label: '订单记录',
              route: AppRoute.Orders,
              icon: AppIconName.Gift
            })
          }
          .backgroundColor(AppColors.surface)
          .borderRadius(AppRadii.card)
        }
        .padding(AppSpacing.x4)
      }
      .layoutWeight(1)
      .align(Alignment.TopStart)
      BottomTabs({ store: this.store, selected: AppRoute.Membership })
    }
    .width('100%')
    .height('100%')
  }

  private confirmPlan(planId: string): void {
    this.store.startCheckout(planId)
    this.store.navigateByName('membership.checkout')
  }
}


