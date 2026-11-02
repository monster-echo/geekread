import { useEffect, useState } from 'react';
import { ActivityIndicator, Pressable, Text, View } from 'react-native';
import { usePreferences } from '../../../preferences/PreferencesProvider';
import { deriveTargetLanguage } from '../application/locale';
import { translate } from '../application/translationCache';

const LANG_LABEL: Record<string, string> = {
  'zh-Hans': '简体中文', 'zh-Hant': '繁體中文', ja: '日本語', ko: '한국어', en: 'English',
};

export function ImmersiveTranslation({ text, selectable = false }: { text: string; selectable?: boolean }) {
  const { locale, palette } = usePreferences();
  const lang = deriveTargetLanguage(locale);
  const [result, setResult] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [failed, setFailed] = useState(false);
  const [failedMsg, setFailedMsg] = useState('翻译失败');
  const [armed, setArmed] = useState(false);

  useEffect(() => {
    setResult(null); setFailed(false); setFailedMsg('翻译失败'); setArmed(false);
  }, [text]);

  useEffect(() => {
    if (!lang || !armed) return;
    let alive = true;
    setLoading(true);
    translate(text, lang)
      .then((t) => { if (alive) { setResult(t); setLoading(false); } })
      .catch((error: unknown) => {
        if (alive) {
          // 内容合规拦截不是故障：给用户明确提示，不显示通用“翻译失败”
          const blocked = error instanceof Error && error.message === 'blocked';
          setFailedMsg(blocked ? '内容不符合展示规范' : '翻译失败');
          setFailed(true);
          setLoading(false);
        }
      });
    return () => { alive = false; };
  }, [armed, lang, text]);

  if (!lang) return <Text selectable={selectable}>{text}</Text>;

  return (
    <View style={{ marginTop: 2 }}>
      <Text selectable={selectable}>{text}</Text>
      {loading && <ActivityIndicator size="small" style={{ marginTop: 4 }} />}
      {!loading && result && (
        <View style={{ borderLeftWidth: 3, borderLeftColor: palette.brand, paddingLeft: 8, marginTop: 4 }}>
          <Text style={{ color: palette.brand, fontSize: 11 }}>译 · {LANG_LABEL[lang] ?? lang}</Text>
          <Text selectable={selectable}>{result}</Text>
        </View>
      )}
      {!loading && failed && <Text style={{ color: palette.textSecondary, fontSize: 11 }}>{failedMsg}</Text>}
      {!loading && !result && !failed && (
        <Pressable onPress={() => setArmed(true)} style={{ marginTop: 4 }}>
          <Text style={{ color: palette.brand, fontSize: 12 }}>译 · {LANG_LABEL[lang] ?? lang}</Text>
        </Pressable>
      )}
    </View>
  );
}