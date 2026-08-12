// @keepTs
// @ts-nocheck
export declare namespace TableImpl {
    let tableWidthsList: number[][];
    let tableWidthsUnionList: string[];
    function handleTableBackgroundColor(v68: string): ResourceColor;
    function handleTableTitleBackgroundColor(u68: string): ResourceColor;
    function handleTableTitleTextColor(t68: string): ResourceColor;
    function handleTableInterleaveTextColor(s68: string): ResourceColor;
    function handleTableNormalTextColor(r68: string): ResourceColor;
    function handleTableInterleaveBackgroundColor(q68: string): ResourceColor;
    function handleTableBorderRadius(p68: string): ResourceStr | number;
    function handleTableOuterBorderColor(o68: string): ResourceColor | null;
    function handleTableOuterBorderWidth(n68: string): ResourceStr | number;
    function handleTableInnerBorderColor(m68: string): ResourceColor | null;
    function handleTableInnerBorderWidth(l68: string): ResourceStr | number;
    function handleTableAlign(k68: string): FlexAlign;
    function handleTextAlign(j68: "none" | "left" | "center" | "right" | string | undefined): HorizontalAlign;
}
