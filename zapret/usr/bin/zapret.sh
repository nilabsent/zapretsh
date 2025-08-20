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
DESYNC_MARK="0x40000000"
# mark allowed clients
FILTER_MARK="0x10000000"

### default config

ISP_INTERFACE=
NFQUEUE_NUM=200
LOG_LEVEL=0
USER="nobody"

# comma separated list of client ipv4 addresses, enables client access restrictions
CLIENTS_ALLOWED=

###

log()
{
    [ -n "$*" ] || return
    echo "$@"
    local pid
    [ -f "$PID_FILE" ] && pid="[$(cat "$PID_FILE" 2>/dev/null)]"
    logger -t "zapret$pid" "$@"
}

trim()
{
    awk '{gsub(/^ +| +$/,"")}1'
}

error()
{
    log "$@"
    exit 1
}

_get_if_default()
{
    # $1 = 4  - ipv4
    # $1 = 6  - ipv6
    ip -$1 route show default | grep via | sed -r 's/^.*default.*via.* dev ([^ ]+).*$/\1/' | head -n1
}

isp_is_present()
{
    [ "$(echo "$ISP_IF" | tr -d ' ,\n')" ]
}

_get_ports()
{
    grep -v "^#" "$STRATEGY_FILE" | tr -d '"' | grep -o "[-][-]filter-$1=[0-9][0-9,-]*" \
        | cut -d '=' -f2 | tr -s ',' '\n' | sort -u \
        | sed -ne 'H;${x;s/\n/,/g;s/-/:/g;s/^,//;p;}'
}

get_port_list(){
    # set limit for multiport iptables
    local port_limit=7

    echo "$1" | tr ',' '\n' | xargs -n$port_limit | tr ' ' ','
}

_mangle_rules()
{
    local i iface filter ports

    # enable only for ipv4
    # $1 = "6" - sign that it is ipv6
    if [ "$CLIENTS_ALLOWED" -a ! "$1" ]; then
        filter="-m mark --mark $FILTER_MARK/$FILTER_MARK"

        echo "-A OUTPUT -j MARK --or-mark $FILTER_MARK"
        for i in $CLIENTS_ALLOWED; do
            echo "-A PREROUTING -s $i -j MARK --or-mark $FILTER_MARK"
        done
    fi

    local rule_nfqueue="-j NFQUEUE --queue-num $NFQUEUE_NUM --queue-bypass"
    local rule_output_end="$filter -m mark ! --mark $DESYNC_MARK/$DESYNC_MARK -m connbytes --connbytes 1:9 --connbytes-mode packets --connbytes-dir original $rule_nfqueue"

    for iface in $ISP_IF; do
        for ports in $(get_port_list "$TCP_PORTS"); do
            echo "-A PREROUTING -i $iface -p tcp -m multiport --sports $ports -m connbytes --connbytes 1:3 --connbytes-mode packets --connbytes-dir reply $rule_nfqueue"
            echo "-A POSTROUTING -o $iface -p tcp -m multiport --dports $ports $rule_output_end"
        done
        for ports in $(get_port_list "$UDP_PORTS"); do
            echo "-A POSTROUTING -o $iface -p udp -m multiport --dports $ports $rule_output_end"
        done
    done
}

is_running()
{
    [ -z "$(pgrep `basename "$NFQWS_BIN"` 2>/dev/null)" ] && return 1
    [ "$PID_FILE" ]
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
    local b=$(echo "$2" | tr -s '\n' ' ' | sed 's/\//\\\//g')
    shift; shift
    echo "$@" | tr -s '\n' ' ' | sed "s/$a/$b/g; s/[ \t]\{1,\}/ /g"
}

