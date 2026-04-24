#!/system/bin/sh

MODID="chroot_env"
MODDIR="/data/adb/modules/$MODID"
STATE_DIR="/data/adb/chroot-env"
ROOTFS_DIR="$STATE_DIR/rootfs"
CACHE_DIR="$STATE_DIR/cache"
DOWNLOAD_DIR="$STATE_DIR/downloads"
LOG_DIR="$STATE_DIR/logs"
RUN_DIR="$STATE_DIR/run"
PERSIST_DIR="$STATE_DIR/persist"
CONFIG_FILE="$STATE_DIR/config.env"
ROOTFS_MARKER="$STATE_DIR/.rootfs-ready"
TOOLCHAIN_MARKER="$STATE_DIR/.toolchain-ready"
HERMES_MARKER="$STATE_DIR/.hermes-ready"
PROVIDER_SETUP_MARKER="$STATE_DIR/.hermes-provider-setup-ready"
VERSION_CACHE="$STATE_DIR/hermes.version"
HOST_RUNTIME_DIR="$STATE_DIR/host"
HOST_RUNTIME_VERSIONS_DIR="$HOST_RUNTIME_DIR/versions"
HOST_RUNTIME_CURRENT_DIR="$HOST_RUNTIME_DIR/current"
HOST_RUNTIME_VERSION_FILE="$HOST_RUNTIME_DIR/current.version"
HOST_RUNTIME_SOURCE_DIR="$MODDIR/system/etc/chroot-env"
HOST_RUNTIME_SOURCE_ENTRY="$HOST_RUNTIME_SOURCE_DIR/chroot-env-host"

DEFAULT_ROOTFS_URL="https://cdimage.ubuntu.com/ubuntu-base/releases/26.04/release/ubuntu-base-26.04-base-arm64.tar.gz"

DEFAULT_HERMES_PREFIX="/root/.local"
DEFAULT_HERMES_VERSION="latest"
DEFAULT_HERMES_NODE_VERSION="25"

DEFAULT_GATEWAY_PORT="8642"
DEFAULT_AUTO_START="0"
DEFAULT_RUNIT_AUTO_START="0"
DEFAULT_RUNIT_SERVICES=""
DEFAULT_TOOLCHAIN_PACKAGES="ca-certificates curl wget git bash xz-utils gnupg dirmngr unzip zip procps psmisc runit file less nano iproute2 iputils-ping python3 python3-dev python3-pip python3-venv build-essential cmake ninja-build pkg-config clang lld libc++-dev libc++abi-dev libssl-dev"
CHROOT_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

export PATH="/system/bin:/system/xbin:/vendor/bin:/sbin:/bin:$PATH"

msg() {
  echo "[chroot-env] $*"
}

err() {
  echo "[chroot-env] $*" >&2
}

die() {
  err "$*"
  exit 1
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

ensure_root() {
  [ "$(id -u)" = "0" ] || die "需要 root 权限，请通过 su 执行"
}

ensure_arm64() {
  ABI="$(getprop ro.product.cpu.abi 2>/dev/null)"
  case "$ABI" in
    arm64*|*arm64*)
      ;;
    *)
      die "不支持的 ABI: ${ABI:-unknown}，此模块仅支持 arm64"
      ;;
  esac
}

ensure_dirs() {
  mkdir -p "$STATE_DIR" "$CACHE_DIR" "$DOWNLOAD_DIR" "$LOG_DIR" "$RUN_DIR" "$PERSIST_DIR" "$PERSIST_DIR/hermes-home" "$HOST_RUNTIME_DIR" "$HOST_RUNTIME_VERSIONS_DIR"
}

ensure_config() {
  ensure_dirs
  [ -f "$CONFIG_FILE" ] && return 0
  cat >"$CONFIG_FILE" <<EOF
ROOTFS_URL="$DEFAULT_ROOTFS_URL"
HERMES_PREFIX="$DEFAULT_HERMES_PREFIX"
HERMES_VERSION="$DEFAULT_HERMES_VERSION"
HERMES_NODE_VERSION="$DEFAULT_HERMES_NODE_VERSION"
TOOLCHAIN_PACKAGES="$DEFAULT_TOOLCHAIN_PACKAGES"
GATEWAY_PORT="$DEFAULT_GATEWAY_PORT"
AUTO_START="$DEFAULT_AUTO_START"
RUNIT_AUTO_START="$DEFAULT_RUNIT_AUTO_START"
RUNIT_SERVICES="$DEFAULT_RUNIT_SERVICES"
EOF
}

