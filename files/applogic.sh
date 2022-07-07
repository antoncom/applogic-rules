#!/bin/sh

INITFILE=/etc/init.d/applogic
SERVICE_PID_FILE=/var/run/applogic.pid
APP=$0

usage() {
    echo "Usage: $APP [ COMMAND [ OPTIONS ] ]"
    echo "Without any command Applogic will be runned in the foreground without debug mode"
    echo
    echo "Commands are:"
    echo "    start|stop|restart|reload     controlling the daemon"
    echo "    list                          show list of active rules"
    echo "    debug                         run in rules debug mode"
    echo "    help                          show this and exit"
    doexit
}
callinit() {
    [ -x $INITFILE ] || {
        echo "No init file '$INITFILE'"
        return
    }
    exec $INITFILE $1
    RETVAL=$?
}
run() {
    uci set applogic.debug_mode.enable='0'
    uci commit
    exec /usr/bin/lua /usr/lib/lua/applogic/app.lua
    RETVAL=$?
}

list() {
    ubus call applogic.cpe list
    RETVAL=$?
}

debug() {
    applogic stop
    uci set applogic.debug_mode.enable='1'
    uci commit
    exec /usr/bin/lua /usr/lib/lua/applogic/app.lua
    RETVAL=$?
}

doexit() {
    exit $RETVAL
}

[ -n "$INCLUDE_ONLY" ] && return

CMD="$1"
[ -z $CMD ] && {
    run
    doexit
}
shift
# See how we were called.
case "$CMD" in
    start|stop|restart|reload)
        callinit $CMD
        ;;
    debug)
        debug
        ;;
    list)
        list
        ;;
    *help|*?)
        usage $0
        ;;
    *)
        RETVAL=1
        usage $0
        ;;
esac

doexit