startup_args()
{
    [ -f /tmp/filter.list ] || touch /tmp/filter.list
    local args="--user=$USER --qnum=$NFQUEUE_NUM"

    [ "$LOG_LEVEL" = "1" ] && args="--debug=syslog $args"

    NFQWS_ARGS="$(grep -v '^#' "$STRATEGY_FILE" | tr -d '"')"
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
    for i in "" "6"; do
        eval "$(ip${i}tables-save -t filter 2>/dev/null | grep "FORWARD.*forwarding_rule_zapret" | sed 's/^-A/ip${i}tables -D/g')"
        ip${i}tables -F forwarding_rule_zapret 2>/dev/null
        ip${i}tables -X forwarding_rule_zapret 2>/dev/null
    done
}

offload_stop()
{
    [ "$OPENWRT" ] || return
    if [ "$NFT" ]; then
        offload_unset_nft_rules
    else
        offload_unset_ipt_rules
    fi
}

offload_set_nft_rules()
{
    flow=$(fw4 print | grep -A5 "flowtable" | grep -E "hook|devices|flags" | tr -d '"')
    [ "$flow" ] || return
    nft add flowtable inet zapret ft "{$flow}"

    UDP_PORTS=$(echo $UDP_PORTS | tr -s ":" "-")
    TCP_PORTS=$(echo $TCP_PORTS | tr -s ":" "-")

    nft add chain inet zapret forward "{type filter hook forward priority filter; policy accept;}"
    [ "$TCP_PORTS" ] && nft add rule inet zapret forward "tcp dport {$TCP_PORTS} ct original packets 1-9 return comment direct_flow_offloading_exemption"
    [ "$UDP_PORTS" ] && nft add rule inet zapret forward "udp dport {$UDP_PORTS} ct original packets 1-9 return comment direct_flow_offloading_exemption"
    nft add rule inet zapret forward "meta l4proto { tcp, udp } flow add @ft"
}

offload_set_ipt_rules()
{
    local hw_offload fw_forward iface ports i

    forward_rule_zapret(){
        echo "-A forwarding_rule_zapret -p $1 -m multiport --dports $ports -m connbytes --connbytes 1:9 --connbytes-mode packets --connbytes-dir original -m comment --comment zapret_traffic_offloading_exemption -j RETURN"
    }

    flow_rule_zapret(){
        echo "-A forwarding_rule_zapret -m comment --comment zapret_traffic_offloading_enable -m conntrack --ctstate RELATED,ESTABLISHED -j FLOWOFFLOAD $hw_offload"
    }

    [ "$(uci -q get firewall.@defaults[0].flow_offloading_hw)" = "1" ] && hw_offload="--hw"

    for i in "" "6"; do
        fw_forward=$(
            for iface in $ISP_IF; do
                # insert after custom forwarding rule chain
                echo "-I FORWARD 2 -o $iface -j forwarding_rule_zapret"
            done

            for ports in $(get_port_list "$TCP_PORTS"); do
                forward_rule_zapret tcp
            done
            for ports in $(get_port_list "$UDP_PORTS"); do
                forward_rule_zapret udp
            done

            flow_rule_zapret
        )

        ip${i}tables-restore -n <<EOF
*filter
:forwarding_rule_zapret - [0:0]
$(echo "$fw_forward")
COMMIT
EOF
    done
}

offload_start()
{
    # offloading is supported only in OpenWrt
    [ -n "$OPENWRT" ] || return

    [ "$(uci -q get firewall.@defaults[0].flow_offloading)" = "1" ] || return

    if [ "$NFT" ]; then
        # delete system nftables offloading
        nft_rule_handle=$(nft -a list chain inet fw4 forward | grep "flow add @ft" | grep -Eo "handle [0-9]+$" | head -n1)
        [ "$nft_rule_handle" ] && nft delete rule inet fw4 forward $nft_rule_handle
        nft delete flowtable inet fw4 ft 2>/dev/null

        offload_set_nft_rules
    else
        # delete system iptables offloading
        local i
        for i in "" "6"; do
            eval "$(ip${i}tables-save -t filter 2>/dev/null | grep "FLOWOFFLOAD" | sed 's/^-A/ip${i}tables -D/g')"
        done

        offload_set_ipt_rules
    fi

    log "firewall offloading rules updated"
}

