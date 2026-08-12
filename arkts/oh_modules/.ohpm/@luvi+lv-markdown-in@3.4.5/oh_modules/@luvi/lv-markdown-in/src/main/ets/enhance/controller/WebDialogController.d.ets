// @keepTs
// @ts-nocheck
export type WebDialogMode = "url" | "html" | "text";
export declare class WebDialogController {
    private static instance;
    private baseContentNode;
    title: string;
    src: string;
    mode: WebDialogMode;
    javaScriptAccess: boolean;
    /**
     * 打开模态框
     */
    openBindSheet(s60: string, t60: string): Promise<void>;
    openHtmlBindSheet(p60: string, q60: string, r60?: boolean): Promise<void>;
    openTextBindSheet(n60: string, o60: string): Promise<void>;
    private openSheet;
    /**
     * 关闭模态弹窗
     */
    closeBindSheet(): Promise<void>;
    static getInstance(): WebDialogController;
}
