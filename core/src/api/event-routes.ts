import type { FastifyInstance } from 'fastify';
import { eventBus } from '../events/index.js';
import { createLogger } from '../logger.js';

const log = createLogger('SSE');

/** 注册 SSE 事件推送端点 */
export function registerEventRoutes(app: FastifyInstance): void {

  app.get('/api/events', async (request, reply) => {
    // SSE 响应头
    reply.raw.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'X-Accel-Buffering': 'no',   // 禁用 nginx 缓冲
    });

    // 发送初始连接确认
    reply.raw.write(`data: ${JSON.stringify({ type: 'connected', timestamp: new Date().toISOString() })}\n\n`);

    // 心跳定时器 — 保持连接
    const heartbeat = setInterval(() => {
      reply.raw.write(`: heartbeat\n\n`);
    }, 30_000);

    // 订阅事件总线
    const unsubscribe = eventBus.subscribe((event) => {
      reply.raw.write(`event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`);
    });

    // 客户端断开时清理
    request.raw.on('close', () => {
      clearInterval(heartbeat);
      unsubscribe();
      log.info('SSE client disconnected');
    });

    log.info('SSE client connected');

    // 阻止 Fastify 自动结束响应
    return reply.hijack();
  });

  log.info('Event routes registered');
}
