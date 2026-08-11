import { PurchaseResult, StoreProduct, StoreProductMapping } from '../domain/Models'

export interface PaymentProvider {
  loadProducts(mapping: StoreProductMapping | null): Promise<StoreProduct[]>
  purchase(storeProductId: string): Promise<PurchaseResult>
  restore(): Promise<PurchaseResult[]>
}
