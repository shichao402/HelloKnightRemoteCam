import { createLogger } from '../logger.js';

const log = createLogger('EventBus');

/** 事件类型定义 */
export interface TaskEvent {
  type: 'task.created' | 'task.updated' | 'task.deleted' | 'submission.added' | 'submission.deleted';
  taskId: string;
  timestamp: string;
  payload?: Record<string, unknown>;
}

type EventListener = (event: TaskEvent) => void;

/** 内存事件总线 — 用于 SSE 推送和内部解耦 */
class EventBus {
  private listeners: Set<EventListener> = new Set();

  /** 订阅事件 */
  subscribe(listener: EventListener): () => void {
    this.listeners.add(listener);
    log.debug(`Subscriber added, total: ${this.listeners.size}`);
    return () => {
      this.listeners.delete(listener);
      log.debug(`Subscriber removed, total: ${this.listeners.size}`);
    };
  }

  /** 发布事件 */
  emit(event: TaskEvent): void {
    log.info(`Event: ${event.type} taskId=${event.taskId}`);
    for (const listener of this.listeners) {
      try {
        listener(event);
      } catch (err) {
        log.error(`Listener error for ${event.type}:`, err);
      }
    }
  }
}

/** 全局单例 */
export const eventBus = new EventBus();