load_config() {
  ROOTFS_URL="$DEFAULT_ROOTFS_URL"
  HERMES_PREFIX="$DEFAULT_HERMES_PREFIX"
  HERMES_VERSION="$DEFAULT_HERMES_VERSION"
  HERMES_NODE_VERSION="$DEFAULT_HERMES_NODE_VERSION"
  TOOLCHAIN_PACKAGES="$DEFAULT_TOOLCHAIN_PACKAGES"
  GATEWAY_PORT="$DEFAULT_GATEWAY_PORT"
  AUTO_START="$DEFAULT_AUTO_START"
  RUNIT_AUTO_START="$DEFAULT_RUNIT_AUTO_START"
  RUNIT_SERVICES="$DEFAULT_RUNIT_SERVICES"
  [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

  # 历史配置自动补齐 runit，保持模块内置 runit 能力
  if ! printf ' %s ' "$TOOLCHAIN_PACKAGES" | grep -q ' runit '; then
    TOOLCHAIN_PACKAGES="$TOOLCHAIN_PACKAGES runit"
    if [ -f "$CONFIG_FILE" ]; then
      ESC_TOOLCHAIN_PACKAGES="$(printf '%s' "$TOOLCHAIN_PACKAGES" | sed 's/[\/&]/\\&/g')"
      sed -i 's/^TOOLCHAIN_PACKAGES=.*/TOOLCHAIN_PACKAGES="'"$ESC_TOOLCHAIN_PACKAGES"'"/' "$CONFIG_FILE" 2>/dev/null || true
    fi
  fi

  # 历史默认值 0.10.0 自动迁移到 latest，保持安装/更新默认跟随上游最新版本
  case "$HERMES_VERSION" in
    0.10.0|v0.10.0)
      HERMES_VERSION="$DEFAULT_HERMES_VERSION"
      if [ -f "$CONFIG_FILE" ]; then
        sed -i 's/^HERMES_VERSION=.*/HERMES_VERSION="'"$DEFAULT_HERMES_VERSION"'"/' "$CONFIG_FILE" 2>/dev/null || true
      fi
      ;;
  esac

  # Hermes API Server 官方默认端口为 8642，这里把旧的 18789 自动修正回默认值
  if [ "$GATEWAY_PORT" = "18789" ]; then
    GATEWAY_PORT="$DEFAULT_GATEWAY_PORT"
    if [ -f "$CONFIG_FILE" ]; then
      sed -i 's/^GATEWAY_PORT=.*/GATEWAY_PORT="'"$DEFAULT_GATEWAY_PORT"'"/' "$CONFIG_FILE" 2>/dev/null || true
    fi
  fi
}

module_prop_value() {
  KEY="$1"
  [ -f "$MODDIR/module.prop" ] || return 1
  sed -n "s/^$KEY=//p" "$MODDIR/module.prop" | head -n 1
}

host_runtime_version_label() {
  HOST_MOD_VER="$(module_prop_value version 2>/dev/null)"
  HOST_MOD_VC="$(module_prop_value versionCode 2>/dev/null)"
  [ -n "$HOST_MOD_VER" ] || HOST_MOD_VER="unknown"
  [ -n "$HOST_MOD_VC" ] || HOST_MOD_VC="0"
  printf 'v%s-%s\n' "$HOST_MOD_VER" "$HOST_MOD_VC" | tr -c 'A-Za-z0-9._-' '_'
}

host_runtime_version_dir() {
  echo "$HOST_RUNTIME_VERSIONS_DIR/$(host_runtime_version_label)"
}

host_runtime_entrypoint() {
  echo "$HOST_RUNTIME_CURRENT_DIR/chroot-env-host"
}

host_runtime_current_target() {
  if [ -L "$HOST_RUNTIME_CURRENT_DIR" ]; then
    if has_cmd readlink; then
      TARGET="$(readlink "$HOST_RUNTIME_CURRENT_DIR" 2>/dev/null)"
      [ -n "$TARGET" ] && {
        echo "$TARGET"
        return 0
      }
    fi
    echo "$HOST_RUNTIME_CURRENT_DIR (符号链接)"
    return 0
  fi

  if [ -d "$HOST_RUNTIME_CURRENT_DIR" ] || [ -f "$(host_runtime_entrypoint)" ]; then
    echo "$HOST_RUNTIME_CURRENT_DIR"
    return 0
  fi

  echo "待同步"
}

host_runtime_activate_version() {
  VERSION_DIR="$1"
  rm -rf "$HOST_RUNTIME_CURRENT_DIR"
  if has_cmd ln; then
    ln -s "$VERSION_DIR" "$HOST_RUNTIME_CURRENT_DIR" 2>/dev/null && return 0
  fi
  mkdir -p "$HOST_RUNTIME_CURRENT_DIR" || return 1
  cp -af "$VERSION_DIR"/. "$HOST_RUNTIME_CURRENT_DIR"/ || return 1
}