nftables_stop()
{
    [ -n "$NFT" ] || return
    nft delete table inet zapret 2>/dev/null
}

iptables_stop()
{
    [ -n "$NFT" ] && return

    local i
    for i in "" "6"; do
        [ "$i" == "6" ] && [ ! -d /proc/sys/net/ipv6 ] && continue
        ip${i}tables-restore -n <<EOF
*mangle
$(ip${i}tables-save -t mangle 2>/dev/null | sed -n "/\(queue-num $NFQUEUE_NUM --queue\|mark $DESYNC_MARK\/$DESYNC_MARK\|mark $FILTER_MARK\/$FILTER_MARK\)/{s/^-A/-D/p}")
COMMIT
EOF
    done
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

    local filter iface

    UDP_PORTS=$(echo $UDP_PORTS | tr -s ":" "-")
    TCP_PORTS=$(echo $TCP_PORTS | tr -s ":" "-")

    nft create table inet zapret
    nft add set inet zapret wanif "{type ifname;}"
    nft add chain inet zapret post "{type filter hook postrouting priority mangle;}"
    nft add chain inet zapret pre "{type filter hook prerouting priority filter;}"

    for iface in $ISP_IF; do
        nft add element inet zapret wanif "{ $iface }"
    done

    if [ "$CLIENTS_ALLOWED" ]; then
        filter="mark and $FILTER_MARK != 0"
        nft add chain inet zapret mark_out "{type filter hook output priority mangle;}"
        nft add rule inet zapret mark_out mark set mark or $FILTER_MARK

        nft add set inet zapret allowedip "{type ipv4_addr; policy memory; size 65536; flags interval; auto-merge}"
        nft add chain inet zapret mark_allowedip "{type filter hook prerouting priority mangle;}"

        nft add element inet zapret allowedip "{ $(echo $CLIENTS_ALLOWED | tr -s ' ' ',') }"
        nft add rule inet zapret mark_allowedip ip saddr == @allowedip mark set mark or $FILTER_MARK
    fi

    [ "$TCP_PORTS" ] && nft add rule inet zapret post oifname @wanif $filter mark and $DESYNC_MARK == 0 tcp dport "{$TCP_PORTS}" ct original packets 1-9 queue num $NFQUEUE_NUM bypass
    [ "$UDP_PORTS" ] && nft add rule inet zapret post oifname @wanif $filter mark and $DESYNC_MARK == 0 udp dport "{$UDP_PORTS}" ct original packets 1-9 queue num $NFQUEUE_NUM bypass
    [ "$TCP_PORTS" ] && nft add rule inet zapret pre iifname @wanif tcp sport "{$TCP_PORTS}" ct reply packets 1-3 queue num $NFQUEUE_NUM bypass
}

iptables_start()
{
    [ -n "$NFT" ] && return

    UDP_PORTS=$(echo $UDP_PORTS | tr -s "-" ":")
    TCP_PORTS=$(echo $TCP_PORTS | tr -s "-" ":")

    local i
    for i in "" "6"; do
        [ "$i" == "6" ] && [ ! -d /proc/sys/net/ipv6 ] && continue
        ip${i}tables-restore -n <<EOF
*mangle
$(_mangle_rules $i)
COMMIT
EOF
    done
}

