import { describe, expect, it } from 'vitest';
import { toStory, toComment, type HNItem } from '../domain/models';

const storyItem: HNItem = { id: 1, type: 'story', title: 'T', by: 'pg', time: 0, score: 10, descendants: 3, url: 'https://x', kids: [2, 3] };
const commentItem: HNItem = { id: 2, type: 'comment', by: 'u', time: 0, text: 'hi', kids: [4], parent: 1 };

describe('models', () => {
  it('maps HN story item', () => {
    const s = toStory(storyItem);
    expect(s).toMatchObject({ id: 1, title: 'T', by: 'pg', url: 'https://x', score: 10, commentsCount: 3 });
    expect(s?.kids).toEqual([2, 3]);
  });

  it('maps self-post story (text, no url)', () => {
    const s = toStory({ id: 5, type: 'story', title: 'Ask', text: 'body' });
    expect(s?.url).toBeUndefined();
    expect(s?.text).toBe('body');
  });

  it('maps comment', () => {
    const c = toComment(commentItem);
    expect(c).toMatchObject({ id: 2, by: 'u', text: 'hi', parentId: 1 });
    expect(c?.kids).toEqual([4]);
  });

  it('returns null for missing item', () => {
    expect(toStory(null)).toBeNull();
    expect(toComment(null)).toBeNull();
  });
});