sync_host_runtime() {
  ensure_dirs
  mkdir -p "$HOST_RUNTIME_VERSIONS_DIR" || die "无法创建宿主运行版本目录"

  VERSION_LABEL="$(host_runtime_version_label)"
  VERSION_DIR="$(host_runtime_version_dir)"
  mkdir -p "$VERSION_DIR/lib" || die "无法创建宿主运行目录：$VERSION_DIR"

  [ -f "$MODDIR/lib/common.sh" ] || die "模块内缺少 common.sh"
  [ -f "$MODDIR/lib/bootstrap.sh" ] || die "模块内缺少 bootstrap.sh"
  [ -f "$HOST_RUNTIME_SOURCE_ENTRY" ] || die "模块内缺少 host 入口脚本"

  cp -af "$MODDIR/lib/common.sh" "$VERSION_DIR/lib/common.sh" || die "复制 common.sh 到宿主运行目录失败"
  cp -af "$MODDIR/lib/bootstrap.sh" "$VERSION_DIR/lib/bootstrap.sh" || die "复制 bootstrap.sh 到宿主运行目录失败"
  cp -af "$HOST_RUNTIME_SOURCE_ENTRY" "$VERSION_DIR/chroot-env-host" || die "复制 host 入口脚本失败"
  chmod 0755 "$VERSION_DIR/lib/common.sh" "$VERSION_DIR/lib/bootstrap.sh" "$VERSION_DIR/chroot-env-host" 2>/dev/null || true
  printf '%s\n' "$VERSION_LABEL" >"$VERSION_DIR/runtime.version"

  host_runtime_activate_version "$VERSION_DIR" || die "切换当前宿主运行版本失败"
  printf '%s\n' "$VERSION_LABEL" >"$HOST_RUNTIME_VERSION_FILE"
}

prepare_host_runtime() {
  EXPECTED="$(host_runtime_version_label)"
  if [ -x "$(host_runtime_entrypoint)" ] && [ -f "$HOST_RUNTIME_VERSION_FILE" ]; then
    CURRENT="$(head -n 1 "$HOST_RUNTIME_VERSION_FILE" 2>/dev/null | tr -d '\r')"
    [ "$CURRENT" = "$EXPECTED" ] && return 0
  fi
  sync_host_runtime
}

download_file() {
  URL="$1"
  OUT="$2"
  TMP="$OUT.part"
  rm -f "$TMP"
  if has_cmd wget; then
    wget -O "$TMP" "$URL" || return 1
  elif [ -x /data/adb/magisk/busybox ]; then
    /data/adb/magisk/busybox wget -O "$TMP" "$URL" || return 1
  elif has_cmd curl; then
    curl -L --fail --retry 3 -o "$TMP" "$URL" || return 1
  else
    die "系统中没有可用的下载工具（curl/wget）"
  fi
  mv -f "$TMP" "$OUT"
}

has_download_tool() {
  has_cmd wget && return 0
  [ -x /data/adb/magisk/busybox ] && return 0
  has_cmd curl && return 0
  return 1
}

download_tool_name() {
  if has_cmd wget; then
    echo "wget"
  elif [ -x /data/adb/magisk/busybox ]; then
    echo "magisk busybox wget"
  elif has_cmd curl; then
    echo "curl"
  else
    echo "无"
  fi
}

probe_https_headers() {
  URL="$1"
  if has_cmd wget && wget --help 2>&1 | grep -q -- '--spider'; then
    wget --spider -q "$URL" >/dev/null 2>&1
    return $?
  fi
  if [ -x /data/adb/magisk/busybox ] && /data/adb/magisk/busybox wget --help 2>&1 | grep -q -- '--spider'; then
    /data/adb/magisk/busybox wget --spider -q "$URL" >/dev/null 2>&1
    return $?
  fi
  if has_cmd curl; then
    curl -I -L --fail --retry 1 --connect-timeout 10 --max-time 20 -o /dev/null "$URL" >/dev/null 2>&1
    return $?
  fi
  return 2
}

probe_https_small_download() {
  URL="$1"
  OUT="$STATE_DIR/preflight-download.tmp"
  rm -f "$OUT" "$OUT.part"
  if has_cmd wget; then
    wget -q -O "$OUT" "$URL" >/dev/null 2>&1 || {
      rm -f "$OUT"
      return 1
    }
    rm -f "$OUT"
    return 0
  fi
  if [ -x /data/adb/magisk/busybox ]; then
    /data/adb/magisk/busybox wget -q -O "$OUT" "$URL" >/dev/null 2>&1 || {
      rm -f "$OUT"
      return 1
    }
    rm -f "$OUT"
    return 0
  fi
  if has_cmd curl; then
    curl -L --fail --retry 1 --connect-timeout 10 --max-time 20 -o "$OUT.part" "$URL" >/dev/null 2>&1 || {
      rm -f "$OUT" "$OUT.part"
      return 1
    }
    mv -f "$OUT.part" "$OUT"
    rm -f "$OUT"
    return 0
  fi
  return 1
}