firewall_start()
{
    firewall_stop

    if isp_is_present; then
        nftables_start
        iptables_start
        offload_start

        log "firewall rules updated on interface(s): $(echo "$ISP_IF" | tr -s '\n' ' ' | trim)"
    else
        log "interfaces not defined, firewall rules not set"
    fi
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

create_random_pattern_files()
{
    rm -f /tmp/rnd*.bin

    local len=$(for i in $ISP_IF; do cat /sys/class/net/$i/mtu; done | sort | head -n1)
    [ ! "$len" ] && len=1280

    local pattern=$(grep -v "^#" "$STRATEGY_FILE" | tr -d '"' \
        | grep -Eo "[-](pattern|syndata|unknown|unknown-udp)=/tmp/rnd[0-9]?[.]bin" \
        | cut -d '=' -f2 | sort -u)

    if [ "$pattern" ]; then
        echo "creating random file(s): "$pattern
        for i in $pattern; do
            head -c $((len-28)) /dev/urandom > "$i"
        done
    fi
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

    kernel_modules
    local pattern=$(create_random_pattern_files)

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
    [ "$CLIENTS_ALLOWED" ] && log "allowed clients: $CLIENTS_ALLOWED"
    log "use strategy from $STRATEGY_FILE"
    log "$pattern"
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
            wget -q -T 10 "$URL" -O $archive \
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
            URL=$(wget -q -T 10 'https://api.github.com/repos/bol-van/zapret/releases/latest' -O- \
                  | tr ',' '\n' | grep 'browser_download_url.*openwrt-embedded' | cut -d '"' -f4)
            [ -n "$URL" ] || error "unable to get archive link"

            wget -q -T 10 "$URL" -O $archive \
                || error "unable to download: $URL"
        fi
    fi

    [ -s $archive ] || exit
    [ $(cat $archive | head -c3) = "Not" ] && error "not found: $URL"
    log "downloaded successfully: $URL"

    local nfqws_bin=$(tar tzfv $archive | grep -E "binaries/(linux-)?$ARCH/nfqws" | awk '{print $6}')
    [ -n "$nfqws_bin" ] || error "nfqws not found for architecture $ARCH"

    tar xzf $archive "$nfqws_bin" -O > $NFQWS_BIN_GIT
    [ -s $NFQWS_BIN_GIT ] && chmod +x $NFQWS_BIN_GIT
    rm -f $archive
}

download_list()
{
    local list="/tmp/filter.list"

    if [ -f /usr/bin/curl ]; then
        curl -sSL --connect-timeout 5 "$HOSTLIST_DOMAINS" -o $list || error "unable to download $HOSTLIST_DOMAINS"
    else
        wget -q -T 10 "$HOSTLIST_DOMAINS" -O $list || error "unable to download $HOSTLIST_DOMAINS"
    fi

    [ -s "$list" ] && log "downloaded successfully: $HOSTLIST_DOMAINS"
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

unset OPENWRT
[ -f "/etc/openwrt_release" ] && OPENWRT=1

unset NFT
nft -v >/dev/null 2>&1 && NFT=1

# padavan
if [ -x "/usr/sbin/nvram" ]; then
    t="$(nvram get zapret_iface)" && [ -n "$t" ] && ISP_INTERFACE="$t"
    t="$(nvram get zapret_log)" && [ -n "$t" ] && LOG_LEVEL="$t"
    t="$(nvram get zapret_strategy)" && [ -n "$t" ] && STRATEGY_FILE="${STRATEGY_FILE}$t"
    t="$(nvram get zapret_clients_allowed)" && [ -n "$t" ] && CLIENTS_ALLOWED="$t"
    unset t
fi

CLIENTS_ALLOWED=$(echo $CLIENTS_ALLOWED | tr -s ',' ' ' | trim)

unset ISP_IF
if [ "$ISP_INTERFACE" ]; then
    ISP_IF=$(echo "$ISP_INTERFACE" | tr -s ',' ' ' | trim | tr -s ' ' '\n' | sort -u)
else
    ISP_IF4=$(_get_if_default 4)
    ISP_IF6=$(_get_if_default 6)
    ISP_IF=$(printf "%s\n%s" "${ISP_IF4}" "${ISP_IF6}" | sort -u)
fi

set_strategy_file "$2"
TCP_PORTS=$(_get_ports tcp)
UDP_PORTS=$(_get_ports udp)

case "$1" in
    start)
        start_service
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
        start_service
    ;;

    firewall-start)
        firewall_start
    ;;

    firewall-stop)
        firewall_stop
    ;;

    offload-start)
        offload_stop
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
