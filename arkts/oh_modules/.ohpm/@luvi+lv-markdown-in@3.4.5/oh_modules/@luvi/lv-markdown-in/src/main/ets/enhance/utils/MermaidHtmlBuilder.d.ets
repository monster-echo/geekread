// @keepTs
// @ts-nocheck
import { CodeTheme } from '../constant/CodeTheme';
export type MermaidTheme = "default" | "dark" | "forest" | "neutral";
export type MermaidSecurityLevel = "strict" | "loose" | "antiscript" | "sandbox";
export declare function buildMermaidHtml(r111: Context, s111: string, t111: MermaidTheme, u111: MermaidSecurityLevel, v111?: CodeTheme): Promise<string>;
export declare function buildMermaidMissingHtml(l111?: CodeTheme): string;
