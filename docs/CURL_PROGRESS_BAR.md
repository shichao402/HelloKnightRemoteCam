# curl 进度条显示最佳实践

## 问题描述

在使用 `curl --progress-bar` 上传文件时，如果使用 `2>&1` 将所有输出重定向，会导致进度条无法实时显示，因为进度条输出被缓冲了。

## 错误示例

```bash
# ❌ 错误：进度条无法实时显示
UPLOAD_OUTPUT=$(curl --progress-bar -w "%{http_code}" \
  -o "${TEMP_RESPONSE_FILE}" \
  -X POST \
  -F "file=@${file}" \
  "${API_URL}" 2>&1)
```

## 正确做法

### curl 输出流说明

- **stdout**: HTTP 响应体（默认），`-w` 指定的格式字符串（如 HTTP 状态码）
- **stderr**: 进度条（`--progress-bar`）、错误信息（`--show-error`）

### 正确示例

```bash
# ✅ 正确：只重定向 stdout，让 stderr（进度条）直接输出到终端
TEMP_RESPONSE_FILE=$(mktemp)
TEMP_HTTP_CODE_FILE=$(mktemp)

curl --progress-bar --show-error \
  -w "%{http_code}" \
  -o "${TEMP_RESPONSE_FILE}" \
  -X POST \
  -F "file=@${file}" \
  "${API_URL}" \
  > "${TEMP_HTTP_CODE_FILE}"
# 注意：没有 2>&1，进度条会实时显示在终端

HTTP_CODE=$(cat "${TEMP_HTTP_CODE_FILE}" | grep -oE '[0-9]{3}' | tail -n1)
RESPONSE_BODY=$(cat "${TEMP_RESPONSE_FILE}")
rm -f "${TEMP_RESPONSE_FILE}" "${TEMP_HTTP_CODE_FILE}"
```

## 关键要点

1. **不要使用 `2>&1` 重定向 stderr**
   - 进度条输出到 stderr，需要直接显示在终端
   - `2>&1` 会将 stderr 重定向到 stdout，导致进度条被缓冲

2. **分别处理 stdout 和 stderr**
   - stdout（HTTP状态码）→ 重定向到文件
   - stderr（进度条）→ 直接输出到终端
   - 响应体 → 通过 `-o` 保存到文件

3. **使用临时文件存储输出**
   - HTTP 状态码：通过 `-w "%{http_code}"` 输出到 stdout，重定向到文件
   - 响应体：通过 `-o` 保存到文件

## 在 GitHub Actions 中的表现

- **进度条会实时显示在日志中**
- 可以看到上传百分比（如 `48.2%`）和进度条（`##################################`）
- 虽然输出很多行，但这是**合理的**，因为：
  - ✅ 可以实时了解上传进度
  - ✅ 可以通过时间戳预判超时时间
  - ✅ 不会出现"卡住"的假象
  - ✅ 每个百分比更新都有时间戳，便于分析上传速度

### 实际输出示例

```
   ⏳ 上传中（最大超时: 500秒）...

#=#=#                                                                          

##O#-#                                                                         

##O=#  #                                                                       

#=#=-#  #                                                                      

                                                                           0.3%

                                                                           0.6%

                                                                           1.0%

...

##################################                                        47.9%

##################################                                        48.2%
```

**注意**：虽然输出很多行，但这是正常的，因为：
- 每个百分比更新都会输出一行
- 这样可以清楚地看到上传进度
- 结合时间戳可以判断上传速度
- 如果长时间没有更新，可以判断是否超时

## 相关文件

- `.github/workflows/sync-to-gitee.yml`: Gitee Release 文件上传
- 文件上传步骤：`Upload assets to Gitee Release`
- 配置文件上传步骤：`Sync update config to Gitee`

## 历史问题

- 之前使用 `2>&1` 导致进度条无法实时显示
- 用户反馈"25%就再也没有变化了"
- 修复后进度条可以正常实时显示
- **重要**：不要因为输出多行而使用 `2>&1` 或 `-s`（静默模式），这会隐藏进度信息

