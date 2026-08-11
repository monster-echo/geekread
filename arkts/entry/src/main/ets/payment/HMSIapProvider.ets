/**
 * HMS IAP provider — server-authoritative, mirrors the Flutter/RN IapPaymentProvider.
 *
 * Uses HarmonyOS IAP Kit (@kit.IAPKit). The client sends `purchaseToken`
 * → server HMSAdapter calls HMS IAP server verification API → authoritative verify.
 *
 * On HarmonyOS every device has HMS Core, so this is the production provider.
 * Use MockPaymentProvider for dev/testing.
 */
import { iap } from '@kit.IAPKit'
import { PurchaseResult, StoreProduct, StoreProductMapping } from '../domain/Models'
import { PaymentProvider } from './PaymentProvider'

export class HMSIapProvider implements PaymentProvider {
  loadProducts(mapping: StoreProductMapping | null): Promise<StoreProduct[]> {
    if (mapping == null || mapping.hms == null || mapping.hms.length === 0) {
      return Promise.resolve([])
    }
    return iap.queryProducts({ productIds: [mapping.hms] })
      .then((result: iap.ProductInfoResponse) => {
        const products: StoreProduct[] = []
        for (const info of result.productInfo) {
          products.push({ storeProductId: info.productId })
        }
        return products
      })
  }

  purchase(storeProductId: string): Promise<PurchaseResult> {
    return iap.requestPurchase({ productId: storeProductId })
      .then((result: iap.PurchaseResult) => {
        const receipt: Record<string, string | boolean | null> = { purchaseToken: result.purchaseToken }
        return { storeProductId, receipt }
      })
  }

  restore(): Promise<PurchaseResult[]> {
    return iap.getAvailablePurchases()
      .then((owned: iap.OwnedPurchasesResult) => {
        const results: PurchaseResult[] = []
        if (owned.record) {
          for (const item of owned.record) {
            const receipt: Record<string, string | boolean | null> = { purchaseToken: item.purchaseToken }
            results.push({ storeProductId: item.productId, receipt })
          }
        }
        return results
      })
  }
}
