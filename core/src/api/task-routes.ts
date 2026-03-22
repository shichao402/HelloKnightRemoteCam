import type { FastifyInstance } from 'fastify';
import {
  CreateTaskSchema,
  UpdateTaskSchema,
  CreateSubmissionSchema,
  TaskListQuerySchema,
} from '../models/index.js';
import {
  createTask,
  getTaskById,
  listTasks,
  updateTask,
  deleteTask,
  addSubmission,
  deleteSubmission,
} from '../storage/index.js';
import { eventBus } from '../events/index.js';
import { createLogger } from '../logger.js';

const log = createLogger('TaskAPI');

/** 注册任务相关 REST API 路由 */
export function registerTaskRoutes(app: FastifyInstance): void {

  // ─── 任务列表 ─────────────────────────────────────────────
  app.get('/api/tasks', async (request, reply) => {
    const query = TaskListQuerySchema.parse(request.query);
    const result = listTasks(query);
    return reply.send({
      tasks: result.tasks,
      total: result.total,
      limit: query.limit,
      offset: query.offset,
    });
  });

  // ─── 任务详情 ─────────────────────────────────────────────
  app.get<{ Params: { id: string } }>('/api/tasks/:id', async (request, reply) => {
    const task = getTaskById(request.params.id);
    if (!task) {
      return reply.status(404).send({ error: 'Task not found' });
    }
    return reply.send(task);
  });

  // ─── 创建任务 ─────────────────────────────────────────────
  app.post('/api/tasks', async (request, reply) => {
    const input = CreateTaskSchema.parse(request.body);
    const task = createTask(input);

    eventBus.emit({
      type: 'task.created',
      taskId: task.id,
      timestamp: task.createdAt,
      payload: { title: task.title, status: task.status },
    });

    log.info(`POST /api/tasks → ${task.id}`);
    return reply.status(201).send(task);
  });

  // ─── 更新任务 ─────────────────────────────────────────────
  app.patch<{ Params: { id: string } }>('/api/tasks/:id', async (request, reply) => {
    const input = UpdateTaskSchema.parse(request.body);
    const task = updateTask(request.params.id, input);
    if (!task) {
      return reply.status(404).send({ error: 'Task not found' });
    }

    eventBus.emit({
      type: 'task.updated',
      taskId: task.id,
      timestamp: task.updatedAt,
      payload: { title: task.title, status: task.status },
    });

    return reply.send(task);
  });

  // ─── 删除任务 ─────────────────────────────────────────────
  app.delete<{ Params: { id: string } }>('/api/tasks/:id', async (request, reply) => {
    const deleted = deleteTask(request.params.id);
    if (!deleted) {
      return reply.status(404).send({ error: 'Task not found' });
    }

    eventBus.emit({
      type: 'task.deleted',
      taskId: request.params.id,
      timestamp: new Date().toISOString(),
    });

    return reply.status(204).send();
  });

  // ─── 添加提交物 ───────────────────────────────────────────
  app.post<{ Params: { id: string } }>('/api/tasks/:id/submissions', async (request, reply) => {
    const input = CreateSubmissionSchema.parse(request.body);
    const submission = addSubmission(request.params.id, input);
    if (!submission) {
      return reply.status(404).send({ error: 'Task not found' });
    }

    eventBus.emit({
      type: 'submission.added',
      taskId: request.params.id,
      timestamp: submission.createdAt,
      payload: { submissionId: submission.id, type: submission.type },
    });

    return reply.status(201).send(submission);
  });

  // ─── 删除提交物 ───────────────────────────────────────────
  app.delete<{ Params: { id: string; sid: string } }>('/api/tasks/:id/submissions/:sid', async (request, reply) => {
    const deleted = deleteSubmission(request.params.id, request.params.sid);
    if (!deleted) {
      return reply.status(404).send({ error: 'Submission not found' });
    }

    eventBus.emit({
      type: 'submission.deleted',
      taskId: request.params.id,
      timestamp: new Date().toISOString(),
      payload: { submissionId: request.params.sid },
    });

    return reply.status(204).send();
  });

  log.info('Task routes registered');
}
