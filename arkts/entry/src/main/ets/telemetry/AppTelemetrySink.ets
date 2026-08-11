import { TelemetryBatch, TelemetrySink } from './Telemetry'
import { apiClient } from '../data/ApiClient'

// Bridges the in-memory telemetry queue to the backend. The ApiClient method
// bypasses the normal 401 refresh / session-expiry path so a failing token can
// never bounce the user to the sign-in guard from a telemetry flush.
export class AppTelemetrySink implements TelemetrySink {
  async send(batch: TelemetryBatch): Promise<boolean> {
    return apiClient.telemetry(batch)
  }
}
