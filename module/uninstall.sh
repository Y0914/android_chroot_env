#!/system/bin/sh
STATE_DIR="/data/adb/chroot-env"
RUN_DIR="$STATE_DIR/run"
HOST_RUNTIME_DIR="$STATE_DIR/host"
HOST_RUNTIME_CURRENT_DIR="$HOST_RUNTIME_DIR/current"
HOST_RUNTIME_VERSION_FILE="$HOST_RUNTIME_DIR/current.version"
HOST_RUNTIME_VERSIONS_DIR="$HOST_RUNTIME_DIR/versions"

# Preserve /data/adb/chroot-env by default so the user does not lose Gateway state.
rm -f "$RUN_DIR/gateway.pid" 2>/dev/null

if [ -L "$HOST_RUNTIME_CURRENT_DIR" ] || [ -e "$HOST_RUNTIME_CURRENT_DIR" ]; then
  rm -rf "$HOST_RUNTIME_CURRENT_DIR" 2>/dev/null
fi
rm -f "$HOST_RUNTIME_VERSION_FILE" 2>/dev/null

if [ -d "$HOST_RUNTIME_VERSIONS_DIR" ] && [ -z "$(ls -A "$HOST_RUNTIME_VERSIONS_DIR" 2>/dev/null)" ]; then
  rmdir "$HOST_RUNTIME_VERSIONS_DIR" 2>/dev/null || true
fi
if [ -d "$HOST_RUNTIME_DIR" ] && [ -z "$(ls -A "$HOST_RUNTIME_DIR" 2>/dev/null)" ]; then
  rmdir "$HOST_RUNTIME_DIR" 2>/dev/null || true
fi

exit 0