#!/bin/sh

# https://github.com/nilabsent/zapretsh

# for openwrt versions 21 and above (iptables):
# opkg install curl iptables-mod-nfqueue iptables-mod-conntrack-extra
#
# for openwrt versions 22 and later (nftables):
# opkg install curl kmod-nft-queue kmod-nfnetlink-queue

NFQWS_BIN="/usr/bin/nfqws"
NFQWS_BIN_OPT="/opt/bin/nfqws"
NFQWS_BIN_GIT="/tmp/nfqws"
ETC_DIR="/etc"

# padavan
[ -d "/etc_ro" -a -d "/etc/storage" ] && ETC_DIR="/etc/storage"

CONF_DIR="${ETC_DIR}/zapret"
CONF_DIR_EXAMPLE="/usr/share/zapret"
CONF_FILE="$CONF_DIR/config"
STRATEGY_FILE="$CONF_DIR/strategy"
PID_FILE="/var/run/zapret.pid"
POST_SCRIPT="$CONF_DIR/post_script.sh"

HOSTLIST_DOMAINS="https://github.com/1andrevich/Re-filter-lists/releases/latest/download/domains_all.lst"

HOSTLIST_MARKER="<HOSTLIST>"
HOSTLIST_NOAUTO_MARKER="<HOSTLIST_NOAUTO>"

HOSTLIST_NOAUTO="
  --hostlist=${CONF_DIR}/user.list
  --hostlist=${CONF_DIR}/auto.list
  --hostlist-exclude=${CONF_DIR}/exclude.list
  --hostlist=/tmp/filter.list
"
HOSTLIST="
  --hostlist=${CONF_DIR}/user.list
  --hostlist-exclude=${CONF_DIR}/exclude.list
  --hostlist-auto=${CONF_DIR}/auto.list
  --hostlist=/tmp/filter.list
"

### default config

ISP_INTERFACE=
NFQUEUE_NUM=200
LOG_LEVEL=0
USER="nobody"

###

log()
{
    [ -n "$*" ] || return
    echo "$@"
    local pid
    [ -f "$PID_FILE" ] && pid="[$(cat "$PID_FILE" 2>/dev/null)]"
    logger -t "zapret$pid" "$@"
}

error()
{
    log "$@"
    exit 1
}

if id -u >/dev/null 2>&1; then
    [ $(id -u) != "0" ] && echo "root user is required to start" && exit 1
fi

# padavan: possibility of running nfqws from usb-flash drive
[ -d "/etc_ro" ] && for i in $(cat /proc/mounts | awk '/^\/dev.+\/media/{print $2}'); do
    if [ -s "${i}$NFQWS_BIN_OPT" ]; then
        chmod +x "${i}$NFQWS_BIN_OPT"
        if [ -x "${i}$NFQWS_BIN_OPT" ]; then
            NFQWS_BIN="${i}$NFQWS_BIN_OPT"
            break
        fi
    fi
done

[ -s "$NFQWS_BIN_GIT" ] && NFQWS_BIN="$NFQWS_BIN_GIT"

