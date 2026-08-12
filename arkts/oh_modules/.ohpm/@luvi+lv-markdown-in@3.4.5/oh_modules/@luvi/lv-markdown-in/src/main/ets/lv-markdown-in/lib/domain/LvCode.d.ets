// @keepTs
// @ts-nocheck
type Theme = "light" | "dark";
@Observed
declare class LvCode {
    private theme;
    private indexState;
    setTheme(g119: Theme): void;
    setIndexState(f119: boolean): void;
    getTheme(): string;
    getIndexState(): boolean;
}
declare const lvCode: LvCode;
export { lvCode, LvCode };
