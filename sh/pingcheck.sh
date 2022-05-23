#!/bin/sh

attempts=2
interval=2
timeout=$(($attempts*$interval))

check_active_host() {
    active_host=`ubus call cpeagent status | jsonfilter -e '$.broker.host'`
    active_host_state=`ubus call cpeagent status | jsonfilter -e '$.state'`
    ping_host $active_host
}

make_reserved_host_list() {
    reserved_host_list=""
    active_host=`ubus call cpeagent status | jsonfilter -e '$.broker.host'`
    for host in `uci show wimark | tr -d '"' | tr -d "'"  | grep 'host' | awk -F'=' '{print $2}'`; do
        if [[ "$host" != "$active_host" ]]; then
            if [[ $(ping_host $host) == "OK" ]]; then
                reserved_host_list="$reserved_host_list $host"
            fi
        fi
    done
    echo $reserved_host_list
}

switch_to_host() {
    CPE_non_alived_hosts=$1
    echo "CPE_non_alived_hosts: $CPE_non_alived_hosts"
    for host in $CPE_non_alived_hosts; do
        ping_status=$(ping_host $host)
        echo "Ping status of reserved: $ping_status"
        if [[ $ping_status == "OK" ]];
        then
            # TODO - CALL SWITCH METHOD HERE, like this:
            ubus call cpeagent status # just for demo

            break
        else
            echo "$host FAIL"
        fi
    done
}

ping_host() {
    host=$1
    result=$(ping $host -c $attempts -i $interval -W $interval -w $timeout -q 2>/dev/null | awk -v HOST="$host" -v ATTM=$attempts -v INTRVL=$interval '{
        if(NF>6) {
            loss = $7; loss = substr($7, 0, length($7)-1);
            if(loss == "100") {
                print "FAIL"
                system("uci set")
            } else {
                print "OK"
            }
        }
    }')
    # if Error occured in ping (when possibly bad address, etc.)
    if [[ -z $result ]]; then
        result="FAIL"
    fi
    echo $result
}

start() {
    while true
    do
        ping_status=$(check_active_host)
        if [[ $(check_active_host) == "OK" ]]; then
            echo "Active host OK"
            if [[ ! -z $(make_reserved_host_list) ]]; then
                echo "Reserved list has alive hosts."
                switch_to_host "$(make_reserved_host_list)"
            else
                echo "cpeagent: pingcheck.sh: No reserved host alive."
            fi
        fi
        sleep 3
    done
}

APP=$0
CMD=$1; shift
usage() {
    echo "Usage: $APP COMMAND [ OPTIONS ]"
    echo
    echo "Commands are:"
    echo "  start       run ping checking"
    echo "  help        show this and exit"
}

case "$CMD" in
    start)
        start
        ;;
    help|-h|--help)
        usage
        exit 0
        ;;
    *)
        usage $APP
        exit 1
        ;;
esac
