for openwrt versions 21 and above (iptables):
opkg install iptables-mod-nfqueue iptables-mod-conntrack-extra

for openwrt versions 22 and later (nftables):
opkg install kmod-nft-queue kmod-nfnetlink-queue

for linux with nftables may need to install:

debian: libnetfilter-conntrack3 libnetfilter-queue1

arch: libnetfilter-conntrack libnetfilter-queue

nfqws binary: https://github.com/bol-van/zapret
place nfqws of required architecture in usr/bin
