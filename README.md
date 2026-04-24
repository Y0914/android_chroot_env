# Android Chroot 环境 Magisk 模块

重要提示：本 Magisk 模块的主要代码、脚本与整体工程内容由 AI 辅助编程生成与整理，并在实际设备与使用场景中持续迭代。使用者在部署、修改或二次分发前，应自行审阅实现细节，并结合自身设备环境完成充分验证。

`android_chroot_env` 是一个面向 Android 设备的 Magisk 模块，用于部署和管理一个基于 `chroot` 的 `arm64` Linux 用户空间环境，并提供对 Hermes 的可选集成支持。

该项目的目标是为 Android 设备提供一个相对清晰、可维护、可扩展的 chroot 运行环境，使其既可以作为通用 Linux 用户空间使用，也可以在需要时接入 Hermes Agent 工作流。

## 当前版本

- 模块名称：`Android Chroot 环境（实验性）`
- 模块 ID：`chroot_env`
- 当前版本：`v1.3.1`
- `versionCode`：`5`
- 目标架构：`arm64`
- 默认 RootFS 来源：Ubuntu Base 26.04 release arm64

当前 Magisk 模块描述字段会动态刷新，初始值类似：

```text
RootFS:未就绪 | 工具链:未安装 | Hermes:未安装 | Hermes 服务:未运行 | 自启:关
```

## 项目特性

- 基于 Magisk 的 Android Chroot 环境部署
- 支持在线下载并初始化 RootFS
- 提供统一命令入口管理 chroot 生命周期
- 支持进入 chroot shell 或执行单条命令
- 内置 `runit` 支持与服务自启开关
- 提供 Hermes 子命名空间封装
- 支持 Hermes API Server / Gateway 相关配置
- 支持通过模块脚本控制开机自启动行为
- 仓库直接跟踪 Magisk 模块源码，而不是只保存发布 ZIP

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

## 常用命令

```sh
su -c chroot-env preflight
su -c chroot-env rootfs
su -c chroot-env packages
su -c chroot-env init
su -c chroot-env status
su -c chroot-env shell
su -c 'chroot-env exec "uname -a"'
su -c 'chroot-env exec "python3 -V"'
su -c 'chroot-env exec "node -v"'
su -c chroot-env runit status
su -c chroot-env runit start
su -c chroot-env runit enable
su -c 'chroot-env runit services "sshd cron"'
su -c chroot-env umount
```

## 核心能力

### 1. Chroot 环境管理

模块提供以下能力：

- 运行前检查（`preflight`）
- RootFS 下载与初始化
- 基础工具链安装（含 `python3` / `node` / `npm` / `runit`）
- 环境状态查看
- 进入 chroot shell
- 在 chroot 中执行单条命令
- 卸载或清理挂载

### 2. runit 内置支持

模块默认会在 `packages/init` 阶段安装 `runit`，并提供以下命令：

- `chroot-env runit status`：查看 runit 安装/运行状态
- `chroot-env runit start`：启动 `runsvdir /etc/service`
- `chroot-env runit stop`：停止 `runsvdir/runsv`
- `chroot-env runit restart`：重启 runit
- `chroot-env runit enable` / `disable`：开启/关闭开机自启
- `chroot-env runit services "<svc1 svc2>"`：设置需要自动链接到 `/etc/service` 的服务列表

#### 2.1 runit 是干什么的

`runit` 是一个轻量级的服务管理器，用来在 chroot 里持续托管长期运行的后台服务。

在这个模块里，`runit` 主要负责：

- 启动并维持 `sshd`、Hermes 相关服务或其它自定义后台进程
- 在服务异常退出后自动重新拉起
- 统一管理 `/etc/service` 下启用的服务
- 配合模块的开机逻辑实现 chroot 内服务自启动

简单理解：

- `chroot` 提供 Linux 用户空间环境
- `runit` 负责这个环境里的“后台服务持续运行”

如果没有 `runit`，很多需要常驻的服务只能手动启动，设备重启或进程退出后也不会自动恢复。

### 3. Hermes 集成

模块为 Hermes 提供统一命令映射，便于在 chroot 环境中完成安装、配置、诊断与启动；同时也会透传官方 Hermes 的新子命令：

- `chroot-env hermes install`
- `chroot-env hermes update`
- `chroot-env hermes model`
- `chroot-env hermes tools`
- `chroot-env hermes setup`
- `chroot-env hermes gen-key`
- `chroot-env hermes doctor`
- `chroot-env hermes start`
- `chroot-env hermes status`
- 其它官方子命令（如 `config` / `gateway` / `skills` / `memory` / `mcp` / `profile`）会原样透传

推荐安装与启动流程：

```sh
su
chroot-env hermes install
chroot-env hermes setup
chroot-env hermes gen-key
chroot-env hermes start
chroot-env hermes status
chroot-env hermes enable
```

说明：

