import { beforeEach, describe, expect, it } from 'vitest';

describe('entitlement', () => {
  beforeEach(() => { process.env.ENTITLEMENT_SIGNING_SECRET = 'secret'; });

  it('signs and verifies a pro token', async () => {
    const { signEntitlement, hasProEntitlement } = await import('../lib/entitlement.js');
    const token = signEntitlement({ exp: Math.floor(Date.now() / 1000) + 3600 });
    expect(hasProEntitlement(token)).toBe(true);
  });

  it('rejects expired token', async () => {
    const { signEntitlement, hasProEntitlement } = await import('../lib/entitlement.js');
    const token = signEntitlement({ exp: Math.floor(Date.now() / 1000) - 10 });
    expect(hasProEntitlement(token)).toBe(false);
  });

  it('rejects tampered signature', async () => {
    const { signEntitlement, hasProEntitlement } = await import('../lib/entitlement.js');
    const token = signEntitlement({ exp: Math.floor(Date.now() / 1000) + 3600 });
    expect(hasProEntitlement(token + 'x')).toBe(false);
  });

  it('returns false when no secret configured', async () => {
    delete process.env.ENTITLEMENT_SIGNING_SECRET;
    const { hasProEntitlement } = await import('../lib/entitlement.js');
    expect(hasProEntitlement('anything')).toBe(false);
  });
});
