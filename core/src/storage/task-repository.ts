import { v4 as uuidv4 } from 'uuid';
import { getDatabase } from './database.js';
import { createLogger } from '../logger.js';
import type {
  Task,
  TaskSource,
  Attachment,
  Submission,
  CreateTaskInput,
  UpdateTaskInput,
  CreateSubmissionInput,
  TaskListQuery,
} from '../models/index.js';

const log = createLogger('TaskRepo');

// ─── Row → Domain Object Helpers ──────────────────────────────

function rowToTask(row: Record<string, unknown>, attachments: Attachment[], submissions: Submission[]): Task {
  return {
    id: row.id as string,
    title: row.title as string,
    description: row.description as string,
    status: row.status as Task['status'],
    source: {
      channel: row.source_channel as string,
      messageId: (row.source_message_id as string) || undefined,
      rawContent: (row.source_raw_content as string) || undefined,
    },
    attachments,
    submissions,
    dueDate: (row.due_date as string) || undefined,
    createdAt: row.created_at as string,
    updatedAt: row.updated_at as string,
    completedAt: (row.completed_at as string) || undefined,
  };
}

function rowToAttachment(row: Record<string, unknown>): Attachment {
  return {
    id: row.id as string,
    taskId: row.task_id as string,
    type: row.type as Attachment['type'],
    url: (row.url as string) || undefined,
    localPath: (row.local_path as string) || undefined,
    description: (row.description as string) || undefined,
  };
}

function rowToSubmission(row: Record<string, unknown>): Submission {
  return {
    id: row.id as string,
    taskId: row.task_id as string,
    mediaId: (row.media_id as string) || undefined,
    type: row.type as Submission['type'],
    localPath: row.local_path as string,
    thumbnailPath: (row.thumbnail_path as string) || undefined,
    note: (row.note as string) || undefined,
    createdAt: row.created_at as string,
  };
}

// ─── Query Helpers ────────────────────────────────────────────

function getAttachmentsForTask(taskId: string): Attachment[] {
  const db = getDatabase();
  const rows = db.prepare('SELECT * FROM attachments WHERE task_id = ?').all(taskId) as Record<string, unknown>[];
  return rows.map(rowToAttachment);
}

function getSubmissionsForTask(taskId: string): Submission[] {
  const db = getDatabase();
  const rows = db.prepare('SELECT * FROM submissions WHERE task_id = ? ORDER BY created_at ASC').all(taskId) as Record<string, unknown>[];
  return rows.map(rowToSubmission);
}

// ─── Task CRUD ────────────────────────────────────────────────

/** 创建任务 */
export function createTask(input: CreateTaskInput): Task {
  const db = getDatabase();
  const id = uuidv4();
  const now = new Date().toISOString();

  const insertTask = db.transaction(() => {
    db.prepare(`
      INSERT INTO tasks (id, title, description, status, source_channel, source_message_id, source_raw_content, due_date, created_at, updated_at)
      VALUES (?, ?, ?, 'pending', ?, ?, ?, ?, ?, ?)
    `).run(
      id,
      input.title,
      input.description,
      input.source.channel,
      input.source.messageId ?? null,
      input.source.rawContent ?? null,
      input.dueDate ?? null,
      now,
      now,
    );

    // 插入附件
    if (input.attachments.length > 0) {
      const insertAtt = db.prepare(`
        INSERT INTO attachments (id, task_id, type, url, local_path, description)
        VALUES (?, ?, ?, ?, ?, ?)
      `);
      for (const att of input.attachments) {
        insertAtt.run(uuidv4(), id, att.type, att.url ?? null, att.localPath ?? null, att.description ?? null);
      }
    }
  });

  insertTask();
  log.info(`Task created: ${id} "${input.title}"`);

  return getTaskById(id)!;
}

/** 根据 ID 获取任务（含附件和提交物） */
export function getTaskById(id: string): Task | null {
  const db = getDatabase();
  const row = db.prepare('SELECT * FROM tasks WHERE id = ?').get(id) as Record<string, unknown> | undefined;
  if (!row) return null;

  return rowToTask(row, getAttachmentsForTask(id), getSubmissionsForTask(id));
}

