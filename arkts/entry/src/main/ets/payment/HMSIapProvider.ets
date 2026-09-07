/**
 * HMS IAP provider — 适配当前 @hms.core.iap SDK（@since 6.1.0(23)）。
 * purchase() → purchaseData(base64) → 解码 purchaseToken + purchaseOrderId → 后端验证。
 * purchaseOrderId 是服务端「订单状态查询」API（HarmonyOS NEXT）的必选参数，必须随收据上送。
 */
import common from '@ohos.app.ability.common'
import util from '@ohos.util'
import { iap } from '@kit.IAPKit'
import { PurchaseResult, StoreProduct, StoreProductMapping } from '../domain/Models'
import { PaymentProvider } from './PaymentProvider'
import { telemetry } from '../telemetry/Telemetry'

interface IapPurchaseData {
  purchaseToken?: string
  purchaseOrderId?: string
}

interface IapReceipt {
  purchaseToken: string
  purchaseOrderId: string
}

const base64 = new util.Base64Helper()

function decodePurchase(purchaseData: string): IapReceipt {
  try {
    const bytes = base64.decodeSync(purchaseData)
    const json = util.TextDecoder.create().decodeToString(bytes)
    const parsed = JSON.parse(json) as IapPurchaseData
    return { purchaseToken: parsed.purchaseToken ?? '', purchaseOrderId: parsed.purchaseOrderId ?? '' }
  } catch (e) {
    return { purchaseToken: '', purchaseOrderId: '' }
  }
}

export class HMSIapProvider implements PaymentProvider {
  private context: common.UIAbilityContext | null = null

  setContext(context: common.UIAbilityContext): void {
    this.context = context
  }

  loadProducts(mapping: StoreProductMapping | null): Promise<StoreProduct[]> {
    // 商品列表查询非购买必需；购买直接按 storeProductId（配置里的 hms 商品 ID）。
    return Promise.resolve([])
  }

  purchase(storeProductId: string): Promise<PurchaseResult> {
    const ctx = this.context
    if (ctx == null) return Promise.reject(new Error('IAP context not set'))
    // 模拟器/无 HMS IAP 运行时：@kit.IAPKit 解析为空命名空间，直接调用会抛
    // "queryEnvironmentStatus of undefined"。用系统能力探测提前拦截，给友好提示而非 TypeError。
    if (!canIUse('SystemCapability.Payment.IAP')) {
      return Promise.reject(new Error('当前设备不支持华为应用内支付（模拟器或无 HMS IAP 运行时），请使用真机测试'))
    }
    // 先检查 IAP 环境（AGC 未配商品时 queryEnvironmentStatus 抛错 → 返回错误，避免 createPurchase native 崩溃）
    return iap.queryEnvironmentStatus(ctx)
      .then(() => this.doPurchase(ctx, storeProductId))
      .catch((e: Error) => {
        telemetry.report(new Error(`iap_purchase_failed: ${e.message}`))
        throw new Error(`IAP unavailable: ${e.message}`)
      })
  }

  private doPurchase(ctx: common.UIAbilityContext, storeProductId: string): Promise<PurchaseResult> {
    const parameter: iap.PurchaseParameter = {
      productId: storeProductId,
      productType: iap.ProductType.AUTORENEWABLE,
    }
    return iap.createPurchase(ctx, parameter).then((result: iap.CreatePurchaseResult) => {
      const r = decodePurchase(result.purchaseData)
      const receipt: Record<string, string | boolean | null> = {}
      receipt['purchaseToken'] = r.purchaseToken
      receipt['purchaseOrderId'] = r.purchaseOrderId
      const out: PurchaseResult = { storeProductId, receipt }
      return out
    })
  }

  restore(): Promise<PurchaseResult[]> {
    const ctx = this.context
    if (ctx == null) return Promise.resolve([])
    // 无 IAP 能力的环境（模拟器等）直接返回空，避免对未解析的 kit 调用。
    if (!canIUse('SystemCapability.Payment.IAP')) return Promise.resolve([])
    const parameter: iap.QueryPurchasesParameter = {
      productType: iap.ProductType.AUTORENEWABLE,
    }
    return iap.queryOwnedPurchases(ctx, parameter).then((result: iap.QueryPurchasesResult) => {
      const results: PurchaseResult[] = []
      for (let i = 0; i < result.inAppPurchaseDataList.length; i++) {
        const r = decodePurchase(result.inAppPurchaseDataList[i])
        const receipt: Record<string, string | boolean | null> = {}
        receipt['purchaseToken'] = r.purchaseToken
        receipt['purchaseOrderId'] = r.purchaseOrderId
        const item: PurchaseResult = { storeProductId: '', receipt }
        results.push(item)
      }
      return results
    })
  }
}
