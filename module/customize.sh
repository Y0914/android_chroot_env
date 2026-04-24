SKIPUNZIP=0

ui_print "- 正在安装 Android Chroot 环境模块"
ui_print "- 首次初始化需手动执行：su -c chroot-env init"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/system/bin/chroot-env" 0 0 0755
set_perm "$MODPATH/system/etc/chroot-env/chroot-env-host" 0 0 0755
set_perm "$MODPATH/lib/common.sh" 0 0 0755
set_perm "$MODPATH/lib/bootstrap.sh" 0 0 0755
