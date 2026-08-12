// @keepTs
// @ts-nocheck
/**
 * 日志级别枚举
 */
export declare enum LogLevel {
    DEBUG = 3,
    INFO = 4,
    WARN = 5,
    ERROR = 6,
    FATAL = 7
}
/**
 * HiLog工具类 - 支持长日志换行、多级别日志和强制打印
 */
export declare class LogUtil {
    private static MAX_LOG_LENGTH;
    private isForcePrint;
    /**
     * 打印DEBUG级别日志 - 支持多参数
     * @param tag 日志标签
     * @param messages 日志内容参数列表   */
    debug(j111: string, ...k111: ESObject[]): void;
    /**
     * 打印INFO级别日志 - 支持多参数
     * @param tag 日志标签
     * @param messages 日志内容参数列表
     */
    info(h111: string, ...i111: ESObject[]): void;
    /**
     * 打印WARN级别日志 - 支持多参数
     * @param tag 日志标签
     * @param messages 日志内容参数列表
     */
    warn(f111: string, ...g111: ESObject[]): void;
    /**
     * 打印ERROR级别日志 - 支持多参数
     * @param tag 日志标签
     * @param messages 日志内容参数列表
     */
    error(d111: string, ...e111: ESObject[]): void;
    /**
     * 打印FATAL级别日志 - 支持多参数
     * @param tag 日志标签
     * @param messages 日志内容参数列表
     */
    fatal(b111: string, ...c111: ESObject[]): void;
    /**
     * 强制打印日志（无视release环境限制）- 支持多参数
     * @param tag 日志标签
     * @param messages 日志内容参数列表
     */
    infoForce(z110: string, ...a111: ESObject[]): void;
    /**
     * 强制打印日志（无视release环境限制）- 支持多参数
     * @param tag 日志标签
     * @param messages 日志内容参数列表
     */
    errorForce(x110: string, ...y110: ESObject[]): void;
    /**
     * 核心日志打印方法
     * @param level 日志级别
     * @param tag 日志标签
     * @param messages 日志内容参数列表
     * @param force 是否强制打印
     */
    private printLog;
    /**
     * 将多个参数格式化为单个日志字符串
     * @param messages 参数列表
     */
    private formatMessages;
    /**
     * 打印单条日志
     * @param level 日志级别
     * @param tag 日志标签
     * @param message 日志内容
     */
    private printSingleLog;
    /**
     * 获取调用者信息
     * @returns 调用者类名和方法名
     */
    private getCallerInfo;
    setDebugState(w109: boolean): void;
}
export declare const Logger: LogUtil;
