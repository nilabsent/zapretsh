#!/bin/sh

[ $(id -u) != "0" ] && echo "root user is required to install" && exit 1
cd $(dirname $0)

[ -s /etc/os-release ] && . /etc/os-release

install_zapret(){
    cp -rf ./zapret/usr /
    chmod +x /usr/bin/zapret.sh
    /usr/bin/zapret.sh download && mv /tmp/nfqws /usr/bin && chmod +x /usr/bin/nfqws
}

install_pkg(){
    if [ -x /usr/bin/apk ]; then 
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
    if [ -x /usr/bin/apk ]; then
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
        /etc/init.d/zapret enable
        /etc/init.d/zapret start
    ;;
    *)
        install_zapret
        [ -d /etc/systemd ] || exit
        cp -rf ./linux/etc /
        systemctl enable zapret.service
        systemctl start zapret.service
    ;;
esac
