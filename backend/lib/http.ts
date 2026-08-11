export function json(body: unknown, status = 200, extraHeaders: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store', ...extraHeaders },
  });
}

export function errorResponse(message: string, status: number, extra: Record<string, unknown> = {}): Response {
  return json({ error: message, ...extra }, status);
}

export function requireString(value: unknown, maximum: number): string {
  if (typeof value !== 'string' || value.trim().length === 0 || value.length > maximum) {
    throw new Error('invalid_request');
  }
  return value.trim();
}

export function requireIds(value: unknown, max = 100): number[] {
  if (!Array.isArray(value) || value.length === 0 || value.length > max) throw new Error('invalid_request');
  const ids = value.map((id) => Number(id));
  if (ids.some((id) => !Number.isSafeInteger(id) || id <= 0)) throw new Error('invalid_request');
  return ids;
}

export function safeErrorStatus(message: string): number {
  return message === 'invalid_request' ? 400
    : message === 'quota_exceeded' ? 429
    : message.startsWith('unsupported_') ? 400
    : 503;
}
