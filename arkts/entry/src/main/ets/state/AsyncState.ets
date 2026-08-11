export enum AsyncStatus {
  Idle,
  Loading,
  Success,
  Empty,
  Error,
  Offline,
  Unauthorized
}

export class AsyncState<T> {
  readonly status: AsyncStatus
  readonly data?: T
  readonly message?: string

  constructor(status: AsyncStatus, data?: T, message?: string) {
    this.status = status
    this.data = data
    this.message = message
  }
}
