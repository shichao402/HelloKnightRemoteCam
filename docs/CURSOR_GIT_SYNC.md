# Cursor Git 同步问题解决方案

## 问题描述

Cursor 每次 git 同步都会失败，需要手动执行 `git pull --rebase` 才能继续使用。

## 问题原因

1. **默认 pull 策略问题**：Git 默认使用 merge 策略，当本地有未推送的提交且远程也有新提交时，Cursor 的自动同步可能无法处理分叉情况。

2. **本地未推送提交**：当本地分支领先远程分支时，Cursor 的同步机制可能无法正确处理。

3. **多个远程仓库**：项目配置了多个远程仓库（gitlab 和 origin），可能导致同步混乱。

## 解决方案

### 方案1：配置 Git 使用 Rebase（推荐）

已为项目配置了 `pull.rebase=true`，这样 Cursor 的 git 同步会自动使用 rebase 策略：

```bash
git config pull.rebase true
```

**优点：**
- 保持提交历史线性
- Cursor 同步时自动使用 rebase
- 避免不必要的 merge 提交

**验证配置：**
```bash
git config --get pull.rebase
# 应该输出: true
```

### 方案2：手动推送本地提交

如果本地有未推送的提交，先推送再同步：

```bash
# 检查本地未推送的提交
git log origin/main..HEAD --oneline

# 推送本地提交
git push origin main

# 然后再让 Cursor 同步
```

### 方案3：使用 Rebase 同步（手动）

如果 Cursor 同步失败，可以手动执行：

```bash
git pull --rebase origin main
```

## 当前配置状态

项目已配置：
- ✅ `pull.rebase=true` - 自动使用 rebase 策略

## 最佳实践

1. **及时推送提交**：避免本地积累太多未推送的提交
2. **使用 rebase**：保持提交历史清晰
3. **定期同步**：在开始工作前先同步远程更改

## 故障排除

### 如果 Cursor 同步仍然失败

1. **检查 git 状态**：
   ```bash
   git status
   ```

2. **检查是否有冲突**：
   ```bash
   git fetch origin
   git log --oneline --graph --all -10
   ```

3. **手动 rebase**：
   ```bash
   git pull --rebase origin main
   ```

4. **如果 rebase 有冲突**：
   ```bash
   # 解决冲突后
   git add .
   git rebase --continue
   ```

## 相关命令

```bash
# 查看当前 pull 配置
git config --get pull.rebase

# 查看所有 pull 相关配置
git config --list | grep pull

# 查看本地和远程的差异
git log origin/main..HEAD --oneline  # 本地未推送的提交
git log HEAD..origin/main --oneline  # 远程未拉取的提交
```

