// @keepTs
// @ts-nocheck
import common2D from "@ohos.graphics.common2D";
import { InlinePluginLayout } from '../model/MarkdownPlugin';
import { PluginNode, TreeNode } from '../model/TreeNode';
export declare class InlinePluginPlacement {
    node: PluginNode;
    start: number;
    end: number;
    layout: InlinePluginLayout;
    constructor(f108: PluginNode, g108: number, h108: number, i108: InlinePluginLayout);
}
export declare class InlinePluginRect {
    node: PluginNode;
    start: number;
    end: number;
    left: number;
    top: number;
    width: number;
    height: number;
    constructor(d108: InlinePluginPlacement, e108: common2D.Rect);
}
export declare function restoreCachedInlinePluginRects(s107: string, t107: InlinePluginPlacement[]): InlinePluginRect[];
export declare function cacheInlinePluginRects(o107: string, p107: InlinePluginRect[]): void;
export declare function isSameInlinePluginRects(l107: InlinePluginRect[], m107: InlinePluginRect[]): boolean;
export declare function buildParagraphInlinePluginPlacements(d106: string, e106: string, f106: TreeNode | undefined): InlinePluginPlacement[];
export declare function buildTextInlinePluginPlacements(z105: string, a106: string, b106: TreeNode | undefined): InlinePluginPlacement[];
export declare function buildInlinePluginRects(q105: TextController, r105: InlinePluginPlacement[], s105: UIContext): InlinePluginRect[];
