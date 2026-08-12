// 出站 HTTP 代理支持（受限网络，如国内直连 HN/LLM 超时时）。
// 设置 HTTPS_PROXY/HTTP_PROXY 即生效；NO_PROXY 控制 bypass（默认本地回环）。
// 用 undici ProxyAgent（显式 URL）——EnvHttpProxyAgent 对部分代理不兼容。
import { ProxyAgent, setGlobalDispatcher } from 'undici';

const proxyUrl = process.env.HTTPS_PROXY?.trim() || process.env.HTTP_PROXY?.trim();
if (proxyUrl) {
  setGlobalDispatcher(new ProxyAgent(proxyUrl));
}
