import { Comment } from '../domain/Models'

export interface CommentNode extends Comment {
  replies: CommentNode[]
}

export interface FlatComment {
  node: CommentNode
  depth: number
}

export function buildCommentTree(flat: Comment[], rootParentId: number): CommentNode[] {
  const byId = new Map<number, CommentNode>()
  for (let i = 0; i < flat.length; i++) {
    const c = flat[i]
    const node: CommentNode = {
      id: c.id, by: c.by, text: c.text, time: c.time,
      parentId: c.parentId, kids: c.kids, replies: [],
    }
    if (c.deleted) node.deleted = c.deleted
    if (c.dead) node.dead = c.dead
    byId.set(c.id, node)
  }
  const roots: CommentNode[] = []
  byId.forEach((node: CommentNode) => {
    const parent = byId.get(node.parentId)
    if (parent !== undefined) {
      parent.replies.push(node)
    } else if (node.parentId === rootParentId) {
      roots.push(node)
    }
  })
  return roots
}

/** 按深度优先展平评论树（折叠的节点不展开子节点），供 ArkUI ForEach 直接渲染。 */
export function flattenTree(
  nodes: CommentNode[],
  depth: number,
  collapsed: Set<number>,
  acc: FlatComment[],
): void {
  for (let i = 0; i < nodes.length; i++) {
    const n = nodes[i]
    acc.push({ node: n, depth })
    if (!collapsed.has(n.id) && n.replies.length > 0) {
      flattenTree(n.replies, depth + 1, collapsed, acc)
    }
  }
}
