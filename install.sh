#!/bin/sh

[ $(id -u) != "0" ] && echo "root user is required to install" && exit 1
cd $(dirname $0)

[ -f /etc/os-release ] && . /etc/os-release

install_zapret(){
    cp -rf ./zapret/usr /
    chmod +x /usr/bin/zapret.sh
    /usr/bin/zapret.sh download-nfqws && mv /tmp/nfqws /usr/bin && chmod +x /usr/bin/nfqws
    /usr/bin/zapret.sh download-list
}

case "$ID" in
    openwrt)
        opkg update && if nft -v >/dev/null 2>&1; then
            opkg install curl kmod-nft-queue kmod-nfnetlink-queue
        else
            opkg install curl iptables-mod-nfqueue iptables-mod-conntrack-extra
        fi
        install_zapret
        cp -rf ./openwrt/etc /
        chmod +x /etc/init.d/zapret
        sed -i '/zapret.sh/d' /etc/rc.local
        if grep -q "exit 0" /etc/rc.local; then
            sed -i '/exit 0/i sleep 11 && zapret.sh download-list && zapret.sh restart' /etc/rc.local
        else
            echo "sleep 11 && zapret.sh download-list && zapret.sh restart" >> /etc/rc.local
        fi
        /etc/init.d/zapret enable
        /etc/init.d/zapret start
    ;;
    *)
        install_zapret
        [ -s /tmp/filter.list ] && mv /tmp/filter.list /etc/zapret/auto.list
        [ -d /etc/systemd ] || exit
        cp -rf ./linux/etc /
        systemctl enable zapret.service
        systemctl restart zapret.service
    ;;
esac