[ -f "$CONF_DIR" ] && rm -f "$CONF_DIR"
[ -d "$CONF_DIR" ] || mkdir -p "$CONF_DIR" || exit 1
# copy all non-existent config files to storage except fake dir
[ -d "$CONF_DIR_EXAMPLE" ] && false | cp -i "${CONF_DIR_EXAMPLE}"/* "$CONF_DIR" >/dev/null 2>&1

[ -s "$CONF_FILE" ] && . "$CONF_FILE"

for i in user.list exclude.list auto.list strategy config; do
  [ -f ${CONF_DIR}/$i ] || touch ${CONF_DIR}/$i || exit 1
done

###

unset OPENWRT
[ -f "/etc/openwrt_release" ] && OPENWRT=1
unset NFT
nft -v >/dev/null 2>&1 && NFT=1

# padavan
if [ -x "/usr/sbin/nvram" ]; then
    [ "$(nvram get zapret_iface)" ] && ISP_INTERFACE="$(nvram get zapret_iface)"
    [ "$(nvram get zapret_log)" ] && LOG_LEVEL="$(nvram get zapret_log)"
    [ "$(nvram get zapret_strategy)" ] && STRATEGY_FILE="$STRATEGY_FILE$(nvram get zapret_strategy)"
fi

_get_if_default()
{
    ip -$1 route show default | grep via | sed -r 's/^.*default.*via.* dev ([^ ]+).*$/\1/' | head -n1
}

if [ "$ISP_INTERFACE" ]; then
    ISP_IF=$(echo "$ISP_INTERFACE" | tr -d " " | tr "," "\n" | sort -u);
else
    ISP_IF4=$(_get_if_default 4);
    ISP_IF6=$(_get_if_default 6);
    ISP_IF=$(printf "%s\n%s" "${ISP_IF4}" "${ISP_IF6}" | sort -u)
fi

_get_ports()
{
    grep -v "^#" $STRATEGY_FILE | grep -Eo "filter-$1=[0-9,-]+" \
        | cut -d '=' -f2 | tr ',' '\n' | sort -u \
        | sed -ne 'H;${x;s/\n/,/g;s/-/:/g;s/^,//;p;}'
}

TCP_PORTS=$(_get_ports tcp)
UDP_PORTS=$(_get_ports udp)

_MANGLE_RULES()
{
    [ "$TCP_PORTS" ] && echo "-A PREROUTING  -i $IFACE -p tcp -m multiport --sports $TCP_PORTS -m connbytes --connbytes-dir=reply    --connbytes-mode=packets --connbytes 1:3 -m mark ! --mark 0x40000000/0x40000000 -j NFQUEUE --queue-num $NFQUEUE_NUM --queue-bypass"
    [ "$TCP_PORTS" ] && echo "-A POSTROUTING -o $IFACE -p tcp -m multiport --dports $TCP_PORTS -m connbytes --connbytes-dir=original --connbytes-mode=packets --connbytes 1:9 -m mark ! --mark 0x40000000/0x40000000 -j NFQUEUE --queue-num $NFQUEUE_NUM --queue-bypass"
    [ "$UDP_PORTS" ] && echo "-A POSTROUTING -o $IFACE -p udp -m multiport --dports $UDP_PORTS -m connbytes --connbytes-dir=original --connbytes-mode=packets --connbytes 1:9 -m mark ! --mark 0x40000000/0x40000000 -j NFQUEUE --queue-num $NFQUEUE_NUM --queue-bypass"
}

is_running()
{
    [ -z "$(pgrep `basename "$NFQWS_BIN"` 2>/dev/null)" ] && return 1
    [ ! -f "$PID_FILE" ] && return 1
    return 0
}

status_service()
{
    if is_running; then
        echo "service nfqws is running"
        exit 0
    else
        echo "service nfqws is stopped"
        exit 1
    fi
}

kernel_modules()
{
    # "modprobe -a" may not supported
    for i in nfnetlink_queue xt_connbytes xt_NFQUEUE nft-queue; do
        modprobe -q $i >/dev/null 2>&1
    done
}

replace_str()
{
    local a=$(echo "$1" | sed 's/\//\\\//g')
    local b=$(echo "$2" | tr '\n' ' ' | sed 's/\//\\\//g')
    shift; shift
    echo "$@" | tr '\n' ' ' | sed "s/$a/$b/g; s/[ \t]\{1,\}/ /g"
}

startup_args()
{
    [ -f /tmp/filter.list ] || touch /tmp/filter.list
    local args="--user=$USER --qnum=$NFQUEUE_NUM"

    [ "$LOG_LEVEL" = "1" ] && args="--debug=syslog $args"

    NFQWS_ARGS="$(grep -v '^#' $STRATEGY_FILE)"
    NFQWS_ARGS=$(replace_str "$HOSTLIST_MARKER" "$HOSTLIST" "$NFQWS_ARGS")
    NFQWS_ARGS=$(replace_str "$HOSTLIST_NOAUTO_MARKER" "$HOSTLIST_NOAUTO" "$NFQWS_ARGS")
    echo "$args $NFQWS_ARGS"
}

offload_unset_nft_rules()
{
    nft delete chain inet zapret forward 2>/dev/null
    nft delete flowtable inet zapret ft 2>/dev/null
}

offload_unset_ipt_rules()
{
    eval "$(ip$1tables-save -t filter 2>/dev/null | grep "FORWARD.*forwarding_rule_zapret" | sed 's/^-A/ip$1tables -D/g')"
    ip$1tables -F forwarding_rule_zapret 2>/dev/null
    ip$1tables -X forwarding_rule_zapret 2>/dev/null
}

offload_stop()
{
    [ "$OPENWRT" ] || return
    if [ "$NFT" ]; then
        offload_unset_nft_rules
    else
        offload_unset_ipt_rules
        offload_unset_ipt_rules 6
    fi
}

offload_set_nft_rules()
{
    flow=$(fw4 print | grep -A5 "flowtable" | grep -E "hook|devices|flags" | tr -d '"')
    [ "$flow" ] || return
    nft add flowtable inet zapret ft "{$flow}"

    UDP_PORTS=$(echo $UDP_PORTS | tr ":" "-")
    TCP_PORTS=$(echo $TCP_PORTS | tr ":" "-")

    nft add chain inet zapret forward "{type filter hook forward priority filter; policy accept;}"
    [ "$TCP_PORTS" ] && nft add rule inet zapret forward "tcp dport {$TCP_PORTS} ct original packets 1-9 return comment direct_flow_offloading_exemption"
    [ "$UDP_PORTS" ] && nft add rule inet zapret forward "udp dport {$UDP_PORTS} ct original packets 1-9 return comment direct_flow_offloading_exemption"
    nft add rule inet zapret forward "meta l4proto { tcp, udp } flow add @ft"
}

offload_set_ipt_rules()
{
    local HW_OFFLOAD FW_FORWARD

    [ "$(uci -q get firewall.@defaults[0].flow_offloading_hw)" = "1" ] && HW_OFFLOAD="--hw"

    FW_FORWARD=$(
        for IFACE in $ISP_IF; do
            # insert after custom forwarding rule chain
            echo "-I FORWARD 2 -o $IFACE -j forwarding_rule_zapret"
        done)

    [ -n "$FW_FORWARD" ] && ip$1tables-restore -n <<EOF
*filter
:forwarding_rule_zapret - [0:0]
-A forwarding_rule_zapret -p udp -m multiport --dports $UDP_PORTS -m connbytes --connbytes 1:9 --connbytes-mode packets --connbytes-dir original -m comment --comment zapret_traffic_offloading_exemption -j RETURN
-A forwarding_rule_zapret -p tcp -m multiport --dports $TCP_PORTS -m connbytes --connbytes 1:9 --connbytes-mode packets --connbytes-dir original -m comment --comment zapret_traffic_offloading_exemption -j RETURN
-A forwarding_rule_zapret -m comment --comment zapret_traffic_offloading_enable -m conntrack --ctstate RELATED,ESTABLISHED -j FLOWOFFLOAD $HW_OFFLOAD
$(echo "$FW_FORWARD")
COMMIT
EOF
}

offload_start()
{
    # offloading is supported only in OpenWrt
    [ -n "$OPENWRT" ] || return

    offload_stop

    [ -n "$ISP_IF" ] || return
    [ "$(uci -q get firewall.@defaults[0].flow_offloading)" = "1" ] || return

    if [ "$NFT" ]; then
        # delete system nftables offloading
        nft_rule_handle=$(nft -a list chain inet fw4 forward | grep "flow add @ft" | grep -Eo "handle [0-9]+$" | head -n1)
        [ "$nft_rule_handle" ] && nft delete rule inet fw4 forward $nft_rule_handle
        nft delete flowtable inet fw4 ft 2>/dev/null

        offload_set_nft_rules
    else
        # delete system iptables offloading
        eval "$(iptables-save -t filter 2>/dev/null | grep "FLOWOFFLOAD" | sed 's/^-A/iptables -D/g')"
        eval "$(ip6tables-save -t filter 2>/dev/null | grep "FLOWOFFLOAD" | sed 's/^-A/ip6tables -D/g')"

        offload_set_ipt_rules
        offload_set_ipt_rules 6
    fi

    log "offloading rules updated"
}

nftables_stop()
{
    [ -n "$NFT" ] || return
    nft delete table inet zapret 2>/dev/null
}

iptables_stop()
{
    [ -n "$NFT" ] && return
    eval "$(iptables-save -t mangle 2>/dev/null | grep "queue-num $NFQUEUE_NUM " | sed 's/^-A/iptables -t mangle -D/g')"
    eval "$(ip6tables-save -t mangle 2>/dev/null | grep "queue-num $NFQUEUE_NUM " | sed 's/^-A/ip6tables -t mangle -D/g')"
}

firewall_stop()
{
    nftables_stop
    iptables_stop
    offload_stop
}

nftables_start()
{
    [ -n "$NFT" ] || return

    UDP_PORTS=$(echo $UDP_PORTS | tr ":" "-")
    TCP_PORTS=$(echo $TCP_PORTS | tr ":" "-")

    nft create table inet zapret
    nft add chain inet zapret post "{type filter hook postrouting priority mangle;}"
    nft add chain inet zapret pre "{type filter hook prerouting priority filter;}"

    for IFACE in $ISP_IF; do
        [ "$TCP_PORTS" ] && nft add rule inet zapret post oifname $IFACE meta mark and 0x40000000 == 0 tcp dport "{$TCP_PORTS}" ct original packets 1-9 queue num $NFQUEUE_NUM bypass
        [ "$UDP_PORTS" ] && nft add rule inet zapret post oifname $IFACE meta mark and 0x40000000 == 0 udp dport "{$UDP_PORTS}" ct original packets 1-9 queue num $NFQUEUE_NUM bypass
        [ "$TCP_PORTS" ] && nft add rule inet zapret pre iifname $IFACE tcp sport "{$TCP_PORTS}" ct reply packets 1-3 queue num $NFQUEUE_NUM bypass
    done
}

iptables_set_rules()
{
    local FW_MANGLE

    [ "$1" == "6" ] && [ ! -d /proc/sys/net/ipv6 ] && return

    FW_MANGLE=$(
        for IFACE in $ISP_IF; do
            echo "$(_MANGLE_RULES)"
        done)

    [ -n "$FW_MANGLE" ] && ip$1tables-restore -n <<EOF
*mangle
$(echo "$FW_MANGLE")
COMMIT
EOF
}

iptables_start()
{
    [ -n "$NFT" ] && return

    UDP_PORTS=$(echo $UDP_PORTS | tr "-" ":")
    TCP_PORTS=$(echo $TCP_PORTS | tr "-" ":")

    iptables_set_rules
    iptables_set_rules 6
}

firewall_start()
{
    firewall_stop

    nftables_start
    iptables_start

    if [ "$ISP_IF" ]; then
        IF_LOG=$(echo "$ISP_IF" | tr "\n" " ")
        log "firewall rules updated on interface(s): $IF_LOG"
    else
        log "firewall rules were not set"
    fi

    offload_start
}

system_config()
{
    sysctl -w net.netfilter.nf_conntrack_checksum=0 >/dev/null 2>&1
    sysctl -w net.netfilter.nf_conntrack_tcp_be_liberal=1 >/dev/null 2>&1
    [ -n "$OPENWRT" ] || return
    [ -s /etc/firewall.zapret ] \
        || echo "[ -x /usr/bin/zapret.sh ] && /usr/bin/zapret.sh reload" > /etc/firewall.zapret
    uci -q get firewall.zapret >/dev/null || (
        uci -q set firewall.zapret=include
        uci -q set firewall.zapret.path='/etc/firewall.zapret'
        [ ! "$NFT" ] && uci -q set firewall.zapret.reload='1'
        [ "$NFT" ] && uci -q set firewall.zapret.fw4_compatible='1'
        uci commit
    )
}

set_strategy_file()
{
    [ "$1" ] || return
    [ -s "$1" ] && STRATEGY_FILE="$1"
    [ -s "${CONF_DIR}/$1" ] && STRATEGY_FILE="${CONF_DIR}/$1"
}

start_service()
{
    [ -s "$NFQWS_BIN" -a -x "$NFQWS_BIN" ] || error "$NFQWS_BIN: not found or invalid"
    if is_running; then
        echo "already running"
        return
    fi

    set_strategy_file "$@"

    kernel_modules

    res=$($NFQWS_BIN --daemon --pidfile=$PID_FILE $(startup_args) 2>&1)
    if [ ! "$?" = "0" ]; then
        log "failed to start: $(echo "$res" | grep 'github version')"
        echo "$res" | grep -Ei 'unrecognized|invalid' \
        | while read -r i; do
            log "$i"
        done
        exit 1
    fi

    log "started, $(echo "$res" | grep 'github version')"
    log "use strategy from $STRATEGY_FILE"
    echo "$res" \
    | grep -Ei "loaded|profile" \
    | while read -r i; do
        log "$i"
    done

    system_config
    firewall_start
}

stop_service()
{
    firewall_stop
    killall -q -s 15 $(basename "$NFQWS_BIN") && log "stopped"
    rm -f "$PID_FILE"
}

reload_service()
{
    is_running || return
    firewall_start
    kill -HUP $(cat "$PID_FILE")
}

download_nfqws()
{
    # $1 - nfqws version number starting from 69.3

    local archive="/tmp/zapret.tar.gz"

    ARCH=$(uname -m | grep -oE 'mips|mipsel|aarch64|arm|rlx|i386|i686|x86_64')
    case "$ARCH" in
        aarch64*)
            ARCH="(aarch64|arm64)"
        ;;
        armv*)
            ARCH="arm"
        ;;
        rlx)
            ARCH="lexra"
        ;;
        mips)
            ARCH="(mips32r1-msb|mips)"
            grep -qE 'system type.*(MediaTek|Ralink)' /proc/cpuinfo && ARCH="(mips32r1-lsb|mipsel)"
        ;;
        i386|i686)
            ARCH="x86"
        ;;
    esac
    [ -n "$ARCH" ] || error "cpu arch unknown"

    if [ "$1" ]; then
        URL="https://github.com/bol-van/zapret/releases/download/v$1/zapret-v$1-openwrt-embedded.tar.gz"
        if [ -x /usr/bin/curl ]; then
            curl -sSL --connect-timeout 10 "$URL" -o $archive \
                || error "unable to download $URL"
        else
            wget -q -t5 -T10 "$URL" -O $archive \
                || error "unable to download $URL"
        fi
    else
        if [ -x /usr/bin/curl ]; then
            URL=$(curl -sSL --connect-timeout 10 'https://api.github.com/repos/bol-van/zapret/releases/latest' \
                  | grep 'browser_download_url.*openwrt-embedded' | cut -d '"' -f4)
            [ -n "$URL" ] || error "unable to get archive link"

            curl -sSL --connect-timeout 10 "$URL" -o $archive \
                || error "unable to download: $URL"
        else
            URL=$(wget -q -t5 -T10 'https://api.github.com/repos/bol-van/zapret/releases/latest' -O- \
                  | grep 'browser_download_url.*openwrt-embedded' | cut -d '"' -f4)
            [ -n "$URL" ] || error "unable to get archive link"

            wget -q -t5 -T10 "$URL" -O $archive \
                || error "unable to download: $URL"
        fi
    fi

    [ -s $archive ] || exit
    [ $(cat $archive | head -c3) = "Not" ] && error "not found: $URL"
    log "downloaded successfully: $URL"

    local NFQWS=$(tar tzfv $archive \
                  | grep -E "binaries/(linux-)?$ARCH/nfqws" | awk '{print $6}')
    [ -n "$NFQWS" ] || error "nfqws not found for architecture $ARCH"

    tar xzf $archive "$NFQWS" -O > $NFQWS_BIN_GIT
    [ -s $NFQWS_BIN_GIT ] && chmod +x $NFQWS_BIN_GIT
    rm -f $archive
}

download_list()
{
    local LIST="/tmp/filter.list"

    if [ -f /usr/bin/curl ]; then
        curl -sSL --connect-timeout 5 "$HOSTLIST_DOMAINS" -o $LIST || error "unable to download $HOSTLIST_DOMAINS"
    else
        wget -q -T 5 "$HOSTLIST_DOMAINS" -O $LIST || error "unable to download $HOSTLIST_DOMAINS"
    fi

    [ -s "$LIST" ] && log "downloaded successfully: $HOSTLIST_DOMAINS"
}

case "$1" in
    start)
        start_service "$2"
    ;;

    stop)
        stop_service

        # openwrt: restore default firewall rules
        [ "$OPENWRT" ] && /etc/init.d/firewall reload >/dev/null 2>&1
    ;;

    status)
        status_service
    ;;

    restart)
        stop_service
        start_service "$2"
    ;;

    firewall-start)
        firewall_start
    ;;

    firewall-stop)
        firewall_stop
    ;;

    offload-start)
        offload_start
    ;;

    offload-stop)
        offload_stop
    ;;

    reload)
        reload_service
    ;;

    download|download-nfqws)
        download_nfqws "$2"
    ;;

    download-list)
        download_list
    ;;

    *)  echo "Usage: $0 {start [strategy_file]|stop|restart [strategy_file]|download [version_nfqws]|download-list|status}"
esac

[ -s "$POST_SCRIPT" -a -x "$POST_SCRIPT" ] && . "$POST_SCRIPT"
