#!/bin/sh

INITFILE=/etc/init.d/applogic
SERVICE_PID_FILE=/var/run/applogic.pid
APP=$0
RULE=$2
SHOWVAR1=$3
SHOWVAR2=$4
SHOWVAR3=$5
SHOWVAR4=$6
SHOWVAR5=$7

usage() {
    echo "Usage: $APP [ COMMAND [ OPTIONS ] ]"
    echo "Without any command Applogic will be runned in the foreground without debug mode"
    echo
    echo "Commands are:"
    echo "    start|stop|restart|reload     controlling the daemon"
    echo "    list                          show list of active rules"
    echo "    debug 01                      run 01 rule in debug mode"
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
    sleep 5
    exec /usr/bin/lua /usr/lib/lua/applogic/app.lua
    RETVAL=$?
}

list() {
    ubus call applogic list | sort
    RETVAL=$?
}

debug() {
    applogic stop
    uci set applogic.debug_mode.enable='1'
    [ -n "$RULE" ] || {
        uci set applogic.debug_mode.rule="overview"
    }
    [ -n "$RULE" ] && [ "$RULE" == "queu" ] && {
        uci set applogic.debug_mode.rule=queu
    }
    [ -n "$RULE" ] && {
        uci set applogic.debug_mode.rule=$RULE
    }
    [ -n "$SHOWVAR1" ] && {
        uci add_list applogic.debug_mode.showvar=$SHOWVAR1
    }
    [ -n "$SHOWVAR2" ] && {
        uci add_list applogic.debug_mode.showvar=$SHOWVAR2
    }
    [ -n "$SHOWVAR3" ] && {
        uci add_list applogic.debug_mode.showvar=$SHOWVAR3
    }
    [ -n "$SHOWVAR4" ] && {
        uci add_list applogic.debug_mode.showvar=$SHOWVAR4
    }
    [ -n "$SHOWVAR5" ] && {
        uci add_list applogic.debug_mode.showvar=$SHOWVAR5
    }
    uci commit
    sleep 1
    exec /usr/bin/lua /usr/lib/lua/applogic/app.lua
    RETVAL=$?
}

doexit() {
    exit $RETVAL
}

stop_debug() {
    echo "Bye"
}
trap stop_debug SIGINT

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
