# 发布检查清单

## 发布前检查

- [ ] 版本号已更新（使用 `./scripts/version.sh bump`）
- [ ] 版本号已同步到 pubspec.yaml（使用 `./scripts/version.sh sync`）
- [ ] 代码已测试通过
- [ ] 所有更改已提交

## 发布步骤

1. **提交代码更改**
   ```bash
   git add .
   git commit -m "准备发布版本 X.X.X"
   git push origin main
   ```

2. **创建并推送版本标签**
   ```bash
   git tag v1.0.5  # 替换为实际版本号
   git push origin v1.0.5
   ```

3. **等待 GitHub Actions 完成**
   - 查看 Actions 页面：https://github.com/shichao402/HelloKnightRemoteCam/actions
   - 等待所有构建完成（约 10-20 分钟）

4. **验证发布结果**
   - [ ] GitHub Release 已创建
   - [ ] 所有平台的构建产物已上传
   - [ ] 更新配置文件已更新到 GitHub 仓库

## 发布后验证

- [ ] 在客户端测试更新检查功能
- [ ] 验证下载链接可访问
- [ ] 检查版本号是否正确

## 故障排除

如果发布失败：
1. 查看 GitHub Actions 日志
2. 检查版本号是否正确
3. 检查网络连接
