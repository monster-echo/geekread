export type TelemetryValue = string | number | boolean

export type TelemetryProperties = Map<string, TelemetryValue>

export interface TelemetryEvent {
  eventId: string
  name: string
  screenId: string
  occurredAt: string
  configVersion: number
  properties: TelemetryProperties
}

export interface TelemetryBatch {
  anonymousId: string
  sessionId: string
  events: TelemetryEvent[]
}

export interface TelemetrySink {
  send(batch: TelemetryBatch): Promise<boolean>
}

export class TelemetryConfig {
  enabled: boolean = true
  backendEnabled: boolean = true
  configVersion: number = 0
}

class Telemetry {
  private readonly maxQueue: number = 200
  private readonly batchSize: number = 25
  private readonly sessionId: string = this.createId('session')
  private readonly anonymousId: string = this.createId('anonymous')
  private config: TelemetryConfig = new TelemetryConfig()
  private queue: TelemetryEvent[] = []
  private sink: TelemetrySink | null = null
  private currentScreen: string = ''
  private screenStartedAt: number = Date.now()
  private flushing: boolean = false
  private flushScheduled: boolean = false
  private retryIndex: number = 0

  configure(config: TelemetryConfig, sink: TelemetrySink | null): void {
    this.config = config
    this.sink = sink
    this.scheduleFlush(0)
  }

  screen(screenId: string): void {
    if (this.currentScreen === screenId) {
      return
    }
    if (this.currentScreen.length > 0) {
      const leaveProperties = new Map<string, TelemetryValue>()
      leaveProperties.set('screen_id', this.currentScreen)
      leaveProperties.set('duration_ms', Date.now() - this.screenStartedAt)
      this.track('screen_leave', leaveProperties, this.currentScreen)
    }
    this.currentScreen = screenId
    this.screenStartedAt = Date.now()
    const properties = new Map<string, TelemetryValue>()
    properties.set('screen_id', screenId)
    this.track('screen_view', properties, screenId)
  }

  track(
    name: string,
    properties: TelemetryProperties = new Map<string, TelemetryValue>(),
    screenId: string = this.currentScreen
  ): void {
    if (!this.config.enabled || !this.config.backendEnabled) {
      return
    }
    if (this.queue.length >= this.maxQueue) {
      this.queue.shift()
    }
    this.queue.push({
      eventId: this.createId('evt'),
      name: name,
      screenId: screenId,
      occurredAt: new Date().toISOString(),
      configVersion: this.config.configVersion,
      properties: properties
    })
    this.scheduleFlush(2000)
  }

  report(error: Error, context: TelemetryProperties = new Map<string, TelemetryValue>()): void {
    const properties = new Map<string, TelemetryValue>(context)
    properties.set('error_name', error.name)
    properties.set('error_message', error.message.substring(0, 180))
    this.track('app_error', properties)
  }

  /** 记录用户点击（按钮/入口），便于追踪操作路径。 */
  click(button: string, screenId: string = this.currentScreen): void {
    const properties = new Map<string, TelemetryValue>()
    properties.set('button', button)
    this.track('click', properties, screenId)
  }

  private scheduleFlush(delayMs: number): void {
    if (this.flushing || this.flushScheduled || this.queue.length === 0) {
      return
    }
    this.flushScheduled = true
    setTimeout(() => {
      this.flushScheduled = false
      this.flush()
    }, delayMs)
  }

  private async flush(): Promise<void> {
    if (this.flushing || this.queue.length === 0 || this.sink === null) {
      return
    }
    this.flushing = true
    const events = this.queue.slice(0, this.batchSize)
    try {
      const accepted = await this.withTimeout(this.sink.send({
        anonymousId: this.anonymousId,
        sessionId: this.sessionId,
        events: events
      }), 5000)
      if (!accepted) {
        throw new Error('Telemetry rejected')
      }
      this.queue = this.queue.slice(events.length)
      this.retryIndex = 0
    } catch (_) {
      this.retryIndex = Math.min(this.retryIndex + 1, 4)
    } finally {
      this.flushing = false
      if (this.queue.length > 0) {
        const delays: number[] = [2000, 5000, 15000, 30000, 60000]
        this.scheduleFlush(delays[this.retryIndex])
      }
    }
  }

  private withTimeout(operation: Promise<boolean>, delayMs: number): Promise<boolean> {
    return Promise.race([
      operation,
      new Promise<boolean>((_, reject) => {
        setTimeout(() => reject(new Error('Telemetry timeout')), delayMs)
      })
    ])
  }

  private createId(prefix: string): string {
    return `${prefix}-${Date.now()}-${Math.floor(Math.random() * 1000000000)}`
  }
}

export const telemetry: Telemetry = new Telemetry()
