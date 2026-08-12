// @keepTs
// @ts-nocheck
import common2D from "@ohos.graphics.common2D";
import componentUtils from "@ohos.arkui.componentUtils";
export declare class TextSelectionSegment {
    renderedLength: number;
    copyText: string;
    constructor(x89: number, y89: string);
}
export declare class RegisteredTextBlock {
    id: string;
    order: number;
    controller: TextController;
    segments: TextSelectionSegment[];
    renderedLength: number;
    constructor(r89: string, s89: number, t89: TextController, u89: TextSelectionSegment[]);
}
export declare class SelectedTextInfo {
    block: RegisteredTextBlock;
    componentInfo: componentUtils.ComponentInfo;
    rects: common2D.Rect[];
    startIndex: number;
    endIndex: number;
    constructor(m89: RegisteredTextBlock, n89: componentUtils.ComponentInfo, o89: common2D.Rect[], p89: number, q89: number);
    getCaretPosition(h89: componentUtils.ComponentInfo, i89?: boolean): Position | undefined;
}
export declare class BlockHitInfo {
    block: RegisteredTextBlock;
    info: componentUtils.ComponentInfo;
    constructor(f89: RegisteredTextBlock, g89: componentUtils.ComponentInfo);
}
export declare class BlockSelectionStartInfo {
    blockId: string;
    localX: number;
    localY: number;
    showActionBarOnStart: boolean;
    globalX?: number;
    globalY?: number;
    fromBlankArea: boolean;
    constructor(y88: string, z88: number, a89: number, b89?: boolean, c89?: number, d89?: number, e89?: boolean);
}
export declare class CaretInfo {
    blockOrder: number;
    caretIndex: number;
    lessThan(x88: CaretInfo): boolean;
    reset(): void;
}
export declare enum LongPressSelectionType {
    ALL = 0,
    PARAGRAPH = 1,
    CUSTOM = 2
}
/**
 * 长按菜单(复制 / 选取文本)的事件载荷。
 * 由 Markdown 组件在「长按菜单模式」下组装并回调给消费端:
 * - paragraphText: 按压所在文本块(段落)的完整可复制文本, 供「复制」按钮使用。
 * - globalX / globalY: 按压点的窗口坐标(vp), 供消费端把蒙层菜单定位到手指位置。
 * - selectWholeBlock: 组件绑定的「选取文本」动作, 支持全部 / 段落 / 自定义三种选取类型。
 */
export declare class LongPressMenuInfo {
    blockId: string;
    paragraphText: string;
    globalX: number;
    globalY: number;
    selectWholeBlock: (type?: LongPressSelectionType) => void;
    constructor(s88: string, t88: string, u88: number, v88: number, w88: (type?: LongPressSelectionType) => void);
}
export declare class TextSelectionActionContext {
    selectedText: string;
    copy: () => void;
    selectAll: () => void;
    clear: () => void;
    constructor(o88: string, p88: () => void, q88: () => void, r88: () => void);
}
export declare class TextSelectionActionItem {
    title: string;
    fontColor?: ResourceColor;
    onClick: (context: TextSelectionActionContext) => void;
    constructor(l88: string, m88: (context: TextSelectionActionContext) => void, n88?: ResourceColor);
}
