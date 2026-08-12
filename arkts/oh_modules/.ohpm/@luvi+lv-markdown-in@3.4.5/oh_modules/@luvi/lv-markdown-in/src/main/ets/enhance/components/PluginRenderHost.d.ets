// @keepTs
// @ts-nocheck
import { InlinePluginLayout } from '../model/MarkdownPlugin';
import { PluginNode } from '../model/TreeNode';
@Component
export declare struct PluginBlockRenderHost {
    @Prop
    node: PluginNode;
    renderer: WrappedBuilder<[
        PluginNode
    ]> | undefined;
    build(): void;
}
@Component
export declare struct PluginInlineRenderHost {
    @Prop
    node: PluginNode;
    renderer: WrappedBuilder<[
        PluginNode
    ]> | undefined;
    build(): void;
}
export declare function getPluginRenderer(k39: string, l39: PluginNode): WrappedBuilder<[
    PluginNode
]> | undefined;
export declare function getPluginInlineLayout(h39: string, i39: PluginNode): InlinePluginLayout | undefined;
export declare function hasPluginInlineOverlay(f39: string, g39: PluginNode): boolean;
export declare function getPluginInlinePlaceholderWidth(d39: string, e39: PluginNode): number;
export declare function getPluginInlinePlaceholderHeight(b39: string, c39: PluginNode): number;
@Builder
export declare function PluginInlinePlaceholderSpan(s38: string, t38: PluginNode): void;
