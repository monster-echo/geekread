// @keepTs
// @ts-nocheck
import image from "@ohos.multimedia.image";
export interface LatexInfo {
    pixelMap: image.PixelMap;
    width: number;
    height: number;
}
export declare namespace LatexUtil {
    function latexToPixelMap(u108: string, v108: number, w108: number, x108: UIContext): Promise<LatexInfo>;
    function getCachedLatex(r108: string, s108: number, t108: number): LatexInfo | undefined;
    function clearCache(): void;
}
