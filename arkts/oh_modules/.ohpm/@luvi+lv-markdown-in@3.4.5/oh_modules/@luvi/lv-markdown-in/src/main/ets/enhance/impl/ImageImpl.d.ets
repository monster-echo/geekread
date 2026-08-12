// @keepTs
// @ts-nocheck
import { ImageNode } from '../model/TreeNode';
export declare namespace ImageImpl {
    function handleImageSrc(u67: string, v67?: string): ResourceStr;
    function handleRawfileImage(q67?: string): Resource | "";
    function handleClick(n67: string, o67: string): void;
    function handleImageWidth(l67: string, m67?: ImageNode): number | ResourceStr | null;
    function handleImageMaxWidth(j67: string, k67?: ImageNode): number | ResourceStr | null;
    function handleImageHeight(h67: string, i67?: ImageNode): number | ResourceStr | null;
    function handleImageMaxHeight(f67: string, g67?: ImageNode): number | ResourceStr | null;
    function handleImageBorderRadius(e67: string): number | ResourceStr;
}
