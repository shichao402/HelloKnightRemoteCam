import { z } from 'zod';

// ─── Task Status ──────────────────────────────────────────────

export const TaskStatusEnum = z.enum([
  'pending',
  'in_progress',
  'completed',
  'returned',
]);

export type TaskStatus = z.infer<typeof TaskStatusEnum>;

// ─── Attachment ───────────────────────────────────────────────

export const AttachmentTypeEnum = z.enum(['image', 'video', 'file', 'text']);

export interface Attachment {
  id: string;
  taskId: string;
  type: z.infer<typeof AttachmentTypeEnum>;
  url?: string;
  localPath?: string;
  description?: string;
}

// ─── Submission ───────────────────────────────────────────────

export const SubmissionTypeEnum = z.enum(['photo', 'video', 'file']);

export interface Submission {
  id: string;
  taskId: string;
  mediaId?: string;
  type: z.infer<typeof SubmissionTypeEnum>;
  localPath: string;
  thumbnailPath?: string;
  note?: string;
  createdAt: string;
}

// ─── Task ─────────────────────────────────────────────────────

export interface TaskSource {
  channel: string;
  messageId?: string;
  rawContent?: string;
}

export interface Task {
  id: string;
  title: string;
  description: string;
  status: TaskStatus;
  source: TaskSource;
  attachments: Attachment[];
  submissions: Submission[];
  dueDate?: string;
  createdAt: string;
  updatedAt: string;
  completedAt?: string;
}

// ─── API Validation Schemas ───────────────────────────────────

export const CreateTaskSchema = z.object({
  title: z.string().min(1).max(500),
  description: z.string().default(''),
  source: z.object({
    channel: z.string().min(1),
    messageId: z.string().optional(),
    rawContent: z.string().optional(),
  }).default({ channel: 'manual' }),
  dueDate: z.string().optional(),
  attachments: z.array(z.object({
    type: AttachmentTypeEnum,
    url: z.string().optional(),
    localPath: z.string().optional(),
    description: z.string().optional(),
  })).default([]),
});

export type CreateTaskInput = z.infer<typeof CreateTaskSchema>;

export const UpdateTaskSchema = z.object({
  title: z.string().min(1).max(500).optional(),
  description: z.string().optional(),
  status: TaskStatusEnum.optional(),
  dueDate: z.string().nullable().optional(),
});

export type UpdateTaskInput = z.infer<typeof UpdateTaskSchema>;

export const CreateSubmissionSchema = z.object({
  mediaId: z.string().optional(),
  type: SubmissionTypeEnum,
  localPath: z.string().min(1),
  thumbnailPath: z.string().optional(),
  note: z.string().optional(),
});

export type CreateSubmissionInput = z.infer<typeof CreateSubmissionSchema>;

export const TaskListQuerySchema = z.object({
  status: TaskStatusEnum.optional(),
  keyword: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});

export type TaskListQuery = z.infer<typeof TaskListQuerySchema>;
