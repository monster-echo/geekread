/**
 * HMS IAP provider — 适配当前 @hms.core.iap SDK（@since 6.1.0(23)）。
 * purchase() → purchaseData(base64) → 解码取 purchaseToken → 后端 HMSAdapter 验证。
 */
import common from '@ohos.app.ability.common'
import util from '@ohos.util'
import { iap } from '@kit.IAPKit'
import { PurchaseResult, StoreProduct, StoreProductMapping } from '../domain/Models'
import { PaymentProvider } from './PaymentProvider'

interface IapPurchaseData {
  purchaseToken?: string
}

const base64 = new util.Base64Helper()

function decodePurchaseToken(purchaseData: string): string {
  try {
    const bytes = base64.decodeSync(purchaseData)
    const json = util.TextDecoder.create().decodeToString(bytes)
    const parsed = JSON.parse(json) as IapPurchaseData
    return parsed.purchaseToken ?? ''
  } catch (e) {
    return ''
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
    const parameter: iap.PurchaseParameter = {
      productId: storeProductId,
      productType: iap.ProductType.AUTORENEWABLE,
    }
    return iap.createPurchase(ctx, parameter).then((result: iap.CreatePurchaseResult) => {
      const token = decodePurchaseToken(result.purchaseData)
      const receipt: Record<string, string | boolean | null> = {}
      receipt['purchaseToken'] = token
      const out: PurchaseResult = { storeProductId, receipt }
      return out
    })
  }

  restore(): Promise<PurchaseResult[]> {
    const ctx = this.context
    if (ctx == null) return Promise.resolve([])
    const parameter: iap.QueryPurchasesParameter = {
      productType: iap.ProductType.AUTORENEWABLE,
    }
    return iap.queryOwnedPurchases(ctx, parameter).then((result: iap.QueryPurchasesResult) => {
      const results: PurchaseResult[] = []
      for (let i = 0; i < result.inAppPurchaseDataList.length; i++) {
        const token = decodePurchaseToken(result.inAppPurchaseDataList[i])
        const receipt: Record<string, string | boolean | null> = {}
        receipt['purchaseToken'] = token
        const item: PurchaseResult = { storeProductId: '', receipt }
        results.push(item)
      }
      return results
    })
  }
}
