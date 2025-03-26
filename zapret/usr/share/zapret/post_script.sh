#!/bin/sh
### Sample custom user script
### Called after executing the zapret.sh, all its variables and functions are available
### $1 - action: start/stop/reload

post_start()
{
    log "post start actions"
}

post_stop()
{
    log "post stop actions"
}

post_reload()
{
    log "post reload actions"
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
esac
