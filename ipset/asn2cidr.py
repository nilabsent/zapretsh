#!/usr/bin/env python3
#
# asn2cidr.py
#
# Download and process bgp.tools routing table, extracting and
# aggregating IPv4 prefixes for one or more Autonomous System Numbers.
#
# Usage:
#   ./asn2cidr.py download
#   ./asn2cidr.py update
#
# Author: nil
# AI-assisted development: ChatGPT (OpenAI)
#

import argparse
import ipaddress
import pathlib
import urllib.request
import sys
import subprocess
from collections import defaultdict

TABLE_URL = "https://bgp.tools/table.txt"
TABLE_FILE = pathlib.Path("table.txt")
OUTPUT_DIR = pathlib.Path("ipv4")

AS_LIST = {
    "amazon": ( 16509, 14618, 7224, 21664, 401395, 801, 62785, ),
    "cloudflare": ( 13335, 14789, 395747, 400095, 402542, ),
    "contabo": ( 51167, 40021, 141995, ),
    "digitalocean": ( 14061, ),
    "ovh": ( 16276, ),
    "hetzner": ( 24940, 213230, 212317, ),
    "akamai": ( 20940, 200005, 12222, 24319, 35994, 34164, 16625, 31108, 21342, 213120, 33905, ),
    "oracle": ( 31898, 54253, 6142, 14544, 20054, ),
    "telegram": ( 62041, 62014, 59930, 44907, 211157, ),
    "meta": ( 63293, 32934, ),
}

def download_table():
    print(f"Downloading {TABLE_URL}...")

    subprocess.run(
        ["wget", "-O", str(TABLE_FILE), TABLE_URL],
        check=True,
    )

    print("Done.")


def load_table():
    """
    Читает table.txt один раз и возвращает:

        {
            "amazon": {IPv4Network(...), ...},
            "telegram": {IPv4Network(...), ...},
            ...
        }
    """

    # ASN -> имя ipset
    asn_map = {}

    for name, asns in AS_LIST.items():
        for asn in asns:
            asn_map[str(asn)] = name

    result = defaultdict(set)

    with TABLE_FILE.open("r", encoding="ascii") as f:
        for line in f:

            # IPv6 пропускаем
            if "." not in line:
                continue

            fields = line.split()
            if len(fields) < 2:
                continue

            prefix = fields[0]
            asn = fields[1]

            name = asn_map.get(asn)
            if name is None:
                continue

            try:
                result[name].add(ipaddress.IPv4Network(prefix))
            except ValueError:
                print(f"Invalid prefix: {prefix}", file=sys.stderr)

    return result


def update():

    if not TABLE_FILE.exists():
        print("table.txt not found. Run 'download' first.", file=sys.stderr)
        sys.exit(1)

    OUTPUT_DIR.mkdir(exist_ok=True)

    table = load_table()

    for name in sorted(AS_LIST):

        print(name)

        outfile = OUTPUT_DIR / f"{name}.txt"

        with outfile.open("w") as f:
            for network in ipaddress.collapse_addresses(table.get(name, ())):
                f.write(f"{network}\n")


def main():

    parser = argparse.ArgumentParser(
        description="Download and aggregate IPv4 prefixes by ASN"
    )

    sub = parser.add_subparsers(dest="command")

    sub.add_parser("download", help="Download BGP table")
    sub.add_parser("update", help="Generate aggregated prefix lists")

    args = parser.parse_args()

    if args.command == "download":
        download_table()

    elif args.command == "update":
        update()

    else:
        parser.print_help()


if __name__ == "__main__":
    main()
