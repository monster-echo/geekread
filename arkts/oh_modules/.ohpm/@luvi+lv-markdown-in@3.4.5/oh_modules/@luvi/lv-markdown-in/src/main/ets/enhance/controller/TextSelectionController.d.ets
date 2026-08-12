// @keepTs
// @ts-nocheck
import componentUtils from "@ohos.arkui.componentUtils";
import { BlockHitInfo, BlockSelectionStartInfo, RegisteredTextBlock, TextSelectionSegment } from '../model/TextSelectionInfo';
export declare class TextSelectionController {
    private static controllerMap;
    private static activeMarkdownUnion?;
    private markdownUnion;
    private blocks;
    private orderedBlocksCache;
    private blockRectCache;
    private layoutCacheValid;
    private nextOrder;
    private readonly HIT_SLOP;
    private startSelectionHandler?;
    private updateSelectionHandler?;
    private endSelectionHandler?;
    private clearSelectionHandler?;
    private constructor();
    static getInstance(h60: string): TextSelectionController;
    static destroy(g60: string): void;
    registerBlock(z59: string, a60: TextController, b60: TextSelectionSegment[]): void;
    unregisterBlock(y59: string): void;
    clear(): void;
    setStartSelectionHandler(x59?: (info: BlockSelectionStartInfo) => void): void;
    setUpdateSelectionHandler(w59?: (globalX: number, globalY: number) => void): void;
    setEndSelectionHandler(v59?: () => void): void;
    setClearSelectionHandler(u59?: () => void): void;
    releaseActiveSelection(): void;
    triggerStartSelection(s59: BlockSelectionStartInfo): void;
    triggerUpdateSelection(q59: number, r59: number): boolean;
    triggerEndSelection(): boolean;
    getOrderedBlocks(): RegisteredTextBlock[];
    private refreshLayoutSnapshot;
    getBlockByOrder(g59: number): RegisteredTextBlock | undefined;
    getBlockById(f59: string): RegisteredTextBlock | undefined;
    getExactBlockInfoByPoint(v58: number, w58: number): BlockHitInfo | undefined;
    getNearestBlockInfoByPoint(g58: number, h58: number): BlockHitInfo | undefined;
    getBlockInfoByPoint(v57: number, w57: number): BlockHitInfo | undefined;
    getBlockRect(s57: string, t57?: boolean): componentUtils.ComponentInfo | undefined;
    invalidateLayoutCache(): void;
    private loadBlockRect;
    buildCopyText(b57: number, c57: number, d57: number, e57: number): string;
    private extractBlockCopyText;
}
