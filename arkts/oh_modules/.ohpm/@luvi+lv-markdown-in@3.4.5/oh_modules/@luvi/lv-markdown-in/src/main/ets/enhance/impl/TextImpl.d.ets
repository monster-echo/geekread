// @keepTs
// @ts-nocheck
import { BaseNode, FootnoteRefNode, LinkNode, TextNode, TreeNode } from '../model/TreeNode';
export declare namespace TextImpl {
    function handleFontColor(s70: string, t70: ESObject, u70?: TreeNode | undefined): ResourceColor;
    function handleBackgroundColor(q70: string, r70: ESObject): ResourceColor;
    function handleBackgroundRadius(n70: string, o70: ESObject): Dimension;
    function handleDecoration(l70: string, m70: ESObject): DecorationStyleInterface;
    function handleText(j70: string, k70: TreeNode | TextNode | FootnoteRefNode | LinkNode): string;
    function handleFontWeight(f70: string, g70: ESObject, h70?: TreeNode | undefined): FontWeight | null;
    function handleFontStyle(b70: string, c70: ESObject, d70?: TreeNode | undefined): FontStyle;
    function handleLineHeight(y69: string, z69?: TreeNode): ResourceStr | number;
    function handleFontSize(s69: string, t69?: BaseNode | undefined, u69?: TreeNode | undefined): number | ResourceStr;
    function handleFontFamily(n69: string, o69?: BaseNode | undefined, p69?: TreeNode | undefined): ResourceStr;
    function handleClick(e69: string, f69: ESObject): void;
    function handleSpanId(a69: string, b69: ESObject): string;
    function handleCopyOption(x68: string): CopyOptions;
}
