// @keepTs
// @ts-nocheck
import { MarkdownPlugin } from '../model/MarkdownPlugin';
export declare class MarkdownPluginRegistry {
    private static pluginMap;
    static registerPlugins(k56: string, l56: MarkdownPlugin[]): void;
    static getPlugin(i56: string, j56: string): MarkdownPlugin | undefined;
    static destroy(h56: string): void;
}
