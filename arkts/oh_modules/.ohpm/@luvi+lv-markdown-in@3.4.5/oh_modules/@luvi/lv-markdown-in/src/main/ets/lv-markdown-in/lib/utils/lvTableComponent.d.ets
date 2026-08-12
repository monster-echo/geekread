// @keepTs
// @ts-nocheck
@Component
export declare struct lvTableComponent {
    @State
    text: string;
    @State
    dialogController: CustomDialogController | null;
    @State
    cellWidthArrayIndexed: number[];
    build(): void;
    @Builder
    lvTableHeadBuilder(l142: string, m142: CustomDialogController | null): void;
    @Builder
    lvTableRowBuilder(q141: string, r141: number, s141: CustomDialogController | null): void;
}