available_kb() {
  TARGET="$1"
  df -Pk "$TARGET" 2>/dev/null | tail -n 1 | sed 's/^ *//; s/  */ /g' | cut -d ' ' -f4
}

print_preflight_item() {
  LEVEL="$1"
  LABEL="$2"
  DETAIL="$3"
  case "$LEVEL" in
    ok)
      echo "[预检] [通过] $LABEL${DETAIL:+: $DETAIL}"
      ;;
    warn)
      echo "[预检] [警告] $LABEL${DETAIL:+: $DETAIL}"
      ;;
    fail)
      echo "[预检] [失败] $LABEL${DETAIL:+: $DETAIL}"
      ;;
  esac
}

run_preflight() {
  ensure_root
  ensure_arm64
  ensure_dirs
  ensure_config
  load_config

  PREFLIGHT_FAILED=0
  PREFLIGHT_WARN=0
  PREFLIGHT_TMP="$STATE_DIR/preflight"
  PREFLIGHT_MIN_KB=4194304
  PREFLIGHT_NVM_INSTALL_URL="https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh"
  PREFLIGHT_NODE_SMALL_URL="https://nodejs.org/dist/index.json"
  PREFLIGHT_HERMES_SMALL_URL="https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh"

  echo "[预检] 开始检查宿主环境"
  print_preflight_item ok "root 权限" "已获取"
  print_preflight_item ok "CPU 架构" "arm64"

  if has_cmd chroot; then
    print_preflight_item ok "chroot 命令" "$(command -v chroot)"
  else
    print_preflight_item fail "chroot 命令" "当前系统找不到 chroot"
    PREFLIGHT_FAILED=1
  fi

  if has_cmd mount; then
    print_preflight_item ok "mount 命令" "$(command -v mount)"
  else
    print_preflight_item fail "mount 命令" "当前系统找不到 mount"
    PREFLIGHT_FAILED=1
  fi

  if has_cmd umount; then
    print_preflight_item ok "umount 命令" "$(command -v umount)"
  else
    print_preflight_item fail "umount 命令" "当前系统找不到 umount"
    PREFLIGHT_FAILED=1
  fi

  if has_cmd tar; then
    print_preflight_item ok "tar 命令" "$(command -v tar)"
  else
    print_preflight_item fail "tar 命令" "当前系统找不到 tar"
    PREFLIGHT_FAILED=1
  fi

  if has_download_tool; then
    print_preflight_item ok "下载工具" "$(download_tool_name)"
  else
    print_preflight_item fail "下载工具" "系统中没有可用的 curl/wget"
    PREFLIGHT_FAILED=1
  fi

  mkdir -p "$PREFLIGHT_TMP/src" "$PREFLIGHT_TMP/dst" "$PREFLIGHT_TMP/proc" "$PREFLIGHT_TMP/sys" || {
    print_preflight_item fail "状态目录" "无法创建 $PREFLIGHT_TMP"
    PREFLIGHT_FAILED=1
  }

  if [ "$PREFLIGHT_FAILED" = "0" ]; then
    : >"$PREFLIGHT_TMP/src/write.test" 2>/dev/null
    if [ $? = 0 ]; then
      rm -f "$PREFLIGHT_TMP/src/write.test"
      print_preflight_item ok "状态目录写入" "$STATE_DIR"
    else
      print_preflight_item fail "状态目录写入" "无法写入 $STATE_DIR"
      PREFLIGHT_FAILED=1
    fi
  fi

  if [ "$PREFLIGHT_FAILED" = "0" ]; then
    mount -o bind "$PREFLIGHT_TMP/src" "$PREFLIGHT_TMP/dst" >/dev/null 2>&1
    if [ $? = 0 ]; then
      print_preflight_item ok "bind mount" "宿主支持"
      umount -l "$PREFLIGHT_TMP/dst" >/dev/null 2>&1 || true
    else
      print_preflight_item fail "bind mount" "当前内核或 SELinux 拒绝 bind 挂载"
      PREFLIGHT_FAILED=1
    fi
  fi

  if [ "$PREFLIGHT_FAILED" = "0" ]; then
    mount -t proc proc "$PREFLIGHT_TMP/proc" >/dev/null 2>&1
    if [ $? = 0 ]; then
      print_preflight_item ok "proc 挂载" "宿主支持"
      umount -l "$PREFLIGHT_TMP/proc" >/dev/null 2>&1 || true
    else
      print_preflight_item fail "proc 挂载" "无法挂载 proc"
      PREFLIGHT_FAILED=1
    fi
  fi

  if [ "$PREFLIGHT_FAILED" = "0" ]; then
    mount -t sysfs sys "$PREFLIGHT_TMP/sys" >/dev/null 2>&1
    if [ $? = 0 ]; then
      print_preflight_item ok "sysfs 挂载" "宿主支持"
      umount -l "$PREFLIGHT_TMP/sys" >/dev/null 2>&1 || true
    else
      print_preflight_item fail "sysfs 挂载" "无法挂载 sysfs"
      PREFLIGHT_FAILED=1
    fi
  fi

  PREFLIGHT_AVAIL_KB="$(available_kb "$STATE_DIR")"
  if [ -n "$PREFLIGHT_AVAIL_KB" ]; then
    PREFLIGHT_AVAIL_MB=$((PREFLIGHT_AVAIL_KB / 1024))
    if [ "$PREFLIGHT_AVAIL_KB" -ge "$PREFLIGHT_MIN_KB" ]; then
      print_preflight_item ok "可用空间" "${PREFLIGHT_AVAIL_MB} MB"
    else
      print_preflight_item fail "可用空间" "仅剩 ${PREFLIGHT_AVAIL_MB} MB，建议至少 4096 MB"
      PREFLIGHT_FAILED=1
    fi
  else
    print_preflight_item warn "可用空间" "无法读取剩余空间"
    PREFLIGHT_WARN=1
  fi

  if has_download_tool; then
    PREFLIGHT_ROOTFS_HEADER_RC=2
    PREFLIGHT_NODE_HEADER_RC=2
    probe_https_headers "$ROOTFS_URL"
    PREFLIGHT_ROOTFS_HEADER_RC=$?
    probe_https_headers "$PREFLIGHT_NVM_INSTALL_URL"
    PREFLIGHT_NODE_HEADER_RC=$?

    if [ "$PREFLIGHT_ROOTFS_HEADER_RC" = "0" ]; then
      print_preflight_item ok "RootFS 下载地址" "$ROOTFS_URL"
    elif [ "$PREFLIGHT_ROOTFS_HEADER_RC" = "2" ]; then
      print_preflight_item warn "RootFS 下载地址" "当前下载工具不支持头部探测，跳过精确校验"
      PREFLIGHT_WARN=1
    else
      print_preflight_item fail "RootFS 下载地址" "无法访问 $ROOTFS_URL"
      PREFLIGHT_FAILED=1
    fi

    if [ "$PREFLIGHT_NODE_HEADER_RC" = "0" ]; then
      print_preflight_item ok "nvm 安装脚本地址" "$PREFLIGHT_NVM_INSTALL_URL"
    elif [ "$PREFLIGHT_NODE_HEADER_RC" = "2" ]; then
      print_preflight_item warn "nvm 安装脚本地址" "当前下载工具不支持头部探测，改做基础 HTTPS 校验"
      PREFLIGHT_WARN=1
      if probe_https_small_download "$PREFLIGHT_NODE_SMALL_URL" && probe_https_small_download "$PREFLIGHT_HERMES_SMALL_URL"; then
        print_preflight_item ok "基础 HTTPS 下载" "nvm / Node.js / Hermes 站点可访问"
      else
        print_preflight_item fail "基础 HTTPS 下载" "无法完成基础 HTTPS 下载"
        PREFLIGHT_FAILED=1
      fi
    else
      print_preflight_item fail "nvm 安装脚本地址" "无法访问 $PREFLIGHT_NVM_INSTALL_URL"
      PREFLIGHT_FAILED=1
    fi
  fi

  rm -rf "$PREFLIGHT_TMP" >/dev/null 2>&1 || true

  if [ "$PREFLIGHT_FAILED" = "0" ]; then
    if [ "$PREFLIGHT_WARN" = "0" ]; then
      msg "预检通过，可以继续执行 init"
    else
      msg "预检通过，但存在警告，建议先处理后再执行 init"
    fi
    return 0
  fi

  die "预检未通过，请根据上面的失败项先处理环境问题"
}

