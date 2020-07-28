#!/bin/bash

# Use common vars from .env
source .env

# Ensure exit is properly trapped
trap "exit $?" TERM

# Set sane path
PATH="/bin:/usr/bin:/sbin:/usr/sbin"

# Set error Handlers
error_exit() {
	echo "$(date) - ERROR - ${ERRMSG}"
	exit 1
}

# Ensure requirements are installed
reqs_check() {
	# Check for dependencies
	ERRMSG="Dependency missing. Recommend 'sudo apt-get --no-install-recommends install apache2-utils wireguard'"
	which htpasswd &>/dev/null || error_exit
	which wg &>/dev/null || error_exit
}

# Generate key pairs
gen_keys() {
	# Generate keys, first run only.

	PRIVKEY_WG_CLIENT="$(wg genkey)"
	echo "PRIVKEY_WG_CLIENT=${PRIVKEY_WG_CLIENT}" >> .env

	PUBKEY_WG_CLIENT="$(echo ${PRIVKEY_WG_CLIENT} | wg pubkey)"
	echo "PUBKEY_WG_CLIENT=${PUBKEY_WG_CLIENT}" >> .env
	
	PRIVKEY_WG_SERVER="$(wg genkey)"
	echo "PRIVKEY_WG_SERVER=${PRIVKEY_WG_SERVER}" >> .env
	
	PUBKEY_WG_SERVER="$(echo ${PRIVKEY_WG_SERVER} | wg pubkey)"
	echo "PUBKEY_WG_SERVER=${PUBKEY_WG_SERVER}" >> .env
}

# Generate server and client config files
gen_wg_conf() {
	# Create wg0.conf for client
	cat > ${DOCKER_DATA_PATH}/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = ${PRIVKEY_WG_CLIENT}
Address = 10.1.0.2/30

[Peer]
PublicKey = ${PUBKEY_WG_SERVER}
AllowedIPs = 0.0.0.0/0
Endpoint = ${WG_HOSTNAME}:${WG_PORT}
PersistentKeepalive = 20
EOF
	chmod 600 ${DOCKER_DATA_PATH}/wireguard/wg0.conf

	# Create wg0.conf for server
	cat > ${DOCKER_DATA_PATH}/server-wg0.conf <<EOF
[Interface]
Address = 10.1.0.1/30
ListenPort = ${WG_PORT}
PrivateKey = ${PRIVKEY_WG_SERVER}

[Peer]
PublicKey = ${PUBKEY_WG_CLIENT}
AllowedIPs = 10.1.0.2/32
EOF

	# Create iptables for server
	cat > ${DOCKER_DATA_PATH}/rules.v4 <<EOF
# Generated NAT Rules
*nat
:PREROUTING ACCEPT [58399:9586820]
:INPUT ACCEPT [724:63142]
:OUTPUT ACCEPT [43:3206]
:POSTROUTING ACCEPT [794:45242]
-A PREROUTING -i ${EXT_INTERFACE} -p tcp -m multiport --dports ${FORWARDED_PORTS} -j DNAT --to-destination 10.1.0.2
-A POSTROUTING -s 10.1.0.2/32 -o ${EXT_INTERFACE} -j MASQUERADE
COMMIT
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [37561:13433091]
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -i wg0 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m multiport --dports ${FORWARDED_PORTS} -j ACCEPT
-A INPUT -p udp -m udp --dport ${WG_PORT} -j ACCEPT
-A FORWARD -s 10.1.0.2/32 -i wg0 -o ${EXT_INTERFACE} -j ACCEPT
-A FORWARD -d 10.1.0.2/32 -i ${EXT_INTERFACE} -o wg0 -p tcp -m multiport --dports ${FORWARDED_PORTS} -j ACCEPT
-A FORWARD -d 10.1.0.2/32 -i ${EXT_INTERFACE} -o wg0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
COMMIT
EOF
}

# Configure e-mail for traefik ACME / LetsEncrypt
config_le() {
	ERRMSG="Failed to update LetsEncrypt Email"
	sed -i.bak "s#email: .*#email: ${LE_EMAIL}#g" ${DOCKER_DATA_PATH}/traefik/traefik.yml || error_exit
}

# Set basic auth for traefik
config_auth() {
	ERRMSG="Failed to set auth password for traefik"
	USER_AUTH="$(htpasswd -nb ${AUTH_USER} ${AUTH_PASSWORD} | sed -e s/\\$/\\$\\$/g | head -1)"
	sed -i.bak "s#traefik-auth.basicauth.users=.*#traefik-auth.basicauth.users=${USER_AUTH}\"#g" docker-compose.yml || error_exit
}

reqs_check
test -n "${PUBKEY_WG_SERVER}" || gen_keys
gen_wg_conf
config_le
config_auth
touch ${DOCKER_DATA_PATH}/traefik/acme.json && chmod 600 ${DOCKER_DATA_PATH}/traefik/acme.json

echo "Finished setup. Please run 'sudo docker network create dmz'"
