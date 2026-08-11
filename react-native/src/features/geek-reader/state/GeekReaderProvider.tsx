import { createContext, useContext, useMemo, useState, type ReactNode } from 'react';
import { AsyncState } from '../../../state/asyncState';
import type { Story } from '../domain/models';

type GeekReaderContextValue = {
  top: AsyncState<Story[]>;
  latest: AsyncState<Story[]>;
  setTop: (s: AsyncState<Story[]>) => void;
  setLatest: (s: AsyncState<Story[]>) => void;
  selectedStoryId: number | null;
  setSelectedStoryId: (id: number | null) => void;
};

const GeekReaderContext = createContext<GeekReaderContextValue | null>(null);

export function GeekReaderProvider({ children }: { children: ReactNode }) {
  const [top, setTop] = useState<AsyncState<Story[]>>({ status: 'idle' });
  const [latest, setLatest] = useState<AsyncState<Story[]>>({ status: 'idle' });
  const [selectedStoryId, setSelectedStoryId] = useState<number | null>(null);
  const value = useMemo<GeekReaderContextValue>(
    () => ({ top, latest, setTop, setLatest, selectedStoryId, setSelectedStoryId }),
    [top, latest, selectedStoryId],
  );
  return <GeekReaderContext.Provider value={value}>{children}</GeekReaderContext.Provider>;
}

export function useGeekReader() {
  const ctx = useContext(GeekReaderContext);
  if (!ctx) throw new Error('useGeekReader 必须在 GeekReaderProvider 内使用');
  return ctx;
}
