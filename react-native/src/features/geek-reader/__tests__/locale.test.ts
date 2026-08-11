import { describe, expect, it } from 'vitest';
import { deriveTargetLanguage } from '../application/locale';

describe('deriveTargetLanguage', () => {
  it.each([
    ['zh-CN', 'zh-Hans'], ['zh-Hans-CN', 'zh-Hans'], ['zh', 'zh-Hans'],
    ['zh-TW', 'zh-Hant'], ['zh-Hant', 'zh-Hant'], ['zh-HK', 'zh-Hant'],
    ['ja-JP', 'ja'], ['ko-KR', 'ko'],
    ['en-US', null], ['en', null], ['fr-FR', null],
  ])('%s → %s', (input, expected) => {
    expect(deriveTargetLanguage(input)).toBe(expected);
  });
});
