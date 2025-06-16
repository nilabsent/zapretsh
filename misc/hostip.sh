#!/bin/sh

# search for unblocked ip addresses for hosts file

sites="
rutracker.org
awsstatic.com
d1.awsstatic.com
aws.amazon.com
vs.aws.amazon.com
amazonwebservices.d2.sc.omtrdc.net
4pda.to
instagram.com
www.instagram.com
static.cdninstagram.com
fb.com
www.fb.com
facebook.com
www.facebook.com
static.xx.fbcdn.net
discord.co
discord.gg
discord.com
discord.app
discord.media
discord.dev
discord.new
discord.gift
discordapp.net
discordapp.com
discordcdn.com
discordstatus.com
dis.gd
discord-attachments-uploads-prd.storage.googleapis.com
x.com
video.twimg.com
abs.twimg.com
gql.twitch.tv
www.twitch.tv
twitch.tv
challenges.cloudflare.com
"

[ "$*" ] && sites="$@"

dns="
158.43.240.3
198.6.100.25
192.76.144.66
195.129.12.122
165.87.13.129
77.88.8.8
94.140.14.14
9.9.9.9
8.26.56.26
144.217.51.168
208.67.222.222
64.6.64.6
168.95.1.1
1.1.1.1
8.8.8.8
"

ips=""

echo "### host list ###"
echo
for i in $sites; do
    for j in $dns; do
        ip=$(timeout 3 nslookup $i $j 2>/dev/null | tail -n+3 | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -n1)
        [ "$ip" ] || continue
        if nc -z -w 1 $ip 443 >/dev/null 2>&1; then
            echo "$ip $i"
            ips=$(printf "%s\n%s" "$ips" "$ip")
            break
        fi
    done
done

echo
echo "### ips list ###"
echo "$ips" | sort -u
