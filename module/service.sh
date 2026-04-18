#!/system/bin/sh
. /data/adb/modules/chroot_env/lib/common.sh

BOOT_RC=0
SERVICE_LOG_FILE="$LOG_DIR/service.log"

now_ts() {
  date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date
}

log_boot() {
  LEVEL="$1"
  shift
  printf '[%s] [%s] %s\n' "$(now_ts)" "$LEVEL" "$*" >>"$SERVICE_LOG_FILE"
}

run_step() {
  STEP_NAME="$1"
  shift
  if "$@" >>"$SERVICE_LOG_FILE" 2>&1; then
    log_boot "INFO" "$STEP_NAME: ok"
    return 0
  fi
  RC=$?
  log_boot "ERROR" "$STEP_NAME: failed (rc=$RC)"
  return "$RC"
}

ensure_dirs
ensure_config
run_step "prepare_host_runtime" prepare_host_runtime || exit 1
load_config
cleanup_stale_gateway_pid
run_step "refresh_module_status(pre)" refresh_module_status || true

HOST_ENTRY="$(host_runtime_entrypoint)"
if [ "$RUNIT_AUTO_START" = "1" ]; then
  if [ -x "$HOST_ENTRY" ]; then
    run_step "runit autostart" "$HOST_ENTRY" runit autostart || BOOT_RC=1
  else
    log_boot "ERROR" "runit autostart: missing host runtime entrypoint ($HOST_ENTRY)"
    BOOT_RC=1
  fi
fi

if [ "$AUTO_START" = "1" ]; then
  if [ ! -f "$HERMES_MARKER" ]; then
    log_boot "INFO" "hermes autostart skipped: hermes marker not found"
  elif [ ! -x "$HOST_ENTRY" ]; then
    log_boot "ERROR" "hermes autostart: missing host runtime entrypoint ($HOST_ENTRY)"
    BOOT_RC=1
  else
    run_step "hermes start" "$HOST_ENTRY" hermes start || BOOT_RC=1
  fi
fi

run_step "refresh_module_status(post)" refresh_module_status || true
exit "$BOOT_RC"
