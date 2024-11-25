#!/bin/bash

# Configuration Variables
ADMIN_USER="${admin_username}"
ADMIN_PASS="${admin_password}"
DEV_USER="${dev_username}"
DEV_PASS="${dev_password}"
DOMAIN="${domain}"
EMAIL="${email}"
VPN_SUBNET="${subnet_cidr}"
export DEBIAN_FRONTEND=noninteractive

# Update and upgrade system packages
sudo apt-get update && sudo apt-get upgrade -y

# Install necessary packages for OpenVPN Access Server and Nginx
sudo apt-get install -y ca-certificates wget net-tools gnupg nginx certbot python3-certbot-nginx

# Ensure Nginx is running
sudo systemctl enable nginx
sudo systemctl start nginx

# Install OpenVPN Access Server
wget https://as-repository.openvpn.net/as-repo-public.asc -qO /etc/apt/trusted.gpg.d/as-repository.asc
echo "deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/as-repository.asc] http://as-repository.openvpn.net/as/debian jammy main">/etc/apt/sources.list.d/openvpn-as-repo.list
apt update && apt -y install openvpn-as

# Start the OpenVPN AS service
sudo systemctl start openvpnas

# Configure admin and dev credentials
sudo /usr/local/openvpn_as/scripts/sacli --key "host.name" --value "$DOMAIN" ConfigPut
sudo /usr/local/openvpn_as/scripts/sacli --key "admin_ui.https.ip_address" --value "all" ConfigPut
sudo /usr/local/openvpn_as/scripts/sacli --key "cs.https.ip_address" --value "all" ConfigPut
sudo /usr/local/openvpn_as/scripts/sacli --user $ADMIN_USER --new_pass=$ADMIN_PASS SetLocalPassword
sudo /usr/local/openvpn_as/scripts/sacli --user $DEV_USER --new_pass=$DEV_PASS SetLocalPassword

# Enable IP forwarding
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Apply NAT rule for IP Masquerade
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables-save

# Push route to VPN clients
sudo /usr/local/openvpn_as/scripts/sacli --key "vpn.server.routing.private_access" --value "nat" ConfigPut
sudo /usr/local/openvpn_as/scripts/sacli --key "vpn.server.routing.private_network.0" --value "$VPN_SUBNET" ConfigPut
sudo /usr/local/openvpn_as/scripts/sacli start

# Install Certbot
sudo apt-get update
sudo apt-get install -y certbot

# Obtain Let's Encrypt certificate using webroot method
sudo certbot certonly --webroot -w /var/www/html -d $DOMAIN --non-interactive --agree-tos -m $EMAIL > /dev/null 2>&1 &

# Wait for the certificate installation to complete
wait

# Set up automatic renewal with a post-hook to restart OpenVPN AS after renewal
(crontab -l 2>/dev/null; echo "0 0 1 * * certbot renew --standalone --pre-hook 'systemctl stop openvpnas' --post-hook 'systemctl start openvpnas'") | crontab -

# Configure OpenVPN AS to use the Let's Encrypt certificate
LE_PATH="/etc/letsencrypt/live/$DOMAIN"
sudo /usr/local/openvpn_as/scripts/confdba -mk cs.ca_bundle -v "$(sudo cat $LE_PATH/chain.pem)"
sudo /usr/local/openvpn_as/scripts/confdba -mk cs.priv_key -v "$(sudo cat $LE_PATH/privkey.pem)"
sudo /usr/local/openvpn_as/scripts/confdba -mk cs.cert -v "$(sudo cat $LE_PATH/cert.pem)"
sudo systemctl restart openvpnas
echo "SSL certificate obtained successfully."

# Remove Nginx after completing the main tasks
sudo apt-get remove --purge -y nginx nginx-common
sudo apt-get autoremove -y

# Reset DEBIAN_FRONTEND
unset DEBIAN_FRONTEND

echo " - OpenVPN installation completed."
