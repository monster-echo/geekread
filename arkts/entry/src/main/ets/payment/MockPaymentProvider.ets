import { PurchaseResult, StoreProduct, StoreProductMapping } from '../domain/Models'
import { PaymentProvider } from './PaymentProvider'

export class MockPaymentProvider implements PaymentProvider {
  failPurchases: boolean = false
  private owned: string[] = []

  loadProducts(mapping: StoreProductMapping | null): Promise<StoreProduct[]> {
    const products: StoreProduct[] = []
    if (mapping == null) return Promise.resolve(products)
    if (mapping.apple != null) products.push({ storeProductId: mapping.apple })
    if (mapping.google != null) products.push({ storeProductId: mapping.google })
    if (mapping.hms != null) products.push({ storeProductId: mapping.hms })
    return Promise.resolve(products)
  }

  purchase(storeProductId: string): Promise<PurchaseResult> {
    const receipt: Record<string, string | boolean> = {}
    receipt['productId'] = storeProductId
    if (this.failPurchases) {
      receipt['fail'] = true
    } else {
      this.owned.push(storeProductId)
    }
    const result: PurchaseResult = { storeProductId: storeProductId, receipt: receipt }
    return Promise.resolve(result)
  }

  restore(): Promise<PurchaseResult[]> {
    const results: PurchaseResult[] = []
    for (let i = 0; i < this.owned.length; i++) {
      const receipt: Record<string, string | boolean> = {}
      receipt['productId'] = this.owned[i]
      const result: PurchaseResult = { storeProductId: this.owned[i], receipt: receipt }
      results.push(result)
    }
    return Promise.resolve(results)
  }
}
