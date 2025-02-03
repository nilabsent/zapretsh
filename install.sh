#!/bin/sh

[ $(id -u) != "0" ] && echo "root user is required to install" && exit 1
cd $(dirname $0)

[ -f /etc/os-release ] && . /etc/os-release

LAZY_MODE="$1"

install_zapret(){
    cp -rf ./zapret/usr /
    chmod +x /usr/bin/zapret.sh
    /usr/bin/zapret.sh download-nfqws && mv /tmp/nfqws /usr/bin && chmod +x /usr/bin/nfqws
    [ "$LAZY_MODE" ] || /usr/bin/zapret.sh download-list
}

lazy_mode(){
    [ "$LAZY_MODE" ] || return
    sed -i 's/<HOSTLIST>/<HOSTLIST_NOAUTO>/g' /etc/zapret/strategy
    > /etc/zapret/auto.list
    > /etc/zapret/user.list
}

install_pkg(){
    if [ -f /usr/bin/apk ]; then 
        PKG_LIST=$(apk list --installed --manifest)
    else
        PKG_LIST=$(opkg list-installed)
    fi
    PKG_DEP="curl iptables-mod-nfqueue iptables-mod-conntrack-extra"
    nft -v >/dev/null 2>&1 && PKG_DEP="curl kmod-nft-queue kmod-nfnetlink-queue"
    PKG=$( for i in $PKG_DEP; do
        echo "$PKG_LIST" | grep -Eqo "^$i " || echo $i
    done )
    [ "$PKG" ] || return
    if [ -f /usr/bin/apk ]; then
        apk update && apk add $PKG
    else
        opkg update && opkg install $PKG
    fi
}

case "$ID" in
    openwrt)
        install_pkg
        install_zapret
        cp -rf ./openwrt/etc /
        chmod +x /etc/init.d/zapret
        sed -i '/zapret.sh/d' /etc/rc.local
        [ "$LAZY_MODE" ] || if grep -q "exit 0" /etc/rc.local; then
            sed -i '/exit 0/i sleep 11 && zapret.sh download-list' /etc/rc.local
        else
            echo "sleep 11 && zapret.sh download-list" >> /etc/rc.local
        fi
        lazy_mode
        /etc/init.d/zapret enable
        /etc/init.d/zapret start
    ;;
    *)
        install_zapret
        [ -s /tmp/filter.list ] && mv /tmp/filter.list /etc/zapret/auto.list
        [ -d /etc/systemd ] || exit
        cp -rf ./linux/etc /
        lazy_mode
        systemctl enable zapret.service
        systemctl start zapret.service
    ;;
esac
