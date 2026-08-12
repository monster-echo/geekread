// @keepTs
// @ts-nocheck
import { CodeHighlight } from '../model/CodeHighlight';
import { HighlightNode } from '../model/highlightNode';
export declare namespace PrismHighlightUtil {
    function highlight(t112: string, u112: CodeHighlight, v112?: string, w112?: boolean): Promise<HighlightNode[]>;
    function getCached(n112: string, o112: CodeHighlight, p112?: string, q112?: boolean): HighlightNode[] | undefined;
}
