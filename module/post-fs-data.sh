#!/system/bin/sh
. /data/adb/modules/chroot_env/lib/common.sh

ensure_dirs
ensure_config
prepare_host_runtime >/dev/null 2>&1 || true
cleanup_stale_gateway_pid
refresh_module_status >/dev/null 2>&1
exit 0