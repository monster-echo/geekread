// @keepTs
// @ts-nocheck
import { LvLink } from '../domain/LvLink';
@Component
export declare struct lvHyperlinkComponent {
    @Prop
    text: string;
    @Prop
    uri: string;
    @Prop
    nLink: LvLink;
    @Prop
    fontSize: number | string;
    @Prop
    fontWeight: FontWeight;
    @Prop
    dialogController: CustomDialogController | null;
    build(): void;
}
@Builder
export default function lvHyperlinkBuilder(w137: string, x137: string, y137: LvLink, z137: number | string, a138: FontWeight, b138: CustomDialogController | null): void;
