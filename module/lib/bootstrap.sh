#!/system/bin/sh
BOOTSTRAP_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$BOOTSTRAP_DIR/common.sh"

rootfs_installed() {
  [ -d "$ROOTFS_DIR/usr" ] || return 1
  [ -x "$ROOTFS_DIR/bin/sh" ] || return 1
  return 0
}

toolchain_installed() {
  rootfs_installed || return 1
  chroot_run 'command -v python3 >/dev/null 2>&1 && command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 && command -v runsvdir >/dev/null 2>&1' >/dev/null 2>&1
}

hermes_installed() {
  rootfs_installed || return 1
  chroot_run '[ -x /root/.local/bin/hermes ] && /root/.local/bin/hermes --version >/dev/null 2>&1' >/dev/null 2>&1
}

sync_install_markers() {
  rootfs_installed && touch "$ROOTFS_MARKER"
  toolchain_installed && touch "$TOOLCHAIN_MARKER"
}

prepare_rootfs() {
  ensure_root
  ensure_arm64
  ensure_dirs
  ensure_config
  load_config

  if rootfs_installed; then
    touch "$ROOTFS_MARKER"
    msg "rootfs 已准备完成"
    return 0
  fi

  TMPDIR="$STATE_DIR/rootfs.tmp"
  rm -rf "$TMPDIR"
  mkdir -p "$TMPDIR"

  ARCHIVE="$DOWNLOAD_DIR/$(basename "$ROOTFS_URL")"

  if [ ! -f "$ARCHIVE" ]; then
    msg "正在在线下载 rootfs：$ROOTFS_URL"
    download_file "$ROOTFS_URL" "$ARCHIVE" || die "下载 rootfs 失败"
  else
    msg "使用缓存的 rootfs 压缩包：$ARCHIVE"
  fi

  tar -xpf "$ARCHIVE" -C "$TMPDIR" || die "解压 rootfs 压缩包失败"
  [ -x "$TMPDIR/bin/sh" ] || die "下载的压缩包看起来不是有效的 rootfs"

  rm -rf "$ROOTFS_DIR"
  mv "$TMPDIR" "$ROOTFS_DIR" || die "移动 rootfs 到目标目录失败"

  refresh_resolver
  touch "$ROOTFS_MARKER"
  msg "rootfs 已准备完成：$ROOTFS_DIR"
}

install_toolchain() {
  ensure_root
  ensure_arm64
  ensure_dirs
  ensure_config
  load_config
  rootfs_installed || prepare_rootfs
  touch "$ROOTFS_MARKER"

  if toolchain_installed; then
    touch "$TOOLCHAIN_MARKER"
    msg "工具链已安装"
    return 0
  fi

  msg "正在在线安装 Linux 工具链、runit 和 Node.js 运行环境"
  chroot_run "export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y $TOOLCHAIN_PACKAGES
update-ca-certificates || true
export NVM_DIR="\$HOME/.nvm"
mkdir -p "\$NVM_DIR"
wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
. "\$NVM_DIR/nvm.sh"
nvm install $HERMES_NODE_VERSION
nvm alias default $HERMES_NODE_VERSION
node -v
npm -v" || die "安装基础工具链或 Node.js 失败"
  touch "$TOOLCHAIN_MARKER"
}

init_chroot_env() {
  ensure_root
  ensure_arm64
  ensure_dirs
  ensure_config
  load_config

  sync_install_markers
  if [ -f "$ROOTFS_MARKER" ] && [ -f "$TOOLCHAIN_MARKER" ]; then
    msg "chroot 环境已安装，跳过二次安装"
    return 0
  fi

  prepare_rootfs
  install_toolchain
  msg "chroot init 完成"
}

hermes_target_ref() {
  case "$HERMES_VERSION" in
    ""|latest|main)
      echo ""
      ;;
    0.10.0|v0.10.0)
      echo "v2026.4.16"
      ;;
    0.9.0|v0.9.0)
      echo "v2026.4.13"
      ;;
    *)
      echo "$HERMES_VERSION"
      ;;
  esac
}

install_hermes_by_version() {
  TARGET_REF="$1"
  if [ -n "$TARGET_REF" ]; then
    ESCAPED_REF="$(printf "%s" "$TARGET_REF" | sed "s/'/'\\\\''/g")"
    chroot_run "TARGET_REF='$ESCAPED_REF'
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash -s -- --skip-setup --branch \"\$TARGET_REF\" --force"
  else
    chroot_run 'curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash -s -- --skip-setup'
  fi
}

install_hermes() {
  ensure_root
  ensure_config
  load_config
  [ -f "$ROOTFS_MARKER" ] || prepare_rootfs
  [ -f "$TOOLCHAIN_MARKER" ] || install_toolchain
  TARGET_REF="$(hermes_target_ref)"

  if hermes_installed; then
    touch "$HERMES_MARKER"
    refresh_version_cache >/dev/null 2>&1 || true
    msg "Hermes 已安装"
    return 0
  fi

  if [ -n "$TARGET_REF" ]; then
    msg "正在安装 Hermes Agent（目标版本：$HERMES_VERSION，标签：$TARGET_REF）"
  else
    msg "正在安装 Hermes Agent（目标版本：latest）"
  fi
  install_hermes_by_version "$TARGET_REF" || die "安装 Hermes 失败"

  hermes_installed || die "Hermes 安装完成但校验失败（/root/.local/bin/hermes --version）"
  touch "$HERMES_MARKER"
  refresh_version_cache >/dev/null 2>&1 || true
}

update_hermes() {
  ensure_root
  ensure_config
  load_config
  TARGET_REF="$(hermes_target_ref)"
  hermes_installed || install_hermes

  if [ -n "$TARGET_REF" ]; then
    msg "正在更新 Hermes Agent（目标版本：$HERMES_VERSION，标签：$TARGET_REF）"
    install_hermes_by_version "$TARGET_REF" || die "更新 Hermes 失败"
  else
    msg "正在更新 Hermes Agent（目标版本：latest）"
    chroot_run 'hermes update' || die "更新 Hermes 失败"
  fi

  touch "$HERMES_MARKER"
  refresh_version_cache >/dev/null 2>&1 || true
}

case "$1" in
  rootfs)
    prepare_rootfs
    ;;
  packages)
    install_toolchain
    ;;
  hermes)
    install_hermes
    ;;
  init|"")
    init_chroot_env
    ;;
  update)
    update_hermes
    ;;
  *)
    die "未知的引导动作：$1"
    ;;
esac
