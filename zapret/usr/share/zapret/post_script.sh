#!/bin/sh
### Sample custom user script
### Called after executing the zapret.sh, all its variables and functions are available
### $1 - action: start/stop/reload/restart
###
### $DESYNC_MARK     - mark of processed packages, default 0x40000000
### $FILTER_MARK     - mark allowed clients, default 0x10000000
### $CLIENTS_ALLOWED - ip list allowed clients, comma separated
### $NFQUEUE_NUM     - queue number of current desync strategy
### $ISP_IF          - list of WAN interfaces separated by line breaks
### $TCP_PORTS       - UDP ports, comma separated
### $UDP_PORTS       - UDP ports, comma separated
### $NFQWS_BIN       - nfqws binary, default: /usr/bin/nfqws


### uncomment required feature
### don't forget to remove the relevant filters from the strategies
CUSTOM_STUN4ALL=1
CUSTOM_WG4ALL=1
CUSTOM_DISCORD=1
###


### custom desync strategy
DESYNC_STUN4ALL="--dpi-desync=fake --dpi-desync-repeats=2"
DESYNC_WG4ALL="--dpi-desync=fake --dpi-desync-repeats=6"
DESYNC_DISCORD="--dpi-desync=fake --dpi-desync-repeats=2"
###


custom_d()
{
  [ "$NFT" ] && return
  [ "$1" == "stop" ] && stop_custom && return
  is_running || return

  stop_custom_fw
  modprobe -q xt_u32

  # queue number = [ 300-309 ]
  [ "$CUSTOM_STUN4ALL" ] && stun4all "$DESYNC_STUN4ALL" 300 "$1"
  [ "$CUSTOM_WG4ALL" ] && wg4all "$DESYNC_WG4ALL" 301  "$1"
  [ "$CUSTOM_DISCORD" ] && discord "$DESYNC_DISCORD" 302  "$1"
}

stun4all()
{
  # $1 - desync strategy
  # $2 - queue number
  # $3 - action: "start" if need launch nfqws binary

  start_custom_fw "-p udp -m u32 --u32" "0>>22&0x3C@4>>16=28:65535&&0>>22&0x3C@12=0x2112A442&&0>>22&0x3C@8&0xC0000003=0" $2
  [ "$3" == "start" ] && start_custom "stun4all" "$1" "$2"
}

wg4all()
{
  start_custom_fw "-p udp -m u32 --u32" "0>>22&0x3C@4>>16=0x9c&&0>>22&0x3C@8=0x01000000" $2
  [ "$3" == "start" ] && start_custom "wg4all" "$1" "$2"
}

discord()
{
  start_custom_fw "-p udp --dport 50000:50099 -m u32 --u32" "0>>22&0x3C@4>>16=0x52&&0>>22&0x3C@8=0x00010046&&0>>22&0x3C@16=0&&0>>22&0x3C@76=0" $2
  [ "$3" == "start" ] && start_custom "discord" "$1" "$2"
}

###

post_start()
{
  # download additional domain lists
  # zapret.sh download-list

  custom_d stop
  custom_d start
}

post_stop()
{
  custom_d stop
}

post_reload()
{
  custom_d
}

post_restart()
{
  custom_d stop
  custom_d start
}

###

stop_custom_fw()
{
  eval "$(iptables-save -t mangle 2>/dev/null | grep "queue-num 30[0-9] " | sed 's/^-A/iptables -t mangle -D/g')"
}

start_custom_fw()
{
  # $1 - iptables params (proto, ports, u32)
  # $2 - iptables u32 params
  # $3 - queue number [ 300-309 ]

  local filter
  if [ "$CLIENTS_ALLOWED" ]; then
    filter="-m mark --mark $FILTER_MARK/$FILTER_MARK"
  fi

  for i in $ISP_IF; do
    iptables -t mangle -A POSTROUTING -o $i $filter $1 "$2" -j NFQUEUE --queue-num $3 --queue-bypass
  done
}

stop_custom()
{
  stop_custom_fw
  for i in $(ps | grep "nfqws --qnum=30[0-9]" | cut -d ' ' -f1); do
    kill $i
  done
}

start_custom()
{
  # $1 - custom rule name
  # $2 - desync strategy
  # $3 - queue number

  $NFQWS_BIN --qnum=$3 --daemon --user=nobody $2 >/dev/null 2>&1
  log "custom rule $1 started"
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
