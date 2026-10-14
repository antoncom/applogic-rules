#!/bin/sh

INITFILE=/etc/init.d/applogic
SERVICE_PID_FILE=/var/run/applogic.pid
APP=$0
APP_LUA=/usr/lib/lua/applogic/app.lua
APP_LUA_BIN=/usr/bin/lua
RETVAL=0


usage() {
    echo "Usage: $APP [ COMMAND [ OPTIONS ] ]"
    echo "Without any command Applogic will be run in the foreground without debug mode"
    echo
    echo "Commands are:"
    echo "    start|stop|restart|reload     controlling the daemon"
    echo "    list                          show list of active rules"
    echo "    debug [RULE [VAR...]]         run RULE in debug mode (default: overview),"
    echo "                                  show up to 5 variables VAR"
    echo "    debug perf [legend]           CPU / time / memory per rule and operator,"
    echo "                                  legend - explain the table columns"
    echo "    help                          show this and exit"
}

callinit() {
    [ -x "$INITFILE" ] || {
        echo "No init file '$INITFILE'"
        RETVAL=1
        return
    }
    exec "$INITFILE" "$1"
}

# Выключить режим отладки в конфиге.
# Вызывается при обычном старте и при любом завершении отладочного сеанса,
# чтобы прибор никогда не остался в тяжёлом режиме debug.
stop_debug() {
    uci set applogic.debug_mode.enable='0'
    uci set applogic.debug_mode.level='ERROR'
    uci -q delete applogic.debug_mode.rule
    uci -q delete applogic.debug_mode.showvar
    uci -q delete applogic.debug_mode.shownode
    uci commit applogic
}

# Обычный запуск (так стартует сервис через procd): отладка всегда выключена
run() {
    stop_debug

    "$APP_LUA_BIN" "$APP_LUA" &
    PID=$!
    trap 'kill $PID 2>/dev/null' INT TERM

    wait $PID
    RETVAL=$?
}

list() {
    ubus call applogic list | sort
    RETVAL=$?
}

# Отладочный запуск в терминале: applogic debug [RULE [VAR...]]
debug() {
    RULE=${1:-overview}
    [ $# -gt 0 ] && shift

    applogic stop
    uci set applogic.debug_mode.enable='1'
    uci set applogic.debug_mode.rule="$RULE"

    # perf: отладку узлов не включаем - сбор отладочных данных исказил бы замеры
    case "$RULE" in
        perf|cpu) uci set applogic.debug_mode.enable='0' ;;
    esac

    # drop shownodes left over from the previous debug session
    # (Lua читает список узлов из applogic.debug_mode.shownode, см. src/node/debug_cli.lua)
    uci -q delete applogic.debug_mode.showvar
    uci -q delete applogic.debug_mode.shownode
    for VAR in "$@"; do
        uci add_list applogic.debug_mode.shownode="$VAR"
    done
    uci commit applogic

    sleep 1

    # Не exec: после завершения Lua-процесса (Ctrl+C, закрытие терминала,
    # обрыв SSH, kill) конфиг возвращается в обычный режим.
    trap 'kill $PID 2>/dev/null' INT TERM HUP
    "$APP_LUA_BIN" "$APP_LUA" &
    PID=$!
    wait $PID
    RETVAL=$?

    stop_debug
    echo
    echo "Applogic debug finished, debug mode is OFF. Start the service: applogic start"
}

doexit() {
    exit $RETVAL
}

[ -n "$INCLUDE_ONLY" ] && return

CMD="$1"
[ -z "$CMD" ] && {
    run
    doexit
}
shift

# See how we were called.
case "$CMD" in
    start|stop|restart|reload)
        callinit "$CMD"
        ;;
    debug)
        debug "$@"
        doexit
        ;;
    list)
        list
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        RETVAL=1
        usage
        ;;
esac

doexit
