#!/bin/sh

INITFILE=/etc/init.d/applogic
SERVICE_PID_FILE=/var/run/applogic.pid
APP=$0
APP_LUA=/usr/lib/lua/applogic/app.lua
RETVAL=0


usage() {
    echo "Usage: $APP [ COMMAND [ OPTIONS ] ]"
    echo "Without any command Applogic will be run in the foreground without debug mode"    echo
    echo "Commands are:"
    echo "    start|stop|restart|reload     controlling the daemon"
    echo "    list                          show list of active rules"
    echo "    debug [RULE [VAR...]]         run RULE in debug mode (default: overview),"
    echo "                                  show up to 5 variables VAR"
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

run() {
    uci set applogic.debug_mode.enable='1'
    uci commit applogic

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

debug() {
    RULE=${1:-overview}
    [ $# -gt 0 ] && shift

    applogic stop
    uci set applogic.debug_mode.enable='1'
    uci set applogic.debug_mode.rule="$RULE"

    # drop showvars left over from the previous debug session
    uci -q delete applogic.debug_mode.showvar
    for VAR in "$@"; do
        uci add_list applogic.debug_mode.showvar="$VAR"
    done
    uci commit applogic

    sleep 1
    exec "$APP_LUA_BIN" "$APP_LUA"
}

doexit() {
    exit $RETVAL
}

APP_LUA_BIN=/usr/bin/lua

trap stop_debug SIGINT

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
