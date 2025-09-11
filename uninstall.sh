#!/bin/sh

[ $(id -u) != "0" ] && echo "root user is required to install" && exit 1
cd $(dirname $0)

[ -s /etc/os-release ] && . /etc/os-release

remove_zapret(){
    [ -x /usr/bin/zapret.sh ] && zapret.sh stop
    rm -f /usr/bin/zapret.sh /usr/bin/nfqws /tmp/filter.list
    rm -rf /usr/share/zapret /etc/zapret
}

case "$ID" in
    openwrt)
        if [ -f /etc/init.d/zapret ]; then
            /etc/init.d/zapret stop >/dev/null 2>&1
            /etc/init.d/zapret disable
        fi
        rm -f /etc/init.d/zapret /etc/firewall.zapret
        uci -q del firewall.zapret && uci commit
        remove_zapret
        /etc/init.d/firewall restart >/dev/null 2>&1
    ;;
    *)
        if [ -f /etc/systemd/system/zapret.service ]; then
            systemctl stop zapret.service
            systemctl disable zapret.service
            rm -f /etc/systemd/system/zapret.service
        fi
        remove_zapret
    ;;
esac
