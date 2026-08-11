import { AppStore } from '../state/AppStore'
import { BillingPlan, PurchaseStatus } from '../domain/Models'
import { AppButton, PageHeader } from '../design_system/Components'
import { AppColors, AppRadii, AppSpacing } from '../theme/AppTokens'
import { formatPlanPrice } from './ProfilePages'

// 订阅确认页：展示待确认方案（来自 store.pendingPlanId），驱动一次支付。
// 状态机（store.purchaseStatus）：
//  Loading  → 正在确认…（无操作，防重复提交）
//  Success  → 完成 → 返回会员中心
//  Failed   → 重试 → 重新发起支付
//  其他     → 确认订阅 → 发起支付
@Component
export struct CheckoutPage {
  @ObjectLink store: AppStore

  build() {
    Column() {
      PageHeader({ store: this.store, title: '订阅确认' })
      Scroll() {
        Column({ space: AppSpacing.x4 }) {
          if (this.plan !== null) {
            Column({ space: AppSpacing.x3 }) {
              Text(this.plan.name)
                .fontSize(22).fontWeight(FontWeight.Bold).fontColor(AppColors.text)
              Text(formatPlanPrice(this.plan))
                .fontSize(16).fontColor(AppColors.brand)
              Text(`支付渠道：${this.plan.provider}`)
                .fontSize(13).fontColor(AppColors.textSecondary)
              if (this.plan.provider === 'mock') {
                Text('当前为演示支付，不会调用真实商店或支付渠道。')
                  .fontSize(13).fontColor(AppColors.warning)
              }
            }
            .alignItems(HorizontalAlign.Start)
            .padding(AppSpacing.x6)
            .backgroundColor(AppColors.surface)
            .borderRadius(AppRadii.card)
            .width('100%')
          } else {
            Column({ space: AppSpacing.x4 }) {
              Text('未选择订阅方案').fontSize(16).fontColor(AppColors.textSecondary)
              AppButton({
                label: '返回会员中心',
                onTap: () => this.store.navigateByName('membership.home')
              })
            }
            .alignItems(HorizontalAlign.Start)
            .padding(AppSpacing.x4)
            .backgroundColor(AppColors.surface)
            .borderRadius(AppRadii.card)
            .width('100%')
          }
          if (this.store.purchaseStatus === PurchaseStatus.Loading) {
            Row({ space: AppSpacing.x2 }) {
              LoadingProgress().width(20).height(20).color(AppColors.onBrand)
              Text('正在确认…').fontColor(AppColors.onBrand).fontWeight(FontWeight.Bold)
            }
            .justifyContent(FlexAlign.Center)
            .width('100%')
            .height(52)
          } else if (this.store.purchaseStatus === PurchaseStatus.Success) {
            AppButton({
              label: '完成',
              onTap: () => this.store.navigateByName('membership.home')
            })
          } else if (this.store.purchaseStatus === PurchaseStatus.Failed) {
            AppButton({
              label: '重试',
              onTap: () => { this.store.purchase(this.planId) }
            })
          } else {
            AppButton({
              label: '确认订阅',
              onTap: () => { this.store.purchase(this.planId) }
            })
          }
        }
        .padding(AppSpacing.x4)
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  private get planId(): string {
    return this.store.pendingPlanId
  }

  private get plan(): BillingPlan | null {
    const plans = this.store.config?.plans ?? []
    for (const plan of plans) {
      if (plan.id === this.planId) return plan
    }
    return null
  }
}