mounted_at() {
  grep -qs " $1 " /proc/mounts
}

mount_bind() {
  SRC="$1"
  DST="$2"
  mkdir -p "$DST"
  mounted_at "$DST" && return 0
  mount -o bind "$SRC" "$DST"
}

mount_named_fs() {
  FSTYPE="$1"
  SRC="$2"
  DST="$3"
  OPTS="$4"
  mkdir -p "$DST"
  mounted_at "$DST" && return 0
  if [ -n "$OPTS" ]; then
    mount -t "$FSTYPE" -o "$OPTS" "$SRC" "$DST"
  else
    mount -t "$FSTYPE" "$SRC" "$DST"
  fi
}

refresh_resolver() {
  mkdir -p "$ROOTFS_DIR/etc"
  : >"$ROOTFS_DIR/etc/resolv.conf"
  for KEY in net.dns1 net.dns2 net.dns3 net.dns4; do
    NS="$(getprop "$KEY" 2>/dev/null)"
    [ -n "$NS" ] && echo "nameserver $NS" >>"$ROOTFS_DIR/etc/resolv.conf"
  done
  if ! grep -q "^nameserver" "$ROOTFS_DIR/etc/resolv.conf" 2>/dev/null; then
    echo "nameserver 1.1.1.1" >>"$ROOTFS_DIR/etc/resolv.conf"
    echo "nameserver 8.8.8.8" >>"$ROOTFS_DIR/etc/resolv.conf"
  fi
  [ -f "$ROOTFS_DIR/etc/hosts" ] || cat >"$ROOTFS_DIR/etc/hosts" <<EOF
127.0.0.1 localhost
::1 localhost
EOF
}

