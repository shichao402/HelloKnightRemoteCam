import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { initDatabase, closeDatabase } from '../database.js';
import {
  createTask,
  getTaskById,
  listTasks,
  updateTask,
  deleteTask,
  addSubmission,
  deleteSubmission,
} from '../task-repository.js';
import type { CreateTaskInput } from '../../models/task.js';

const TEST_DB = ':memory:';

function sampleInput(override?: Partial<CreateTaskInput>): CreateTaskInput {
  return {
    title: '数学作业第三单元',
    description: '完成课本 P42-43 练习题',
    source: { channel: 'wecom', messageId: 'msg-001' },
    attachments: [
      { type: 'image', url: 'https://example.com/hw.jpg', description: '作业要求' },
    ],
    ...override,
  };
}

describe('TaskRepository', () => {
  beforeEach(() => {
    initDatabase(TEST_DB);
  });

  afterEach(() => {
    closeDatabase();
  });

  it('should create and retrieve a task', () => {
    const task = createTask(sampleInput());
    expect(task.id).toBeDefined();
    expect(task.title).toBe('数学作业第三单元');
    expect(task.status).toBe('pending');
    expect(task.attachments).toHaveLength(1);
    expect(task.submissions).toHaveLength(0);

    const fetched = getTaskById(task.id);
    expect(fetched).toEqual(task);
  });

  it('should list tasks with pagination', () => {
    createTask(sampleInput({ title: '任务1' }));
    createTask(sampleInput({ title: '任务2' }));
    createTask(sampleInput({ title: '任务3' }));

    const { tasks, total } = listTasks({ limit: 2, offset: 0 });
    expect(total).toBe(3);
    expect(tasks).toHaveLength(2);
  });

  it('should filter tasks by status', () => {
    const t1 = createTask(sampleInput({ title: '已完成任务' }));
    createTask(sampleInput({ title: '待处理任务' }));
    updateTask(t1.id, { status: 'completed' });

    const { tasks, total } = listTasks({ status: 'completed', limit: 50, offset: 0 });
    expect(total).toBe(1);
    expect(tasks[0].title).toBe('已完成任务');
    expect(tasks[0].completedAt).toBeDefined();
  });

  it('should search tasks by keyword', () => {
    createTask(sampleInput({ title: '数学作业' }));
    createTask(sampleInput({ title: '语文作业' }));

    const { tasks } = listTasks({ keyword: '数学', limit: 50, offset: 0 });
    expect(tasks).toHaveLength(1);
    expect(tasks[0].title).toBe('数学作业');
  });

  it('should update a task', () => {
    const task = createTask(sampleInput());
    const updated = updateTask(task.id, { title: '更新后标题', status: 'in_progress' });

    expect(updated).not.toBeNull();
    expect(updated!.title).toBe('更新后标题');
    expect(updated!.status).toBe('in_progress');
  });

  it('should delete a task (cascade)', () => {
    const task = createTask(sampleInput());
    addSubmission(task.id, {
      type: 'photo',
      localPath: '/tmp/photo.jpg',
      note: '第一题',
    });

    const deleted = deleteTask(task.id);
    expect(deleted).toBe(true);
    expect(getTaskById(task.id)).toBeNull();
  });

  it('should add and delete a submission', () => {
    const task = createTask(sampleInput());

    const sub = addSubmission(task.id, {
      type: 'photo',
      localPath: '/tmp/photo.jpg',
      thumbnailPath: '/tmp/photo_thumb.jpg',
      note: '第一题答案',
    });
    expect(sub).not.toBeNull();
    expect(sub!.type).toBe('photo');
    expect(sub!.note).toBe('第一题答案');

    // 验证任务包含提交物
    const refreshed = getTaskById(task.id);
    expect(refreshed!.submissions).toHaveLength(1);

    // 删除提交物
    const removed = deleteSubmission(task.id, sub!.id);
    expect(removed).toBe(true);

    const afterDelete = getTaskById(task.id);
    expect(afterDelete!.submissions).toHaveLength(0);
  });

  it('should return null for non-existent task', () => {
    expect(getTaskById('non-existent')).toBeNull();
    expect(updateTask('non-existent', { title: 'x' })).toBeNull();
    expect(deleteTask('non-existent')).toBe(false);
  });
});
