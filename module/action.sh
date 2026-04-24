#!/system/bin/sh
. /data/adb/modules/chroot_env/lib/common.sh

ensure_dirs
ensure_config
prepare_host_runtime >/dev/null 2>&1 || true
load_config
cleanup_stale_gateway_pid
refresh_module_status

echo "当前缓存状态: $(module_status_description)"
echo "当前宿主运行版本: $( [ -f "$HOST_RUNTIME_VERSION_FILE" ] && head -n 1 "$HOST_RUNTIME_VERSION_FILE" | tr -d '\r' || echo 待同步 )"
echo "说明: 这里显示的是最近一次刷新后的状态，不会主动挂载 chroot。"