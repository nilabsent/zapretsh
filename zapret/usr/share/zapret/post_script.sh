#!/bin/sh
### Sample custom user script
### Called after executing the zapret.sh, all its variables and functions are available
### $1 - action: start/stop/reload/restart
###
### $DESYNC_MARK  - mark of processed packages, default 0x40000000
### $FILTER_MARK  - mark allowed clients, default 0x10000000
### $NFQUEUE_NUM  - queue number
### $ISP_IF       - list of WAN interfaces separated by line breaks
### $TCP_PORTS    - UDP ports separated by commas
### $UDP_PORTS    - UDP ports separated by commas

post_start()
{
    # log "post start actions"

    # download additional domain lists
    # zapret.sh download-list

    return 0
}

post_stop()
{
    # log "post stop actions"
    return 0
}

post_reload()
{
    # log "post reload actions"
    return 0
}

post_restart()
{
    # log "post restart actions"
    return 0
}

case "$1" in
    start)
        post_start
    ;;

    stop)
        post_stop
    ;;

    reload)
        post_reload
    ;;

    restart)
        post_restart
    ;;
esac