/** 查询任务列表 */
export function listTasks(query: TaskListQuery): { tasks: Task[]; total: number } {
  const db = getDatabase();
  const conditions: string[] = [];
  const params: unknown[] = [];

  if (query.status) {
    conditions.push('status = ?');
    params.push(query.status);
  }
  if (query.keyword) {
    conditions.push('(title LIKE ? OR description LIKE ?)');
    const kw = `%${query.keyword}%`;
    params.push(kw, kw);
  }

  const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

  const countRow = db.prepare(`SELECT COUNT(*) as total FROM tasks ${whereClause}`).get(...params) as { total: number };
  const total = countRow.total;

  const rows = db.prepare(`SELECT * FROM tasks ${whereClause} ORDER BY created_at DESC LIMIT ? OFFSET ?`)
    .all(...params, query.limit, query.offset) as Record<string, unknown>[];

  const tasks = rows.map((row) => {
    const id = row.id as string;
    return rowToTask(row, getAttachmentsForTask(id), getSubmissionsForTask(id));
  });

  return { tasks, total };
}

/** 更新任务 */
export function updateTask(id: string, input: UpdateTaskInput): Task | null {
  const db = getDatabase();
  const existing = db.prepare('SELECT * FROM tasks WHERE id = ?').get(id) as Record<string, unknown> | undefined;
  if (!existing) return null;

  const now = new Date().toISOString();
  const sets: string[] = ['updated_at = ?'];
  const params: unknown[] = [now];

  if (input.title !== undefined) {
    sets.push('title = ?');
    params.push(input.title);
  }
  if (input.description !== undefined) {
    sets.push('description = ?');
    params.push(input.description);
  }
  if (input.status !== undefined) {
    sets.push('status = ?');
    params.push(input.status);
    if (input.status === 'completed') {
      sets.push('completed_at = ?');
      params.push(now);
    }
  }
  if (input.dueDate !== undefined) {
    sets.push('due_date = ?');
    params.push(input.dueDate);
  }

  params.push(id);
  db.prepare(`UPDATE tasks SET ${sets.join(', ')} WHERE id = ?`).run(...params);
  log.info(`Task updated: ${id}`);

  return getTaskById(id)!;
}

/** 删除任务（级联删除附件和提交物） */
export function deleteTask(id: string): boolean {
  const db = getDatabase();
  const result = db.prepare('DELETE FROM tasks WHERE id = ?').run(id);
  if (result.changes > 0) {
    log.info(`Task deleted: ${id}`);
    return true;
  }
  return false;
}

// ─── Submission CRUD ──────────────────────────────────────────

/** 添加提交物 */
export function addSubmission(taskId: string, input: CreateSubmissionInput): Submission | null {
  const db = getDatabase();

  // 确认任务存在
  const task = db.prepare('SELECT id FROM tasks WHERE id = ?').get(taskId);
  if (!task) return null;

  const id = uuidv4();
  const now = new Date().toISOString();

  db.prepare(`
    INSERT INTO submissions (id, task_id, media_id, type, local_path, thumbnail_path, note, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).run(id, taskId, input.mediaId ?? null, input.type, input.localPath, input.thumbnailPath ?? null, input.note ?? null, now);

  // 同步更新任务 updated_at
  db.prepare('UPDATE tasks SET updated_at = ? WHERE id = ?').run(now, taskId);

  log.info(`Submission added: ${id} to task ${taskId}`);
  return rowToSubmission(
    db.prepare('SELECT * FROM submissions WHERE id = ?').get(id) as Record<string, unknown>,
  );
}

/** 删除提交物 */
export function deleteSubmission(taskId: string, submissionId: string): boolean {
  const db = getDatabase();
  const result = db.prepare('DELETE FROM submissions WHERE id = ? AND task_id = ?').run(submissionId, taskId);
  if (result.changes > 0) {
    db.prepare('UPDATE tasks SET updated_at = ? WHERE id = ?').run(new Date().toISOString(), taskId);
    log.info(`Submission deleted: ${submissionId} from task ${taskId}`);
    return true;
  }
  return false;
}
