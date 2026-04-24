# Android Chroot 环境 Magisk 模块

这个模块用于在 Android 上部署一个以 `chroot` 为主的 `arm64` Linux 环境，并把 `Hermes` 作为可选附加组件接入进去。

## 模块定位

- 主体能力是 Android Host + `chroot`
- 目标架构是 `arm64`
- RootFS 通过在线下载并解压方式安装
- 初始化后可直接进入 `chroot shell` 或执行单条命令
- `Hermes` 作为 chroot 内的可选组件单独安装和管理

## 安装流程

1. 在 Magisk 中刷入模块 ZIP。
2. 重启设备。
3. 在终端中执行初始化：

```sh
su
chroot-env preflight
chroot-env init
chroot-env status
```

初始化完成后，可直接进入 chroot：

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

## runit 内置支持

模块默认会在 `packages/init` 阶段安装 `runit`，并提供以下命令：

- `chroot-env runit status`：查看 runit 安装/运行状态
- `chroot-env runit start`：启动 `runsvdir /etc/service`
- `chroot-env runit stop`：停止 `runsvdir/runsv`
- `chroot-env runit restart`：重启 runit
- `chroot-env runit enable` / `disable`：开启/关闭开机自启
- `chroot-env runit services "<svc1 svc2>"`：设置需要自动链接到 `/etc/service` 的服务列表

### 2.1 runit 是干什么的

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

## Hermes 命令映射

模块对 Hermes 相关命令做了子命名空间封装：

- `chroot-env hermes model` -> 官方 `hermes model`
- `chroot-env hermes tools` -> 官方 `hermes tools`
- `chroot-env hermes setup` -> 官方 `hermes setup`
- `chroot-env hermes start` -> 模块内后台启动封装（底层调用 `hermes gateway`）

说明：

- `chroot-env hermes status` 只显示 Hermes 相关状态。
- `chroot-env hermes update` 用于更新 Hermes Agent（按 `HERMES_VERSION`，默认 `latest`）。
- `chroot-env hermes setup` 仅执行官方完整 `hermes setup`。

## Hermes 集成

模块为 Hermes 提供了统一的命令映射，便于在 chroot 环境中完成安装、配置、诊断与启动；同时也会透传官方 Hermes 的新子命令：

- `chroot-env hermes install`
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
- 模块对 Hermes 相关流程进行了适配封装，便于在 Android chroot 场景中调用。
- `hermes install`：安装 Hermes Agent
- `hermes update`：更新 Hermes Agent（按 `HERMES_VERSION`，默认 `latest`）
- `hermes model`：进入官方 `hermes model`，配置模型与 Provider
- `hermes tools`：进入官方 `hermes tools`，配置工具能力
- `hermes setup`：执行官方完整 `hermes setup`
- `hermes gen-key`：自动生成并写入 `API_SERVER_KEY`
- `hermes doctor`：执行官方 `hermes doctor`
- `hermes start`：启动官方 `hermes gateway`

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
- Hermes 0.10.0 的 Tool Gateway 采用每个工具独立 `use_gateway` 开关，不再依赖旧的统一环境变量开关。

## 目录说明

- 模块工作目录：`/data/adb/chroot-env`
- chroot 根目录：`/data/adb/chroot-env/rootfs`
- Hermes 持久化目录：`/data/adb/chroot-env/persist/hermes-home`
- Gateway 日志目录：`/data/adb/chroot-env/logs`
