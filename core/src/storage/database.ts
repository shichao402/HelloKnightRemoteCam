import Database from 'better-sqlite3';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { createLogger } from '../logger.js';

const log = createLogger('Database');

let db: Database.Database | null = null;

/** 初始化数据库（创建表结构） */
export function initDatabase(dbPath: string): Database.Database {
  // 确保目录存在
  mkdirSync(dirname(dbPath), { recursive: true });

  db = new Database(dbPath);

  // 开启 WAL 模式 — 读写并发更好
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');

  createTables(db);
  log.info(`Database initialized at ${dbPath}`);
  return db;
}

export function getDatabase(): Database.Database {
  if (!db) throw new Error('Database not initialized. Call initDatabase() first.');
  return db;
}

export function closeDatabase(): void {
  if (db) {
    db.close();
    db = null;
    log.info('Database closed');
  }
}

function createTables(db: Database.Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS tasks (
      id          TEXT PRIMARY KEY,
      title       TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      status      TEXT NOT NULL DEFAULT 'pending'
                    CHECK(status IN ('pending','in_progress','completed','returned')),
      source_channel    TEXT NOT NULL DEFAULT 'manual',
      source_message_id TEXT,
      source_raw_content TEXT,
      due_date    TEXT,
      created_at  TEXT NOT NULL,
      updated_at  TEXT NOT NULL,
      completed_at TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
    CREATE INDEX IF NOT EXISTS idx_tasks_created ON tasks(created_at);

    CREATE TABLE IF NOT EXISTS attachments (
      id          TEXT PRIMARY KEY,
      task_id     TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
      type        TEXT NOT NULL CHECK(type IN ('image','video','file','text')),
      url         TEXT,
      local_path  TEXT,
      description TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_attachments_task ON attachments(task_id);

    CREATE TABLE IF NOT EXISTS submissions (
      id             TEXT PRIMARY KEY,
      task_id        TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
      media_id       TEXT,
      type           TEXT NOT NULL CHECK(type IN ('photo','video','file')),
      local_path     TEXT NOT NULL,
      thumbnail_path TEXT,
      note           TEXT,
      created_at     TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_submissions_task ON submissions(task_id);
  `);
  log.info('Database tables ensured');
}
