#!/bin/bash
# remove MTProxy secret

SECRET="$1"

if [ -z "$SECRET" ]; then
    echo "Usage: delete_proxy.sh <secret>"
    exit 1
fi

sed -i "/$SECRET/d" /etc/mtproxy/secret.list

systemctl restart mtproxy

echo "Secret $SECRET removed."
