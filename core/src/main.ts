import Fastify from 'fastify';
import { ZodError } from 'zod';
import { loadConfig } from './config.js';
import { createLogger, setLogLevel } from './logger.js';
import { initDatabase, closeDatabase } from './storage/index.js';
import { registerTaskRoutes, registerEventRoutes } from './api/index.js';

const log = createLogger('Main');

async function main(): Promise<void> {
  // 1. 加载配置
  const config = loadConfig();
  setLogLevel(config.logLevel);
  log.info('Configuration loaded', config);

  // 2. 初始化数据库
  initDatabase(config.dbPath);

  // 3. 创建 Fastify 实例
  const app = Fastify({
    logger: false, // 使用自己的日志系统
  });

  // 全局错误处理 — Zod 校验失败返回 400
  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof ZodError) {
      return reply.status(400).send({
        error: 'Validation Error',
        details: error.errors.map((e) => ({
          path: e.path.join('.'),
          message: e.message,
        })),
      });
    }

    // 处理 Fastify 内置的校验错误
    if (error.validation) {
      return reply.status(400).send({
        error: 'Validation Error',
        message: error.message,
      });
    }

    log.error(`Unhandled error: ${error.message}`, error);
    return reply.status(500).send({ error: 'Internal Server Error' });
  });

  // 4. 注册路由
  registerTaskRoutes(app);
  registerEventRoutes(app);

  // 健康检查
  app.get('/api/health', async () => ({
    status: 'ok',
    timestamp: new Date().toISOString(),
    version: '0.1.0',
  }));

  // 5. 启动服务器
  try {
    await app.listen({ port: config.port, host: config.host });
    log.info(`Core Service running on http://${config.host}:${config.port}`);
  } catch (err) {
    log.error('Failed to start server:', err);
    process.exit(1);
  }

  // 6. 优雅退出
  const shutdown = async (signal: string) => {
    log.info(`Received ${signal}, shutting down...`);
    await app.close();
    closeDatabase();
    process.exit(0);
  };

  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
