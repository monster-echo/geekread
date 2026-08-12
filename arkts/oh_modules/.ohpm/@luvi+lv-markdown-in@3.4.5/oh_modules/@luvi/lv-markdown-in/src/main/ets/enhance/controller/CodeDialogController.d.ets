// @keepTs
// @ts-nocheck
export declare class CodeDialogController {
    private static instance;
    private baseContentNode;
    markdownUnion: string;
    lang: string;
    text: string;
    openBindSheet(i52: string, j52: string, k52: string): Promise<void>;
    closeBindSheet(): Promise<void>;
    static getInstance(): CodeDialogController;
}
