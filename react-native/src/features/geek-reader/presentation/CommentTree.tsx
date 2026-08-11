import { useState } from 'react';
import { Pressable, Text, View } from 'react-native';
import { usePreferences } from '../../../preferences/PreferencesProvider';
import type { CommentNode } from '../application/comments';
import { ImmersiveTranslation } from './ImmersiveTranslation';

function timeAgo(unix: number): string {
  const d = Math.max(0, Math.floor(Date.now() / 1000 - unix));
  if (d < 60) return `${d}s`;
  if (d < 3600) return `${Math.floor(d / 60)}m`;
  if (d < 86400) return `${Math.floor(d / 3600)}h`;
  return `${Math.floor(d / 86400)}d`;
}

export function CommentTree({ nodes, depth = 0 }: { nodes: CommentNode[]; depth?: number }) {
  return <View>{nodes.map((n) => <CommentRow key={n.id} node={n} depth={depth} />)}</View>;
}

function CommentRow({ node, depth }: { node: CommentNode; depth: number }) {
  const [collapsed, setCollapsed] = useState(false);
  const { palette } = usePreferences();
  if (node.deleted || node.dead) {
    return <Text style={{ paddingLeft: depth * 12, color: palette.textSecondary }}>[已删除]</Text>;
  }
  return (
    <View style={{ paddingLeft: depth * 12, paddingVertical: 6, borderLeftWidth: depth > 0 ? 1 : 0, borderColor: palette.border }}>
      <Pressable onPress={() => setCollapsed((c) => !c)}>
        <Text style={{ fontSize: 12, color: palette.textSecondary }}>
          {node.by} · {timeAgo(node.time)}{node.replies.length ? ` · ${collapsed ? '+' : '−'}${node.replies.length}` : ''}
        </Text>
      </Pressable>
      {!collapsed && (
        <View>
          <ImmersiveTranslation text={node.text} />
          {node.replies.length > 0 && <CommentTree nodes={node.replies} depth={depth + 1} />}
        </View>
      )}
    </View>
  );
}
