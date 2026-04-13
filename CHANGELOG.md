# 更新日志

本文档用于记录本项目的重要版本变更。

本项目参考 Keep a Changelog 的结构整理，并在合适场景下使用语义化风格的版本标签。

## [v1.2.0] - 2026-04-13

### 新增
- 初始化公开 GitHub 仓库
- 补充正式风格的项目 README
- 发布 `v1.2.0` GitHub Release
- 上传 Release 安装包：`android_chroot_env-v1.2.0-release.zip`
- 提供面向 Android chroot 环境部署的 Magisk 模块封装
- 提供 RootFS 下载与初始化流程
- 提供 `chroot-env` 命令入口，支持 shell、exec、status、init、umount 等操作
- 提供 Hermes 集成入口，支持安装、配置、模型/工具设置、诊断与启动流程
- 提供 API Server / Gateway 相关配置支持
- 提供通过模块脚本实现的开机启动钩子能力

### 说明
- 当前目标架构为 `arm64`
- 默认 RootFS 来源为 Ubuntu Base 26.04 beta arm64
- 当前版本仍属于实验性发布，更适合熟悉 Magisk、Root 与 chroot 工作流的用户使用
