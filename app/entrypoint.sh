#!/bin/bash
set -e

DEVICECODE_FILE="/app/data/.devicecode_${APP_USER}"
RESTART_AT_FILE="/tmp/ctyun_restart_at"
RESTART_FLAG_FILE="/tmp/ctyun_restart_triggered"

if [ -z "$DEVICECODE" ]; then
    if [ -f "$DEVICECODE_FILE" ]; then
        export DEVICECODE=$(cat "$DEVICECODE_FILE")
        echo "[*] 读取到已保存的 DEVICECODE: $DEVICECODE"
    else
        export DEVICECODE="web_$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)"
        echo "$DEVICECODE" > "$DEVICECODE_FILE"
        echo "[*] 首次启动，已生成并持久化 DEVICECODE: $DEVICECODE"
    fi
else
    echo "[*] 检测到手动传入的 DEVICECODE: $DEVICECODE"
fi

env >> /etc/environment

service cron start
echo "[*] Cron 定时服务已启动。"

set +e

echo "[*] 启动进程守护模式..."

should_restart_ctyun_now() {
    if [ ! -f "$RESTART_AT_FILE" ]; then
        return 1
    fi

    local restart_at
    restart_at=$(tr -d '[:space:]' < "$RESTART_AT_FILE" 2>/dev/null)
    if ! [[ "$restart_at" =~ ^[0-9]+$ ]]; then
        echo "[!] 检测到无效的重启计划文件，已忽略并清理。"
        rm -f "$RESTART_AT_FILE"
        return 1
    fi

    local now
    now=$(date +%s)
    [ "$now" -ge "$restart_at" ]
}

run_ctyun_with_watch() {
    local duration="$1"

    rm -f "$RESTART_FLAG_FILE"

    # 后台看门狗只负责监视重启计划。
    # 注意：主程序必须留在前台运行，否则 bash 会把后台任务的 stdin 重定向到
    # /dev/null，CtYun.dll 检测到输入不是终端后会直接放弃，无法输入短信验证码。
    (
        while true; do
            if should_restart_ctyun_now; then
                echo "[*] 检测到兑换成功后的重启计划已到时，准备重启 CtYun.dll。"
                : > "$RESTART_FLAG_FILE"
                rm -f "$RESTART_AT_FILE"
                pkill -f "dotnet CtYun.dll" 2>/dev/null || true
                break
            fi
            sleep 2
        done
    ) &
    local watcher_pid=$!

    timeout --foreground "$duration" dotnet CtYun.dll
    local exit_code=$?

    kill "$watcher_pid" 2>/dev/null || true
    wait "$watcher_pid" 2>/dev/null || true

    if [ -f "$RESTART_FLAG_FILE" ]; then
        rm -f "$RESTART_FLAG_FILE"
        return 200
    fi
    return "$exit_code"
}

# 开启无限循环，接管程序的生命周期
while true; do
    echo "======================================================"
    echo "[*] 启动 CtYun.dll..."
    run_ctyun_with_watch 2m
    sleep 10
    run_ctyun_with_watch 24h

    # 获取上方进程退出时的状态码
    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 200 ]; then
        echo "[*] 已按兑换计划完成重启。"
    elif [ $EXIT_CODE -eq 124 ]; then
        echo "[!] 触发定时机制：程序已连续运行 24 小时，执行强制重启。"
    else
        echo "[!] CtYun.dll 进程已退出 (退出码: $EXIT_CODE)。可能正在等待开机或发生了异常。"
    fi

    echo "[*] 容器挂起中，将在 2 分钟 (120秒) 后重新启动程序，请等待..."
    sleep 120

done
