// @keepTs
// @ts-nocheck
@Observed
declare class LvImage {
    private imgWidth;
    private imgHeight;
    private confGlobal;
    private imgUrl;
    setImgWidth(k119: string): void;
    setImgHeight(j119: string): void;
    setConfGlobal(i119: boolean): void;
    setImgUrl(h119: string): void;
    getImgWidth(): number | string;
    getImgHeight(): number | string | null;
    getConfGlobal(): boolean;
    getImgUrl(): string;
}
declare const lvImage: LvImage;
export { lvImage, LvImage };
