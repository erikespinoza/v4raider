# v4raider
A collection of settings that allow you to use a public IPv4 on a cheap VPS and
self-host services on your own personal equipment. It does this by running
wireguard and traefik in docker with shared networking. This allows traefik to
act as an http/https proxy using your VPS IPv4 address.

This is for bootstrapping, it is not an end state. 

This uses the official [traefik](https://hub.docker.com/_/traefik) image & the
[linuxserver.io](https://linuxserver.io/)
[wireguard](https://hub.docker.com/r/linuxserver/wireguard) image.

### Why?
* Stuck behind CGNAT
* Your ISP blocks port 80/443

### Settings
* Docker network called dmz, containers in that network can be accessed by
  traefik.
* LetsEncrypt settings for http validation
* Wireguard and Traefik using Google, Cloudflare and Verisign for DNS
* Cloudflare IPs as trusted forwarders
* Legacy ciphers disabled ('A' Score on SSLlabs Test)
* Wireguard Key generation
* Healthcheck for Wireguard connection
* iptables configuration for the VPS
* Default IPs for both ends of the wireguard connection
* Labels for watchtower / ouroboros to update correctly

## Requirements
* VPS w/ public IPv4 address
* A DNS record pointing to the IPv4 address of your VPS
* A host without a public IPv4 address with docker installed

## Recommendation
This works best with Ubuntu 20.04 since the kernel ships with wireguard support
included. This has also been tested on Debian 10 since apt will install
wireguard via dkms. I’m sure the apt commands could be replaced and adapted to
other distributions fairly easily.

## Docker Host (Your Machine)
This host must have docker & docker-compose installed.

1. Install dependencies
: ```sudo apt-get update && sudo apt-get --no-install-recommends install apache2-utils wireguard```
2. Clone this repo
: ```git clone <repo> ; cd v4raider```
3. Set up your environment variables - more info below
: ```cp env.example .env```
4. Edit ```.env``` with your favorite editor and customize. You will require the
   interface name from your VPS. As well as have an A record that points to your
   VPS.
5. Run the script to generate configs
: ```./setup.sh``` 
6. Create dmz network
: ```sudo docker create network dmz```
7. Bring up wireguard and traefik
: ```sudo docker-compose up -d```

This will generate rules.v4 and server-wg0.conf for your VPS.

## External Host (Your VPS)
This host will forward ports to your wireguard and traefik containers. Usually
80 and 443.

1. Remove potential conflict.
: ```sudo apt-get autoremove --purge ufw```
2. Allow ip forwarding
: ```echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf && sudo sysctl -p```
3. Install dependencies
: ```sudo apt-get update && sudo apt-get --no-install-recommends install wireguard iptables-persistent```
4. Place files generated on your docker host in the appropriate location. You
   can scp the files into the appropriate location or just paste in the content
   with your favorite text editor.
: ```server-wg0.conf``` goes to ```/etc/wireguard/wg0.conf``` on this host
: ```rules.v4``` goes to ```/etc/iptables/rules.v4``` on this host
5. Load iptables
: ```sudo iptables-restore /etc/iptables/rules.v4```
6. Start wireguard
: ```sudo systemctl enable --now wg-quick@wg0```

## What now?
Nothing, you're done! Your traefik dashboard should be accessible externally
now. Navigate to https://\<DNS NAME\>/ and enter the username and password you set
in the .env file.

## What about other containers?
Add these settings to your docker-compose.

```
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.<service>.entrypoints=https"
      - "traefik.http.routers.<service>.rule=Host(`<service>.mydomain.tld`)"
      - "traefik.http.routers.<service>.tls=true"
      - "traefik.http.routers.<service>.tls.certresolver=http"
      - "traefik.http.routers.<service>.service=<service>"
      - "traefik.http.services.<service>.loadbalancer.server.port=<Docker Port>"
    networks:
      - dmz

networks:
  dmz:
    external: true
```

You can go to the ```whoami``` directory and change line 10 of the
docker-compose.yml to a CNAME (or second A record) pointing to your VPS. It's
ready to go with a ```docker-compose up -d```.

## Environment File
Be sure to follow the example as closely as possible. Do not use quotes around
variables as docker-compose will choke on it.

| Parameter | Function |
| :----: | --- |
| LE_EMAIL | Email address for LetsEncrypt registration |
| TIMEZONE | Local time zone ex: America/Los_Angeles |
| FORWARDED_PORTS | Usually 80,443 |
| EXT_INTERFACE | External interface of your VPS, ens192 or eth0 |
| WG_HOSTNAME | The A record pointing to your VPS |
| WG_PORT | UDP port for Wireguard |
| AUTH_USER | Traefik Dashboard Username |
| AUTH_PASSWORD | Traefik Dashboard Password |
| DOCKER_DATA_PATH | Where wireguard and traefik will store config |

If you set DOCKER_DATA_PATH, be sure to copy over the traefik and wireguard
subdirectories included.
