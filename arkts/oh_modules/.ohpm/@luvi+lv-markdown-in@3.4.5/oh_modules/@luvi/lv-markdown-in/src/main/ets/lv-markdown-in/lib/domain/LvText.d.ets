// @keepTs
// @ts-nocheck
@Observed
declare class LvText {
    private textSize;
    private textColor;
    private textMarkBackground;
    private textLineHeight;
    setTextSize(u119: number | string): void;
    setTextColor(t119: string): void;
    setTextMarkBackground(s119: string): void;
    setTextLineHeight(r119: string): void;
    getTextSize(): number | string;
    getTextColor(): string;
    getTextMarkBackground(): string;
    getTextLineHeight(): string | number;
}
declare const lvText: LvText;
export { lvText, LvText };