mount_chroot() {
  [ -d "$ROOTFS_DIR" ] || die "找不到 rootfs，请先执行 chroot-env init"
  ensure_dirs
  refresh_resolver
  mkdir -p "$ROOTFS_DIR"/dev "$ROOTFS_DIR"/dev/pts "$ROOTFS_DIR"/proc "$ROOTFS_DIR"/sys "$ROOTFS_DIR"/run/hermes "$ROOTFS_DIR"/var/log/hermes "$ROOTFS_DIR"/root/.hermes "$ROOTFS_DIR"/root/.local/bin
  mount_bind /dev "$ROOTFS_DIR/dev"
  mount_bind /dev/pts "$ROOTFS_DIR/dev/pts"
  mount_named_fs proc proc "$ROOTFS_DIR/proc" ""
  mount_named_fs sysfs sys "$ROOTFS_DIR/sys" ""
  mount_bind "$RUN_DIR" "$ROOTFS_DIR/run/hermes"
  mount_bind "$LOG_DIR" "$ROOTFS_DIR/var/log/hermes"
  mount_bind "$PERSIST_DIR/hermes-home" "$ROOTFS_DIR/root/.hermes"
  [ -d /sdcard ] && mount_bind /sdcard "$ROOTFS_DIR/sdcard"
}

umount_if_needed() {
  TARGET="$1"
  mounted_at "$TARGET" || return 0
  umount -l "$TARGET" 2>/dev/null
}

umount_chroot() {
  umount_if_needed "$ROOTFS_DIR/sdcard"
  umount_if_needed "$ROOTFS_DIR/root/.hermes"
  umount_if_needed "$ROOTFS_DIR/var/log/hermes"
  umount_if_needed "$ROOTFS_DIR/run/hermes"
  umount_if_needed "$ROOTFS_DIR/sys"
  umount_if_needed "$ROOTFS_DIR/proc"
  umount_if_needed "$ROOTFS_DIR/dev/pts"
  umount_if_needed "$ROOTFS_DIR/dev"
}

chroot_shell_path() {
  if [ -x "$ROOTFS_DIR/bin/bash" ]; then
    echo "/bin/bash"
  else
    echo "/bin/sh"
  fi
}

hermes_path_exports() {
  cat <<EOF
export HERMES_PREFIX="$HERMES_PREFIX"
export NVM_DIR="\$HOME/.nvm"
if [ -s "\$NVM_DIR/nvm.sh" ]; then
  . "\$NVM_DIR/nvm.sh" >/dev/null 2>&1
  nvm use default >/dev/null 2>&1 || nvm use "$HERMES_NODE_VERSION" >/dev/null 2>&1 || true
fi
export PATH="\$HOME/.local/bin:\$HOME/.cargo/bin:$CHROOT_PATH"
if [ -n "\${NVM_BIN:-}" ]; then
  export PATH="\$HOME/.local/bin:\$HOME/.cargo/bin:\$NVM_BIN:$CHROOT_PATH"
fi
EOF
}

chroot_run() {
  mount_chroot
  CMD="$1"
  chroot "$ROOTFS_DIR" /usr/bin/env -i HOME=/root TERM="${TERM:-xterm-256color}" PATH="$CHROOT_PATH" /bin/sh -c "$(hermes_path_exports)
$CMD"
}

chroot_interactive_shell() {
  mount_chroot
  SHELL_BIN="$(chroot_shell_path)"
  chroot "$ROOTFS_DIR" /usr/bin/env -i HOME=/root TERM="${TERM:-xterm-256color}" PATH="$CHROOT_PATH" "$SHELL_BIN" -c "$(hermes_path_exports)
exec $SHELL_BIN"
}

gateway_pid() {
  cat "$RUN_DIR/gateway.pid" 2>/dev/null
}

pid_cmdline() {
  PID="$1"
  [ -n "$PID" ] || return 1
  [ -r "/proc/$PID/cmdline" ] || return 1
  tr '\000' ' ' <"/proc/$PID/cmdline" 2>/dev/null
}

