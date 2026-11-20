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
mkdir -p __ROOTFS__/dev/pts
mountpoint -q __ROOTFS__/dev/pts 2>/dev/null || mount -t devpts devpts __ROOTFS__/dev/pts
mountpoint -q __ROOTFS__/tmp || mount -t tmpfs -o size=512M tmpfs __ROOTFS__/tmp
echo "挂载就绪"
# 记录 sshd PID: chroot 内 sh 把自身 PID 写入 /.chrootctl.pid(宿主机视角即 __ROOTFS__/.chrootctl.pid),
# exec sshd 后 PID 不变, 供 status/stop 直接引用, 免去遍历 /proc 全部进程
rm -f __ROOTFS__/.chrootctl.pid
setsid chroot __ROOTFS__ /bin/sh -c 'export PATH=/usr/sbin:/usr/bin:/sbin:/bin; mkdir -p /run/sshd; echo $$ > /.chrootctl.pid; exec /usr/sbin/sshd -D -p __PORT__' </dev/null >/dev/null 2>&1 &
sleep 2
echo "启动完成"
EOS
;;
stop)
nsenter -t 1 -m -- sh -s <<'EOS'
# 优先杀记录的 sshd PID(免遍历 /proc); 仅在 PID 文件缺失时回退遍历兜底
PID=$(cat __ROOTFS__/.chrootctl.pid 2>/dev/null)
if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
  kill -9 "$PID" 2>/dev/null && echo "杀 $PID (记录sshd)"
else
  for d in /proc/[0-9]*; do
    p=${d#/proc/}
    e=$(readlink /proc/$p/exe 2>/dev/null)
    case "$e" in
      __ROOTFS__/*) kill -9 $p 2>/dev/null && echo "杀 $p";;
    esac
  done
fi
rm -f __ROOTFS__/.chrootctl.pid
sleep 1
# 卸载 rootfs 下所有挂载点。
# 注意: tmpfs(/tmp) 是新建挂载, 继承 /data 的 shared propagation(shared:73),
# 会传播到 /data/user/0 和 /data_mirror 等视角(同一 superblock 多条记录)。
# 故遍历 /proc/mounts 收集所有含 __ROOTFS__ 的挂载点逐一惰性卸载, 清干净全部视角。
for m in $(awk 'index($2,"__ROOTFS__"){print $2}' /proc/mounts); do
  umount -l "$m" 2>/dev/null
done
sleep 1
for m in $(awk 'index($2,"__ROOTFS__"){print $2}' /proc/mounts); do
  umount -l "$m" 2>/dev/null
done
echo "停止完成"
EOS
;;
status)
nsenter -t 1 -m -- sh -s <<'EOS'
# 不再遍历 /proc 全部进程(每个 readlink /proc/PID/exe 极慢, 几百进程可达十几秒);
# 直接读启动时记录的 PID, kill -0 判活, 毫秒级
PID=$(cat __ROOTFS__/.chrootctl.pid 2>/dev/null)
ALIVE=0
[ -n "$PID" ] && kill -0 "$PID" 2>/dev/null && ALIVE=1
M=0
for mp in dev proc sys dev/pts tmp; do
  # dev/pts 在未 start 时可能不存在(proot-distro 原始 dev 为空), 先判存在避免 mountpoint 报错
  [ -e __ROOTFS__/$mp ] && mountpoint -q __ROOTFS__/$mp 2>/dev/null && M=$((M+1))
done
P=$(ss -tln | grep -c ":__PORT__ ")
echo "挂载=$M/5 __PORT__监听=$P sshd(PID=$PID)存活=$ALIVE"
EOS
;;
esac