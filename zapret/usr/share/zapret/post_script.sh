### Sample custom user script
### Called after executing the zapret.sh, all its variables and functions are available
### $1 - action: start/stop/reload

case "$1" in
    start)
      log "post start actions"
    ;;

    stop)
      log "post stop actions"
    ;;

    reload)
      log "post reload actions"
    ;;
esac
