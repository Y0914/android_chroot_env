# Android Chroot 环境 Magisk 模块

`android_chroot_env` 是一个面向 Android 设备的 Magisk 模块，用于部署和管理一个基于 `chroot` 的 `arm64` Linux 用户空间环境，并提供对 Hermes 的可选集成支持。

该项目的目标是为 Android 设备提供一个相对清晰、可维护、可扩展的 chroot 运行环境，使其既可以作为通用 Linux 用户空间使用，也可以在需要时接入 Hermes Agent 工作流。

## 项目特性

- 基于 Magisk 的 Android Chroot 环境部署
- 支持在线下载并初始化 RootFS
- 提供统一命令入口管理 chroot 生命周期
- 支持进入 chroot shell 或执行单条命令
- 提供 Hermes 子命名空间封装
- 支持 API Server / Gateway 相关配置
- 支持通过模块脚本控制开机自启动行为

## 核心能力

### 1. Chroot 环境管理

模块提供以下能力：
- 运行前检查
- RootFS 下载与初始化
- 环境状态查看
- 进入 chroot shell
- 在 chroot 中执行命令
- 卸载或清理挂载

常用示例：

```sh
su -c chroot-env preflight
su -c chroot-env rootfs
su -c chroot-env init
su -c chroot-env status
su -c chroot-env shell
su -c 'chroot-env exec "uname -a"'
su -c 'chroot-env exec "python3 -V"'
su -c chroot-env umount
```

### 2. Hermes 集成

模块为 Hermes 提供了统一的命令映射，便于在 chroot 环境中完成安装、配置、诊断与启动：

- `chroot-env hermes install`
- `chroot-env hermes model`
- `chroot-env hermes tools`
- `chroot-env hermes setup`
- `chroot-env hermes gen-key`
- `chroot-env hermes doctor`
- `chroot-env hermes start`
- `chroot-env hermes status`

说明：
- Hermes 为可选组件，不影响 chroot 主体功能的独立使用。
- 模块对 Hermes 相关流程进行了适配封装，便于在 Android chroot 场景中调用。

## 安装方式

1. 下载 Release 页面中的模块 ZIP
2. 在 Magisk 中刷入该 ZIP
3. 重启设备
4. 使用 root 权限执行初始化：

```sh
su
chroot-env preflight
chroot-env init
chroot-env status
```

初始化完成后，可通过以下命令进入 chroot：

```sh
su
chroot-env shell
```

## 首次使用 Hermes 的推荐流程

```sh
su
chroot-env hermes install
chroot-env hermes model
chroot-env hermes tools
chroot-env hermes setup
chroot-env hermes gen-key
chroot-env hermes doctor
chroot-env hermes start
chroot-env hermes status
```

## 配置概览

模块主配置文件：

```text
/data/adb/chroot-env/config.env
```

典型配置项包括：
- RootFS 下载地址
- Hermes 安装前缀
- Hermes 版本与 Node 版本
- 工具链安装包列表
- Gateway 端口
- AUTO_START 开关

## 目录结构说明

- 模块工作目录：`/data/adb/chroot-env`
- chroot 根目录：`/data/adb/chroot-env/rootfs`
- Hermes 持久化目录：`/data/adb/chroot-env/persist/hermes-home`
- 日志目录：`/data/adb/chroot-env/logs`
- 模块目录：`/data/adb/modules/chroot_env`

## 发布与下载

当前发布包请见 GitHub Releases：

- `android_chroot_env-v1.2.0-release.zip`

Release 页面：
- https://github.com/Y0914/android_chroot_env/releases

## 版本信息

- 当前版本：`v1.2.0`
- 目标架构：`arm64`
- 默认 RootFS 来源：Ubuntu Base 26.04 beta arm64
- 发布形式：Magisk 模块安装包

## 注意事项

- 本项目当前版本仍带有实验性特征。
- 使用前请确保设备已获取 Root，并正确安装 Magisk。
- 建议在熟悉 Android Root / chroot / Linux 用户空间基本操作的前提下使用。
- 如需扩展开机自启动、SSH、自定义服务等能力，可在现有模块脚本基础上进一步定制。

## 已知限制

- 当前默认流程面向 `arm64` 设备与对应 RootFS 资源。
- 依赖 Magisk、Root 权限以及可用的 Android / 内核环境；不同机型兼容性可能存在差异。
- 开机自启动、挂载、网络、SSH 与 Hermes 相关行为仍可能受设备环境影响。
- 当前版本以实用性优先，自动化测试与跨设备验证仍有补充空间。

## Roadmap

后续计划可包括但不限于：

- 改进初始化与失败恢复流程
- 增强 RootFS 管理与可配置能力
- 完善 SSH、自启动与后台服务管理体验
- 补充更多日志、诊断与调试工具
- 优化 Hermes 集成与升级兼容性
- 增加更完整的文档、示例与多设备测试结果

## 贡献与变更记录

- 贡献说明：见 `CONTRIBUTING.md`
- 许可证：见 `LICENSE`
- 版本变更：见 `CHANGELOG.md`
