import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

describe('POST /api/reader/report', () => {
  beforeEach(() => {
    vi.resetModules();
    delete process.env.REDIS_URL;
  });
  afterEach(() => vi.restoreAllMocks());

  it('accepts a valid report', async () => {
    const { POST } = await import('../../app/api/reader/report/route.js');
    const res = await POST(new Request('http://x/api/reader/report', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-install-id': 'c1' },
      body: JSON.stringify({ storyId: 1, commentId: 2, reason: 'spam', text: 'bad' }),
    }));
    const body = await res.json();
    expect(res.status).toBe(200);
    expect(body.ok).toBe(true);
  });

  it('400 when reason missing or invalid', async () => {
    const { POST } = await import('../../app/api/reader/report/route.js');
    const res = await POST(new Request('http://x/api/reader/report', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-install-id': 'c1' },
      body: JSON.stringify({ storyId: 1, commentId: 2 }),
    }));
    expect(res.status).toBe(400);
  });
});
