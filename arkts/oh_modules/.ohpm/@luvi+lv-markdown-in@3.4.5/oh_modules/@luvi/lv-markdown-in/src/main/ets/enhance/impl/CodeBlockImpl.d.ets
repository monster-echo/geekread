// @keepTs
// @ts-nocheck
import { CodeTheme } from '../constant/CodeTheme';
import { TreeNode } from '../model/TreeNode';
export declare namespace CodeBlockImpl {
    function handleBackgroundColor(b67: CodeTheme): "#181A1F" | "#F9FAFB";
    function handleThemeChange(z66: string, a67: CodeTheme): void;
    function copyText(x66: string, y66: string): Promise<void>;
    function handleCodeBlockBorderRadius(w66: string): number | ResourceStr;
    function handleCodeHighlight(u66: string, v66: CodeTheme): void;
    function setExtend(r66: TreeNode, ...s66: [
        string,
        ESObject
    ][]): void;
}
