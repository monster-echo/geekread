// @keepTs
// @ts-nocheck
@ObservedV2
export declare class ImageDialogController {
    private static instance;
    private baseContentNode;
    src: string;
    markdownUnion: string;
    pageOpacity: number;
    imageViewShowState: boolean;
    bgc: string;
    /**
     * 打开模态框
     */
    openBindSheet(p52: string, q52: string): Promise<void>;
    /**
     * 关闭模态弹窗
     */
    closeBindSheet(): Promise<void>;
    static getInstance(): ImageDialogController;
}
