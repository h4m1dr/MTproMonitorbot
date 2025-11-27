#!/bin/bash
# create new MTProxy secret

SECRET=$(openssl rand -hex 16)

echo "Created secret: $SECRET"

# write to config
echo "$SECRET" >> /etc/mtproxy/secret.list

# reload service
systemctl restart mtproxy

# generate tg-link
IP=$(curl -s ifconfig.me)
PORT=443
echo "tg://proxy?server=$IP&port=$PORT&secret=ee$SECRET"
