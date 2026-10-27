#!/usr/bin/env bash
# MicroFlow 项目服务入口；不启动或修改 VPN、网络及其他系统服务。
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SERVICE=microflow-web.service
UNIT_PATH="/etc/systemd/system/${SERVICE}"
MARKER='# Managed by MicroFlow setup.sh v1'
ACTION="${1:-start}"
if (($#)); then shift; fi
NO_BUILD=0
SKIP_TESTS=0
for arg in "$@"; do
    case "$arg" in
        --no-build) NO_BUILD=1 ;;
        --skip-tests) SKIP_TESTS=1 ;;
        *) echo "未知参数：$arg" >&2; exit 2 ;;
    esac
done

die() { echo "错误：$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "缺少命令 $1；请先安装依赖。"; }
as_root() { if ((EUID == 0)); then "$@"; else sudo -- "$@"; fi; }
help_text() {
    echo "用法：bash setup.sh [start|restart|stop|status|logs|test|print-unit|help] [--no-build] [--skip-tests]"
    echo "默认 start：本地构建、回归检查、安装并启动 systemd 服务，退出 SSH 后仍运行。"
    echo "环境变量：MICROFLOW_PORT(18080)、MICROFLOW_THREADS(4)、MICROFLOW_BUILD_DIR、"
    echo "MICROFLOW_MODEL、MICROFLOW_BIG_CORES、MICROFLOW_BUILD_JOBS(4)。"
    echo "Web 页面、/health、/predict、/visualize 和 C++ 推理共用一个进程。"
}
case "$ACTION" in
    help|-h|--help) help_text; exit 0 ;;
    start|restart|stop|status|logs|test|print-unit) ;;
    *) help_text >&2; exit 2 ;;
esac

BUILD_DIR="${MICROFLOW_BUILD_DIR:-${ROOT_DIR}/build-rock4d}"
if [[ -z ${MICROFLOW_BUILD_DIR:-} && -f ${ROOT_DIR}/build-opt3/CMakeCache.txt ]]; then
    BUILD_DIR="${ROOT_DIR}/build-opt3"
fi
MODEL="${MICROFLOW_MODEL:-${ROOT_DIR}/models/mnist_improved.mflow}"
PORT="${MICROFLOW_PORT:-18080}"
THREADS="${MICROFLOW_THREADS:-4}"
JOBS="${MICROFLOW_BUILD_JOBS:-4}"
for number in "$PORT" "$THREADS" "$JOBS"; do
    [[ $number =~ ^[1-9][0-9]{0,4}$ ]] || die "端口、线程和构建并行数必须是正整数。"
