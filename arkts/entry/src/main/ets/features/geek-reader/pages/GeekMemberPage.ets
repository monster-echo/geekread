import { AppStore } from '../../../state/AppStore'
import { AppColors, AppRadii, AppSpacing } from '../../../theme/AppTokens'
import { AppButton } from '../../../design_system/Components'
import { AppIcon, AppIconName } from '../../../design_system/AppIcon'
import { BillingPlan } from '../../../domain/Models'

function planPriceLabel(plan: BillingPlan): string {
  const amount = (plan.priceMinor / 100).toFixed(0)
  const period = plan.interval === 'monthly' || plan.interval === 'month' ? '月' : '年'
  return `¥${amount}/${period}`
}

@Component
export struct GeekMemberPage {
  @ObjectLink store: AppStore
  @State entitlements: string[] = []
  @State plans: BillingPlan[] = []

  aboutToAppear(): void {
    // 从 config 加载权益 + 方案（@State 供 ForEach 反应性）
    const tiers = this.store.config?.tiers ?? []
    for (let i = 0; i < tiers.length; i++) {
      if (tiers[i].id === 'pro') { this.entitlements = tiers[i].entitlements; break }
    }
    const all = this.store.config?.plans ?? []
    this.plans = all.filter((p: BillingPlan) => p.tierId === 'pro')
  }

  private get isPro(): boolean {
    return this.store.user?.tierId === 'pro'
  }

  build() {
    Scroll() {
    Column({ space: AppSpacing.x4 }) {
      // 当前档位卡片
      Column({ space: AppSpacing.x3 }) {
        Row() {
          AppIcon({ name: AppIconName.Crown, color: AppColors.brand, iconSize: 28 })
          Text(this.isPro ? 'Pro 会员' : '免费版')
            .fontSize(22).fontWeight(FontWeight.Bold).fontColor(AppColors.text).layoutWeight(1)
        }.width('100%')
        Text(this.isPro ? '每日 500 次评论翻译 · 已解锁' : '每日 20 次评论翻译 · 升级解锁 500 次')
          .fontSize(14).fontColor(AppColors.textSecondary)
        if (this.isPro) {
          Text('当前已是 Pro，感谢支持！').fontSize(12).fontColor(AppColors.success)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding(AppSpacing.x6)
      .backgroundColor(AppColors.brandSoft)
      .borderRadius(AppRadii.card)
      .width('100%')

      // 权益
      Column({ space: AppSpacing.x2 }) {
        Text('Pro 权益').fontSize(13).fontColor(AppColors.textSecondary).width('100%')
        Column({ space: AppSpacing.x2 }) {
          ForEach(this.entitlements, (ent: string) => {
            Row({ space: AppSpacing.x3 }) {
              AppIcon({ name: AppIconName.Check, color: AppColors.brand, iconSize: 16 })
              Text(ent).fontSize(15).fontColor(AppColors.text)
            }.width('100%')
          })
        }.padding(AppSpacing.x4).backgroundColor(AppColors.surface).borderRadius(AppRadii.card)
      }.alignItems(HorizontalAlign.Start).width('100%')

      // 订阅方案
      Column({ space: AppSpacing.x2 }) {
        Text('订阅方案').fontSize(13).fontColor(AppColors.textSecondary).width('100%')
        Column({ space: AppSpacing.x2 }) {
          ForEach(this.plans, (plan: BillingPlan) => {
            Column({ space: AppSpacing.x3 }) {
              Row() {
                Column({ space: AppSpacing.x1 }) {
                  Text(plan.name).fontSize(17).fontWeight(FontWeight.Bold).fontColor(AppColors.text)
                  Text(planPriceLabel(plan)).fontSize(15).fontColor(AppColors.brand)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                if (plan.interval === 'yearly') {
                  Text('省 45%').fontSize(12).fontColor(AppColors.onBrand)
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .backgroundColor(AppColors.brand).borderRadius(6)
                }
              }.width('100%')
              AppButton({
                label: this.isPro ? '已订阅' : `订阅 ${plan.name}`,
                onTap: () => this.buy(plan)
              })
            }
            .padding(AppSpacing.x4).backgroundColor(AppColors.surface).borderRadius(AppRadii.card)
          })
        }
      }.alignItems(HorizontalAlign.Start).width('100%')

    }
    .padding(AppSpacing.x4)
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    }.layoutWeight(1)
  }

  private buy(plan: BillingPlan): void {
    this.store.startCheckout(plan.id)
    this.store.navigateByName('membership.checkout')
  }
}