gateway_listener_pid() {
  ensure_config
  load_config

  if has_cmd ss; then
    PID="$(ss -lntp 2>/dev/null | grep "[.:]$GATEWAY_PORT " | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' | head -n 1)"
  elif has_cmd netstat; then
    PID="$(netstat -lntp 2>/dev/null | grep "[.:]$GATEWAY_PORT " | sed -n 's/.*[[:space:]]\([0-9][0-9]*\)\/.*/\1/p' | head -n 1)"
  else
    return 2
  fi

  [ -n "$PID" ] || return 1
  printf '%s\n' "$PID"
}

gateway_pid_matches() {
  PID="$1"
  [ -n "$PID" ] || return 1
  kill -0 "$PID" 2>/dev/null || return 1
  CMDLINE="$(pid_cmdline "$PID")"
  case "$CMDLINE" in
    *hermes*gateway*|*gateway*hermes*|*hermes-agent*|*hermes*|*python*hermes*|*node*hermes*|*node*gateway*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

sync_gateway_pid_from_listener() {
  PID="$(gateway_listener_pid 2>/dev/null)"
  [ -n "$PID" ] || return 1
  kill -0 "$PID" 2>/dev/null || return 1
  printf '%s\n' "$PID" >"$RUN_DIR/gateway.pid"
  return 0
}

cleanup_stale_gateway_pid() {
  PID="$(gateway_pid)"
  [ -n "$PID" ] || {
    sync_gateway_pid_from_listener >/dev/null 2>&1 || true
    return 0
  }
  gateway_pid_matches "$PID" && return 0
  sync_gateway_pid_from_listener >/dev/null 2>&1 && return 0
  rm -f "$RUN_DIR/gateway.pid"
  return 0
}

gateway_running() {
  PID="$(gateway_pid)"
  if [ -n "$PID" ] && gateway_pid_matches "$PID"; then
    return 0
  fi
  sync_gateway_pid_from_listener >/dev/null 2>&1 && return 0
  rm -f "$RUN_DIR/gateway.pid"
  return 1
}

gateway_port_listening() {
  ensure_config
  load_config
  if has_cmd ss; then
    ss -lnt 2>/dev/null | grep -q "[.:]$GATEWAY_PORT "
    return $?
  fi
  if has_cmd netstat; then
    netstat -lnt 2>/dev/null | grep -q "[.:]$GATEWAY_PORT "
    return $?
  fi
  return 2
}

gateway_healthy() {
  gateway_port_listening || return 1
  gateway_running
}


cached_hermes_version() {
  if [ -s "$VERSION_CACHE" ]; then
    head -n 1 "$VERSION_CACHE" | tr -d '\r'
  elif [ -f "$HERMES_MARKER" ]; then
    echo "unknown"
  else
    echo "not_installed"
  fi
}

refresh_version_cache() {
  [ -f "$HERMES_MARKER" ] || return 1
  VER="$(chroot_run 'hermes --version 2>/dev/null | head -n 1' 2>/dev/null | tail -n 1 | tr -d '\r')"
  [ -n "$VER" ] || return 1
  printf '%s\n' "$VER" >"$VERSION_CACHE"
}

hermes_version_string() {
  cached_hermes_version | head -n 1 | tr '\n' ' ' | tr -s ' '
}

module_status_description() {
  ensure_dirs
  ensure_config
  load_config
  cleanup_stale_gateway_pid

  ROOTFS_STATE="未就绪"
  TOOLCHAIN_STATE="未安装"
  HERMES_STATE="未安装"
  GATEWAY_STATE="未运行"
  AUTO_FLAG="关"

  [ -f "$ROOTFS_MARKER" ] && ROOTFS_STATE="已就绪"
  [ -f "$TOOLCHAIN_MARKER" ] && TOOLCHAIN_STATE="已安装"
  [ "$AUTO_START" = "1" ] && AUTO_FLAG="开"

  if [ -f "$HERMES_MARKER" ]; then
    HERMES_STATE="已安装"
  fi
  if [ -f "$HERMES_MARKER" ] && [ -f "$PROVIDER_SETUP_MARKER" ]; then
    HERMES_STATE="Provider已配置"
  fi

  if gateway_healthy; then
    GATEWAY_STATE="运行中"
  elif gateway_running; then
    GATEWAY_STATE="进程异常"
  fi

  printf 'RootFS:%s | 工具链:%s | Hermes:%s | Hermes 服务:%s | 自启:%s' "$ROOTFS_STATE" "$TOOLCHAIN_STATE" "$HERMES_STATE" "$GATEWAY_STATE" "$AUTO_FLAG"
}

module_status_description_prop() {
  module_status_description
}

write_module_description() {
  DESC="$1"
  FILE="$2"
  [ -f "$FILE" ] || return 0
  TMP="$FILE.tmp"
  FOUND=0
  : >"$TMP"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      description=*)
        printf 'description=%s\n' "$DESC" >>"$TMP"
        FOUND=1
        ;;
      *)
        printf '%s\n' "$line" >>"$TMP"
        ;;
    esac
  done <"$FILE"
  [ "$FOUND" = "1" ] || printf 'description=%s\n' "$DESC" >>"$TMP"
  mv "$TMP" "$FILE"
}

