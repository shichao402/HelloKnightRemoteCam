import { z } from 'zod';

/** 服务器配置 schema */
const ConfigSchema = z.object({
  port: z.number().default(3900),
  host: z.string().default('0.0.0.0'),
  dbPath: z.string().default('data/core.db'),
  logLevel: z.enum(['debug', 'info', 'warn', 'error']).default('info'),
});

export type Config = z.infer<typeof ConfigSchema>;

/** 从环境变量读取配置 */
export function loadConfig(): Config {
  return ConfigSchema.parse({
    port: env('CORE_PORT', 3900, Number),
    host: env('CORE_HOST', '0.0.0.0'),
    dbPath: env('CORE_DB_PATH', 'data/core.db'),
    logLevel: env('CORE_LOG_LEVEL', 'info'),
  });
}

function env<T>(key: string, fallback: T, transform?: (v: string) => T): T {
  const raw = process.env[key];
  if (raw === undefined) return fallback;
  return transform ? transform(raw) : (raw as unknown as T);
}
