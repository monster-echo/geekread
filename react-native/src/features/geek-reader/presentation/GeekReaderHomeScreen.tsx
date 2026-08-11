import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, FlatList, Pressable, RefreshControl, Text, View } from 'react-native';
import { IconButton } from '../../../design-system/components';
import { usePreferences } from '../../../preferences/PreferencesProvider';
import { useApp } from '../../../state/AppStore';
import { fetchStories, fetchStoriesResolved } from '../data/GeekReaderApiClient';
import type { Story } from '../domain/models';
import { useGeekReader } from '../state/GeekReaderProvider';
import { ImmersiveTranslation } from './ImmersiveTranslation';

const PAGE = 20;

export function GeekReaderHomeScreen() {
  const { navigate } = useApp();
  const { palette } = usePreferences();
  return (
    <View style={{ flex: 1, backgroundColor: palette.background }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', padding: 8, gap: 4 }}>
        <IconButton label="返回" icon="arrow-left" onPress={() => navigate('home')} />
        <Text style={{ fontSize: 20, fontWeight: 'bold', color: palette.text }}>极客译读</Text>
      </View>
      <HomeInner onOpenStory={() => navigate('geekreader.story')} />
    </View>
  );
}

function HomeInner({ onOpenStory }: { onOpenStory: () => void }) {
  const { top, latest, setTop, setLatest, setSelectedStoryId } = useGeekReader();
  const { palette } = usePreferences();
  const [tab, setTab] = useState<'top' | 'latest'>('top');
  const [refreshing, setRefreshing] = useState(false);
  const state = tab === 'top' ? top : latest;
  const setState = tab === 'top' ? setTop : setLatest;

  const load = useCallback(async () => {
    setState({ status: 'loading' });
    try {
      const ids = await fetchStories(tab);
      const slice = ids.ids.slice(0, PAGE);
      const stories = await fetchStoriesResolved(slice);
      setState({ status: stories.length ? 'success' : 'empty', data: stories });
    } catch {
      setState({ status: 'error', message: '加载失败，请检查网络或后端地址。' });
    }
  }, [tab, setState]);

  useEffect(() => { void load(); }, [load]);

  const open = (id: number) => { setSelectedStoryId(id); onOpenStory(); };

  return (
    <View style={{ flex: 1 }}>
      <View style={{ flexDirection: 'row' }}>
        {(['top', 'latest'] as const).map((t) => (
          <Pressable key={t} onPress={() => setTab(t)} style={{ paddingVertical: 12, paddingHorizontal: 16 }}>
            <Text style={{ fontWeight: tab === t ? 'bold' : 'normal', color: tab === t ? palette.brand : palette.text }}>
              {t === 'top' ? '精选' : '最新'}
            </Text>
          </Pressable>
        ))}
      </View>
      {state.status === 'loading' && <ActivityIndicator style={{ padding: 16 }} />}
      {state.status === 'error' && <Text style={{ padding: 16, color: palette.textSecondary }}>{state.message}</Text>}
      {state.status === 'empty' && <Text style={{ padding: 16, color: palette.textSecondary }}>暂无内容。</Text>}
      {state.status === 'success' && (
        <FlatList
          data={state.data}
          keyExtractor={(item: Story) => String(item.id)}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={async () => { setRefreshing(true); await load(); setRefreshing(false); }} />}
          renderItem={({ item }) => (
            <Pressable onPress={() => open(item.id)} style={{ padding: 12, borderBottomWidth: 1, borderColor: palette.border }}>
              <ImmersiveTranslation text={item.title} />
              <Text style={{ color: palette.textSecondary, fontSize: 12, marginTop: 4 }}>{item.score} 分 · {item.by} · {item.commentsCount} 评论</Text>
            </Pressable>
          )}
        />
      )}
    </View>
  );
}