refresh_module_status() {
  DESC="$(module_status_description_prop)"
  write_module_description "$DESC" "$MODDIR/module.prop"
  [ -f "/data/adb/modules_update/$MODID/module.prop" ] && write_module_description "$DESC" "/data/adb/modules_update/$MODID/module.prop"
}

print_status() {
  load_config
  echo "模块ID: $MODID"
  echo "运行模式: Android Host Chroot（实验性，非官方支持）"
  echo "宿主运行目录: $HOST_RUNTIME_CURRENT_DIR"
  echo "宿主运行版本: $( [ -f "$HOST_RUNTIME_VERSION_FILE" ] && head -n 1 "$HOST_RUNTIME_VERSION_FILE" | tr -d '\r' || echo 待同步 )"
  echo "宿主实际目录: $(host_runtime_current_target)"
  echo "环境来源: 在线下载部署"
  echo "RootFS 路径: $ROOTFS_DIR"
  echo "RootFS 就绪: $( [ -f "$ROOTFS_MARKER" ] && echo 是 || echo 否 )"
  echo "基础工具链: $( [ -f "$TOOLCHAIN_MARKER" ] && echo 已安装 || echo 未安装 )"
  echo "runit 开机自启: $( [ "$RUNIT_AUTO_START" = "1" ] && echo 已开启 || echo 已关闭 )"
  echo "runit 附加服务: $( [ -n "$RUNIT_SERVICES" ] && echo "$RUNIT_SERVICES" || echo 无 )"
  echo "chroot shell: chroot-env shell"
  echo "chroot exec: chroot-env exec \"<cmd>\""
  if [ -f "$ROOTFS_MARKER" ]; then
    PY_VER="$(chroot_run 'python3 -V 2>/dev/null' 2>/dev/null | tail -n 1 | tr -d '\r')"
    [ -n "$PY_VER" ] && echo "Python 版本: $PY_VER"
  fi
  if [ -f "$TOOLCHAIN_MARKER" ]; then
    NODE_VER="$(chroot_run 'node -v 2>/dev/null' 2>/dev/null | tail -n 1 | tr -d '\r')"
    NPM_VER="$(chroot_run 'npm -v 2>/dev/null' 2>/dev/null | tail -n 1 | tr -d '\r')"
    [ -n "$NODE_VER" ] && echo "Node.js 版本: $NODE_VER"
    [ -n "$NPM_VER" ] && echo "npm 版本: $NPM_VER"
  fi
  echo "Magisk 显示: $(module_status_description)"
}

print_hermes_status() {
  load_config
  cleanup_stale_gateway_pid
  if [ -f "$HERMES_MARKER" ]; then
    refresh_version_cache >/dev/null 2>&1 || true
  fi

  echo "Hermes 安装: $( [ -f "$HERMES_MARKER" ] && echo 已安装 || echo 未安装 )"
  echo "模型 / Provider 配置: $( [ -f "$PROVIDER_SETUP_MARKER" ] && echo 已完成 || echo 未完成 )"
  echo "官方完整 setup: $( [ -f "$PROVIDER_SETUP_MARKER" ] && echo 已完成 || echo 未完成 )"
  echo "API_SERVER_KEY: $( api_server_key_configured && echo 已配置 || echo 未配置 )"
  echo "Gateway 自启动: $( [ "$AUTO_START" = "1" ] && echo 已开启 || echo 已关闭 )"
  echo "Hermes API / Gateway 端口: $GATEWAY_PORT"
  if gateway_healthy; then
    echo "Hermes Gateway 运行状态: 运行中"
    echo "Hermes Gateway PID: $(gateway_pid)"
    echo "Hermes API 监听地址: 127.0.0.1"
  elif gateway_running; then
    echo "Hermes Gateway 运行状态: 进程存在但端口未就绪"
    echo "Hermes Gateway PID: $(gateway_pid)"
    echo "Hermes API 监听地址: 127.0.0.1"
  else
    echo "Hermes Gateway 运行状态: 未运行"
    echo "Hermes API 监听地址: 127.0.0.1"
  fi
  if [ -f "$HERMES_MARKER" ]; then
    HERMES_VER="$(hermes_version_string)"
    [ -n "$HERMES_VER" ] && echo "Hermes 版本: $HERMES_VER"
  fi
}
