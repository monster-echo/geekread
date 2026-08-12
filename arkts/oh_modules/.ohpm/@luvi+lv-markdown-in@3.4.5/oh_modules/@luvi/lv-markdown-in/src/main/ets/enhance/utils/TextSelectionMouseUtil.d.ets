// @keepTs
// @ts-nocheck
export declare function isPrimaryMouseButton(v115: MouseEvent): boolean;
export declare function clearActiveTextSelectionMouseTracker(): void;
export declare class TextSelectionMouseTracker {
    private pressed;
    private selecting;
    private startLocalX;
    private startLocalY;
    private startGlobalX;
    private startGlobalY;
    handleBlockSelectionMouseEvent(p115: string, q115: string, r115: MouseEvent): void;
    reset(): void;
    private hasDragged;
}
