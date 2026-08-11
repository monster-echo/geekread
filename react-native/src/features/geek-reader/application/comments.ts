import type { Comment } from '../domain/models';

export type CommentNode = Comment & { replies: CommentNode[] };

export function buildCommentTree(flat: Comment[], rootParentId: number): CommentNode[] {
  const byId = new Map<number, CommentNode>();
  for (const c of flat) byId.set(c.id, { ...c, replies: [] });
  const roots: CommentNode[] = [];
  for (const node of byId.values()) {
    const parent = byId.get(node.parentId);
    if (parent) parent.replies.push(node);
    else if (node.parentId === rootParentId) roots.push(node);
  }
  return roots;
}
