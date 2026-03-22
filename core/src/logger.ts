/** 简易日志服务 — 统一输出格式，关键操作可追溯 */

type LogLevel = 'debug' | 'info' | 'warn' | 'error';

const LEVEL_ORDER: Record<LogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
};

let currentLevel: LogLevel = 'info';

export function setLogLevel(level: LogLevel): void {
  currentLevel = level;
}

function shouldLog(level: LogLevel): boolean {
  return LEVEL_ORDER[level] >= LEVEL_ORDER[currentLevel];
}

function formatMessage(level: LogLevel, tag: string, message: string): string {
  const ts = new Date().toISOString();
  return `${ts} [${level.toUpperCase().padEnd(5)}] [${tag}] ${message}`;
}

export function createLogger(tag: string) {
  return {
    debug(msg: string, ...args: unknown[]) {
      if (shouldLog('debug')) console.debug(formatMessage('debug', tag, msg), ...args);
    },
    info(msg: string, ...args: unknown[]) {
      if (shouldLog('info')) console.info(formatMessage('info', tag, msg), ...args);
    },
    warn(msg: string, ...args: unknown[]) {
      if (shouldLog('warn')) console.warn(formatMessage('warn', tag, msg), ...args);
    },
    error(msg: string, ...args: unknown[]) {
      if (shouldLog('error')) console.error(formatMessage('error', tag, msg), ...args);
    },
  };
}
