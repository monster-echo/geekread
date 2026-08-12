// @keepTs
// @ts-nocheck
@Observed
declare class LvLink {
    private textSize;
    private textColor;
    private textUnderline;
    private linkUrl;
    setTextSize(o119: number | string): void;
    setTextColor(n119: string): void;
    setTextUnderline(m119: boolean): void;
    setLinkUrl(l119: string): void;
    getTextSize(): number | string;
    getTextColor(): string;
    getTextUnderline(): boolean;
    getLinkUrl(): string;
}
declare const lvLink: LvLink;
export { lvLink, LvLink };
