// @keepTs
// @ts-nocheck
import { HighlightNode } from '../model/highlightNode';
@Component
export declare struct CodeSourceRender {
    @Prop
    markdownUnion: string;
    @Prop
    text: string;
    @Prop
    lang: string;
    @Prop
    autoCollapse: boolean;
    @Prop
    selectable: boolean;
    @Prop
    lineNumberWidth: number;
    @Prop
    contentBottomPadding: number;
    @State
    highlightNode: HighlightNode[];
    @State
    MAX_ROWS: number;
    BASE_ROWS: number;
    private highlightVersion;
    private highlightDebounceTimer;
    private codeThemeListener;
    aboutToAppear(): void;
    aboutToDisappear(): void;
    refreshHighlight(): void;
    private shouldAutoCollapse;
    private applyHighlightRows;
    private buildPlainTextRows;
    private visibleRows;
    private visibleRowCount;
    private showMore;
    private isDarkTheme;
    private showLineNumber;
    build(): void;
}
