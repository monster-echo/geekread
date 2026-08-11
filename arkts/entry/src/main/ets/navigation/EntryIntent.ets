import { Want } from '@kit.AbilityKit'

export class EntryIntent {
  routeName: string | null
  cold: boolean

  constructor(routeName: string | null, cold: boolean) {
    this.routeName = routeName
    this.cold = cold
  }
}

export interface EntryIntentListener {
  onEntryIntent(intent: EntryIntent): void
  onResume(): void
}

class EntryIntentInbox {
  private listener: EntryIntentListener | null = null
  private pending: EntryIntent | null = null
  private resumePending: boolean = false

  subscribe(listener: EntryIntentListener): void {
    this.listener = listener
    if (this.pending !== null) {
      listener.onEntryIntent(this.pending)
      this.pending = null
    }
    if (this.resumePending) {
      listener.onResume()
      this.resumePending = false
    }
  }

  unsubscribe(listener: EntryIntentListener): void {
    if (this.listener === listener) this.listener = null
  }

  publish(intent: EntryIntent): void {
    if (this.listener !== null) {
      this.listener.onEntryIntent(intent)
      return
    }
    this.pending = intent
  }

  publishResume(): void {
    if (this.listener !== null) {
      this.listener.onResume()
      return
    }
    this.resumePending = true
  }
}

export const entryIntentInbox = new EntryIntentInbox()

export function routeNameFromWant(want: Want): string | null {
  const parameter = want.parameters?.['route']
  if (typeof parameter === 'string' && parameter.length > 0) return parameter
  if (want.uri === undefined || want.uri.length === 0) return null
  const match = /[?&]route=([^&]+)/.exec(want.uri)
  if (match !== null && match.length > 1) return decodeURIComponent(match[1])
  const parts = want.uri.split('/').filter((part: string) => part.length > 0)
  return parts.length > 0 ? parts[parts.length - 1] : null
}
