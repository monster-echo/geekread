import { useEffect, useState } from 'react';
import { ActivityIndicator, Linking, Pressable, ScrollView, Text, View } from 'react-native';
import { IconButton } from '../../../design-system/components';
import { usePreferences } from '../../../preferences/PreferencesProvider';
import { useApp } from '../../../state/AppStore';
import { fetchItems } from '../data/GeekReaderApiClient';
import { toStory, toComment, type Story, type Comment } from '../domain/models';
import { buildCommentTree } from '../application/comments';
import { useGeekReader } from '../state/GeekReaderProvider';
import { ImmersiveTranslation } from './ImmersiveTranslation';
import { CommentTree } from './CommentTree';

export function StoryDetailScreen() {
  const { navigate } = useApp();
  const { selectedStoryId } = useGeekReader();
  const { palette } = usePreferences();
  const [story, setStory] = useState<Story | null>(null);
  const [comments, setComments] = useState<Comment[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    const id = selectedStoryId;
    if (id == null) { setLoading(false); return; }
    (async () => {
      setLoading(true);
      try {
        const top = await fetchItems([id]);
        const s = toStory(top.items[0] ?? null);
        // BFS 抓评论树（上限 200 条，防止超长帖爆网络）。
        const all: Comment[] = [];
        const seen = new Set<number>();
        let frontier = s?.kids ?? [];
        while (frontier.length && all.length < 200) {
          const res = await fetchItems(frontier);
          const next: number[] = [];
          for (const it of res.items) {
            const cm = toComment(it);
            if (!cm || seen.has(cm.id)) continue;
            seen.add(cm.id);
            all.push(cm);
            next.push(...cm.kids);
          }
          frontier = next;
        }
        if (!alive) return;
        setStory(s);
        setComments(all);
      } finally {
        if (alive) setLoading(false);
      }
    })();
    return () => { alive = false; };
  }, [selectedStoryId]);

  if (loading) {
    return (
      <View style={{ flex: 1 }}>
        <Header onBack={() => navigate('geekreader.home')} />
        <ActivityIndicator style={{ flex: 1 }} />
      </View>
    );
  }
  if (!story) {
    return (
      <View style={{ flex: 1 }}>
        <Header onBack={() => navigate('geekreader.home')} />
        <Text style={{ padding: 16, color: palette.textSecondary }}>未找到文章。</Text>
      </View>
    );
  }

  return (
    <View style={{ flex: 1 }}>
      <Header title={story.title} onBack={() => navigate('geekreader.home')} />
      <ScrollView>
        <View style={{ padding: 12 }}>
          <ImmersiveTranslation text={story.title} />
          {story.url ? (
            <Pressable onPress={() => Linking.openURL(story.url!)} style={{ marginTop: 8 }}>
              <Text style={{ color: palette.brand }}>阅读原文 ↗</Text>
            </Pressable>
          ) : story.text ? (
            <View style={{ marginTop: 8 }}><ImmersiveTranslation text={story.text} /></View>
          ) : null}
          <Text style={{ color: palette.textSecondary, marginTop: 8, fontSize: 12 }}>
            {story.score} 分 · {story.by} · {story.commentsCount} 评论
          </Text>
        </View>
        <CommentTree nodes={buildCommentTree(comments, story.id)} />
      </ScrollView>
    </View>
  );
}

function Header({ title, onBack }: { title?: string; onBack: () => void }) {
  const { palette } = usePreferences();
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', padding: 8, gap: 4 }}>
      <IconButton label="返回" icon="arrow-left" onPress={onBack} />
      <Text numberOfLines={1} style={{ flex: 1, color: palette.text, fontSize: 16, fontWeight: '600' }}>{title ?? ''}</Text>
    </View>
  );
}
