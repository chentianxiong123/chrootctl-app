#!/system/bin/sh
# ChrootCtl 内联脚本 — 由 app 注入 ROOTFS/PORT/ACTION 后用 su 执行
# 关键1: Android 每个 app 有独立 mount namespace, 看不到其他 app 私有目录的挂载
#        必须 nsenter -t 1 -m 进 pid1 全局 ns
# 关键2: 全部逻辑放单引号 heredoc, 内部 $ 不被 app 外层 shell 提前展开(只换占位符)
ROOTFS='__ROOTFS__'
PORT=__PORT__
ACTION=__ACTION__

case "$ACTION" in
start)
nsenter -t 1 -m -- sh -s <<'EOS'
PID=$(ss -tlnp 2>/dev/null | grep ":__PORT__" | grep -oE 'pid=[0-9]+' | head -1 | grep -oE '[0-9]+')
[ -n "$PID" ] && { kill "$PID" 2>/dev/null; sleep 1; echo "清占用 $PID"; }
mountpoint -q __ROOTFS__/dev     || mount --bind /dev  __ROOTFS__/dev
mountpoint -q __ROOTFS__/proc    || mount --bind /proc __ROOTFS__/proc
mountpoint -q __ROOTFS__/sys     || mount --bind /sys  __ROOTFS__/sys
mountpoint -q __ROOTFS__/dev/pts || mount -t devpts devpts __ROOTFS__/dev/pts
mountpoint -q __ROOTFS__/tmp || mount -t tmpfs -o size=512M tmpfs __ROOTFS__/tmp
echo "挂载就绪"
setsid chroot __ROOTFS__ /bin/sh -c 'export PATH=/usr/sbin:/usr/bin:/sbin:/bin; mkdir -p /run/sshd; exec /usr/sbin/sshd -D -p __PORT__' </dev/null >/dev/null 2>&1 &
sleep 2
echo "启动完成"
EOS
;;
stop)
nsenter -t 1 -m -- sh -s <<'EOS'
for d in /proc/[0-9]*; do
  p=${d#/proc/}
  e=$(readlink /proc/$p/exe 2>/dev/null)
  case "$e" in
    __ROOTFS__/*) kill -9 $p 2>/dev/null && echo "杀 $p";;
  esac
done
sleep 2
umount __ROOTFS__/dev/pts __ROOTFS__/dev __ROOTFS__/proc __ROOTFS__/sys 2>/dev/null
umount -l __ROOTFS__/dev/pts __ROOTFS__/dev __ROOTFS__/proc __ROOTFS__/sys 2>/dev/null
sleep 1
umount -l __ROOTFS__/dev/pts __ROOTFS__/dev __ROOTFS__/proc __ROOTFS__/sys 2>/dev/null
echo "停止完成"
EOS
;;
status)
nsenter -t 1 -m -- sh -s <<'EOS'
M=$(cat /proc/mounts | grep -c rootfs)
P=$(ss -tln | grep -c ":__PORT__ ")
n=0
for d in /proc/[0-9]*; do
  p=${d#/proc/}
  e=$(readlink /proc/$p/exe 2>/dev/null)
  case "$e" in __ROOTFS__/*) n=$((n+1));; esac
done
echo "挂载=$M  __PORT__监听=$P  rootfs进程=$n"
EOS
;;
esac