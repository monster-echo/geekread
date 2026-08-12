// @keepTs
// @ts-nocheck
@Observed
declare class LvTitle {
    private level1Title;
    private level2Title;
    private level3Title;
    private level4Title;
    private level5Title;
    private level6Title;
    private levelTitleColor;
    setLevel1Title(b120: number | string): void;
    setLevel2Title(a120: number | string): void;
    setLevel3Title(z119: number | string): void;
    setLevel4Title(y119: number | string): void;
    setLevel5Title(x119: number | string): void;
    setLevel6Title(w119: number | string): void;
    setLevelTitleColor(v119: string): void;
    getLevel1Title(): number | string;
    getLevel2Title(): number | string;
    getLevel3Title(): number | string;
    getLevel4Title(): number | string;
    getLevel5Title(): number | string;
    getLevel6Title(): number | string;
    getLevelTitleColor(): string;
}
declare const lvTitle: LvTitle;
export { lvTitle, LvTitle };
