import { randomUUID } from 'node:crypto';

// 《人工智能生成合成内容标识办法》（2025-09-01 施行）+ 强制性国标 GB 45438-2025 附录 E 隐式标识：
// 通过接口提供 AI 生成内容时，响应须附带元数据标识。
// 首次写入方即本应用运营主体（上游模型商不写标识），按附录 E 注 1：首写时
// ContentPropagator=ContentProducer、PropagateID=ProduceID（链头自洽，源头编号须写入方可对账）。
// 上游第三方大模型关系按华为 AGC FAQ #9(4) 走"服务提供方出具证明/官方平台自测"通道，
// 实际使用的模型名记录在 ReservedCode1（预留字段，写入方自主使用）。
const CONTENT_PRODUCER = '苏州终北科技有限公司';
const CONTENT_PROPAGATOR = '苏州终北科技有限公司';

export type AiMetadata = {
  AIGC: {
    /** 内容属性：1=AI 生成，2=AI 合成，3=疑似 AI 生成（翻译/摘要属 AI 生成文本） */
    Label: string;
    /** 生成合成服务提供者（模型服务方：深度求索） */
    ContentProducer: string;
    /** 内容编号（本次响应批次唯一） */
    ProduceID: string;
    /** 预留扩展字段：记录实际使用的模型名称，便于备案核查 */
    ReservedCode1: string;
    /** 内容传播服务提供者（本应用运营主体） */
    ContentPropagator: string;
    /** 传播编号（与 ProduceID 同值，便于日志关联） */
    PropagateID: string;
    ReservedCode2: string;
  };
};

export function aiMetadata(): AiMetadata {
  const produceId = randomUUID();
  return {
    AIGC: {
      Label: '1',
      ContentProducer: CONTENT_PRODUCER,
      ProduceID: produceId,
      ReservedCode1: process.env.MODEL_NAME?.trim() ?? '',
      ContentPropagator: CONTENT_PROPAGATOR,
      PropagateID: produceId,
      ReservedCode2: '',
    },
  };
}