done
((PORT >= 1024 && PORT <= 65535)) || die "服务端口必须为 1024..65535。"
((THREADS <= 64 && JOBS <= 64)) || die "线程数和构建并行数不能超过 64。"
[[ $BUILD_DIR = /* ]] || BUILD_DIR="${ROOT_DIR}/${BUILD_DIR}"
[[ $MODEL = /* ]] || MODEL="${ROOT_DIR}/${MODEL}"
RUN_USER="${SUDO_USER:-$(id -un)}"
if [[ $RUN_USER = root ]]; then RUN_USER="$(stat -c %U "$ROOT_DIR")"; fi
[[ $RUN_USER != root ]] || die "请由项目普通用户运行，不将推理服务设为 root。"
RUN_GROUP="$(id -gn "$RUN_USER")"
CPUS="${MICROFLOW_BIG_CORES:-}"
if [[ ! ${MICROFLOW_BIG_CORES+x} && $(uname -m) = aarch64 ]] && command -v taskset >/dev/null && taskset -c 4-7 true 2>/dev/null; then
    CPUS=4-7
fi
if [[ -n $CPUS ]]; then
    [[ $CPUS =~ ^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$ ]] || die "CPU 列表格式错误。"
    need taskset
    taskset -c "$CPUS" true 2>/dev/null || die "CPU 列表不在当前可用 CPU 范围内。"
fi
for value in "$ROOT_DIR" "$BUILD_DIR" "$MODEL"; do
    [[ $value != *$'\n'* && $value != *$'\r'* ]] || die "路径不能包含换行。"
done

# systemd 字符串转义，包括路径中的空格、引号、反斜线和 % specifier。
unit_quote() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//%/%%}"
    printf '"%s"' "$value"
}
print_unit() {
    printf '%s\n' "$MARKER" '[Unit]' 'Description=MicroFlow handwritten-digit Web and inference service' 'After=network.target' 'StartLimitIntervalSec=60' 'StartLimitBurst=3' '' '[Service]' 'Type=simple'
    printf 'User=%s\nGroup=%s\nWorkingDirectory=' "$RUN_USER" "$RUN_GROUP"
    printf '%s\nExecStart=' "${ROOT_DIR//%/%%}"
    unit_quote "$BUILD_DIR/web_demo"; printf ' '; unit_quote "$MODEL"
    printf ' %s %s\n' "$PORT" "$THREADS"
    printf 'Environment=OMP_NUM_THREADS=%s\nEnvironment=OMP_PROC_BIND=true\nEnvironment=OMP_PLACES=cores\nEnvironment=MICROFLOW_HTTP_PORT=%s\n' "$THREADS" "$PORT"
    if [[ -n $CPUS ]]; then printf 'CPUAffinity=%s\n' "${CPUS//,/ }"; fi
    printf '%s\n' 'Restart=on-failure' 'RestartSec=3' 'TimeoutStopSec=10' 'KillSignal=SIGTERM' 'NoNewPrivileges=true' 'PrivateTmp=true' 'ProtectSystem=strict' 'ProtectHome=read-only' 'UMask=0027' 'StandardOutput=journal' 'StandardError=journal' '' '[Install]' 'WantedBy=multi-user.target'
}
managed_unit() {
    [[ -f $UNIT_PATH ]] && grep -Fxq "$MARKER" "$UNIT_PATH"
}
require_managed() {
    managed_unit || die "$UNIT_PATH 不是本脚本管理的服务，未执行停止或覆盖。"
}
urls() {
    echo "电脑浏览器访问（选择可达的板端 IPv4 地址）："
    ip -o -4 address show up | awk -v port="$PORT" '$2 !~ /^(lo|docker|br-|veth|tailscale)/ {split($4,a,"/"); printf "  http://%s:%s/  [%s]\n",a[1],port,$2}'
    echo "  http://rock4d.local:${PORT}/  [依赖局域网名称解析]"
}
health() {
    need python3
    python3 "$ROOT_DIR/tools/check_service.py" "http://127.0.0.1:${PORT}" "$ROOT_DIR/image/test_input.bin" "$THREADS"
}
build_and_test() {
    [[ -r $MODEL ]] || die "模型不存在或不可读：$MODEL（不会联网训练或下载模型）。"
    need cmake
    if ((NO_BUILD == 0)); then
        cmake -S "$ROOT_DIR" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release
        cmake --build "$BUILD_DIR" -j"$JOBS"
    fi
    [[ -x $BUILD_DIR/web_demo ]] || die "没有可执行文件：$BUILD_DIR/web_demo"
    if ((SKIP_TESTS == 0)); then
        need ctest
        [[ -f $BUILD_DIR/CTestTestfile.cmake ]] || die "构建目录缺少 CTest 注册。"
        ctest --test-dir "$BUILD_DIR" --output-on-failure
    fi
}
case "$ACTION" in
    print-unit) print_unit ;;
    test) build_and_test ;;
    stop) require_managed; as_root systemctl disable --now "$SERVICE"; echo 'MicroFlow 已停止并取消开机启动；未修改其他服务。' ;;
    logs) require_managed; as_root journalctl -u "$SERVICE" -n 80 -f ;;
    status)
        require_managed
        systemctl --no-pager --full status "$SERVICE" || exit $?
        # 读取已安装服务的实际端口，而不是调用者当前的默认端口。
        PORT="$(systemctl show "$SERVICE" -p Environment --value | grep -oE 'MICROFLOW_HTTP_PORT=[0-9]+' | cut -d= -f2)"
        [[ -n $PORT ]] || die '已安装服务缺少端口记录。'
        curl --noproxy '*' --max-time 3 -fsS "http://127.0.0.1:${PORT}/health"; echo; urls
        ;;
    start|restart)
        need systemctl; need systemd-analyze; need ip; need python3; need curl; need ss
        [[ -d /run/systemd/system ]] || die '需要正在运行的 systemd（不支持容器内直接安装）。'
        if [[ -e $UNIT_PATH ]]; then require_managed; fi
        # 只操作本项目服务，不杀占用同一端口的其他程序。
        python3 - "$PORT" <<'PY'
import socket,subprocess,sys
p=int(sys.argv[1])
s=socket.socket()
try:
    s.bind(('0.0.0.0',p))
except OSError:
    r=subprocess.run(['systemctl','is-active','--quiet','microflow-web.service'])
    pid=subprocess.check_output(['systemctl','show','microflow-web.service','-p','MainPID','--value'],text=True).strip()
    listeners=subprocess.check_output(['ss','-H','-ltnp',f'sport = :{p}'],text=True).splitlines()
    if r.returncode or pid=='0' or not listeners or any(f'pid={pid},' not in line for line in listeners):
        sys.exit(f'端口 {p} 被其他进程占用；未停止该进程。')
finally:
    s.close()
PY
        build_and_test
        stage_dir="$(mktemp -d)"
        stage="$stage_dir/$SERVICE"
        trap 'rm -f -- "$stage"; rmdir -- "$stage_dir"' EXIT
        print_unit >"$stage"
        systemd-analyze verify "$stage"
        # 不存在同名服务才安装；内容未变时不打断正在运行的服务。
        changed=1
        if [[ -f $UNIT_PATH ]] && cmp -s "$stage" "$UNIT_PATH"; then changed=0; fi
        if ((changed)); then as_root install -m 0644 "$stage" "$UNIT_PATH"; fi
        as_root systemctl daemon-reload
        as_root systemctl enable "$SERVICE"
        if [[ $ACTION = restart ]] || ((changed)); then
            as_root systemctl restart "$SERVICE"
        else
            as_root systemctl start "$SERVICE"
        fi
        if ! health; then
            as_root journalctl -u "$SERVICE" -n 40 --no-pager
            die '启动验收失败，请检查日志；未关闭防火墙或重写网络配置。'
        fi
        echo "MicroFlow 已启动，已启用开机自启；关闭 SSH 不会停止服务。"
        urls
        echo "状态：bash setup.sh status    日志：bash setup.sh logs    停止：bash setup.sh stop"
        ;;
esac