- Hermes 为可选组件，不影响 chroot 主体功能的独立使用。
- `chroot-env hermes start` 走的是模块内后台启动封装；如需使用官方网关子命令，可直接使用 `chroot-env hermes gateway ...`。
- `chroot-env hermes status` 只显示 Hermes 相关状态。
- `chroot-env hermes update` 用于更新 Hermes Agent（按 `HERMES_VERSION`，默认 `latest`）。
- `chroot-env hermes setup` 仅执行官方完整 `hermes setup`。

## API Server

Hermes 的 API Server 依赖 `.env` 中的以下配置：

```env
API_SERVER_ENABLED=true
API_SERVER_KEY=change-me-local-dev
API_SERVER_PORT=8642
API_SERVER_HOST=127.0.0.1
```

模块默认网关端口：

```sh
GATEWAY_PORT="8642"
```

说明：

- `chroot-env hermes start` 启动前会检查 `API_SERVER_KEY`
- 可直接执行 `chroot-env hermes gen-key` 自动生成并写入密钥
- API Server 环境文件路径为 `/data/adb/chroot-env/persist/hermes-home/.env`
- 启动时会向 `hermes gateway` 注入 `API_SERVER_ENABLED=true`、`API_SERVER_HOST=127.0.0.1`、`API_SERVER_PORT=$GATEWAY_PORT`

## 状态命令

- `chroot-env status`：查看 chroot 主环境状态
- `chroot-env hermes status`：查看 Hermes 安装、配置、API Server、Gateway 运行状态

## 配置文件

模块主配置文件：

```text
/data/adb/chroot-env/config.env
```

当前默认值：

```sh
ROOTFS_URL="https://cdimage.ubuntu.com/ubuntu-base/releases/26.04/release/ubuntu-base-26.04-base-arm64.tar.gz"
HERMES_PREFIX="/root/.local"
HERMES_VERSION="latest"
HERMES_NODE_VERSION="25"
TOOLCHAIN_PACKAGES="ca-certificates curl wget git bash xz-utils gnupg dirmngr unzip zip procps psmisc runit file less nano iproute2 iputils-ping python3 python3-dev python3-pip python3-venv build-essential cmake ninja-build pkg-config clang lld libc++-dev libc++abi-dev libssl-dev"
GATEWAY_PORT="8642"
AUTO_START="0"
RUNIT_AUTO_START="0"
RUNIT_SERVICES=""
```

## Hermes 版本策略

- 模块默认 `HERMES_VERSION="latest"`，安装/更新时跟随 Hermes 官方最新版本。
- 若你需要其它版本，可在 `config.env` 中手动修改 `HERMES_VERSION`（支持 `latest`、`0.10.0`、`0.9.0`、或直接填写官方分支/标签名）。
- 历史默认值 `0.10.0` 会自动迁移为 `latest`。

## 仓库源码结构

仓库现在直接跟踪 Magisk 模块源码，位于：

- `module/`

其中包含：

- `module/lib/`：核心宿主脚本
- `module/system/`：模块安装后的系统路径内容
- `module/META-INF/`：Magisk/Recovery 安装入口文件
- `module/module.prop`：模块元数据
- `module/README.module.md`：模块内说明文档

如需重新打包发布 zip，可在仓库中基于 `module/` 目录构建。

## 目录结构说明

- 模块工作目录：`/data/adb/chroot-env`
- chroot 根目录：`/data/adb/chroot-env/rootfs`
- Hermes 持久化目录：`/data/adb/chroot-env/persist/hermes-home`
- Gateway 日志目录：`/data/adb/chroot-env/logs`
- 模块目录：`/data/adb/modules/chroot_env`

## 发布与下载

当前发布包请见 GitHub Releases：

- `android_chroot_env-v1.3.1-magisk.zip`

Release 页面：

- https://github.com/Y0914/android_chroot_env/releases

## 注意事项

- 本项目当前版本仍带有实验性特征。
- 使用前请确保设备已获取 Root，并正确安装 Magisk。
- 建议在熟悉 Android Root / chroot / Linux 用户空间基本操作的前提下使用。
- 当前工具链安装流程在 `lib/bootstrap.sh` 中已去掉安装后的 `toolchain_installed` 二次校验，安装成败主要依赖安装过程本身返回值。
- 如需扩展开机自启动、SSH、自定义服务等能力，可在现有模块脚本基础上进一步定制。

## 已知限制

- 当前默认流程面向 `arm64` 设备与对应 RootFS 资源。
- 依赖 Magisk、Root 权限以及可用的 Android / 内核环境；不同机型兼容性可能存在差异。
- 开机自启动、挂载、网络、SSH 与 Hermes 相关行为仍可能受设备环境影响。
- 当前版本以实用性优先，自动化测试与跨设备验证仍有补充空间。

## Roadmap

后续计划：

- 仅个人使用模块分享
- 基本功能已正常可用
- 如需其他功能请使用 AI 自动添加

## 许可证与变更记录

- 许可证：见 `LICENSE`
- 版本变更：见 `CHANGELOG.md`
