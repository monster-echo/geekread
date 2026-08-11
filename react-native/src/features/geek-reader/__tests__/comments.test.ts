import { describe, expect, it } from 'vitest';
import { buildCommentTree } from '../application/comments';
import type { Comment } from '../domain/models';

const c = (id: number, parent: number, kids: number[] = []): Comment =>
  ({ id, by: 'u', text: `t${id}`, time: 0, parentId: parent, kids });

describe('buildCommentTree', () => {
  it('nests replies under parents by id', () => {
    // rootParentId=1 是虚拟根（story），不在 flat 里；parent==1 的是顶层评论。
    const flat: Comment[] = [c(2, 1), c(3, 1, [4]), c(4, 3)];
    const tree = buildCommentTree(flat, 1);
    expect(tree.map((n) => n.id)).toEqual([2, 3]);
    expect(tree[1].replies.map((r) => r.id)).toEqual([4]);
  });

  it('returns empty for unknown root', () => {
    expect(buildCommentTree([c(9, 0)], 1)).toEqual([]);
  });
});
