# Home Lab Server

Ansible scripts to deploy the homelab services at matbooth.co.uk.

## Roles

Purpose of the top level roles:

* id - User identity provider and SSO service for other apps
* photos - Immich for photo and video management
* ci - Jenkins for on-prem continuous integration
* sshd - SSH for restricted user shell accounts
* admin - Cockpit for system administration and monitoring
* cams - Zoneminder for CCTV monitoring and recording
* hab - OpenHAB for home automation
* spotify - Spotify Connect implementation to play music through the big stereo

### Dependencies

This dependency graph show roughly how the roles all hang together:

![Role Dependency Graph](depgraph.png)

## Pre-requisites

### Key Server

Clevis is used for automatic boot-time decryption of LUKS encrypted volumes using keys stored in a Tang server. There is a DHCP reservation for my main workstation at `192.168.1.11`, and Clevis expects Tang to be running there. Installation process for that is as follows:

```
# dnf install tang
# semanage port -a -t tangd_port_t -p tcp 7500
# firewall-cmd --zone=libvirt --add-port=7500/tcp
# cat <<EOF | sudo tee -a /etc/systemd/system/tangd.socket.d/override.conf
[Socket]
ListenStream=
ListenStream=7500
EOF
# systemctl daemon-reload
# systemctl enable --now tangd.socket
```

### Router Configuration

When using the ISP supplied router, some configuration is needed to make everything work nicely with the self-hosted network services. This section lists settings changed from the router defaults.

Connect to the router as user 'engineer' and the same password as the web interface. This gives access to the Technicolor CLI, which is loosely based on OpenWRT/uci:

```
$ ssh engineer@192.168.1.1
engineer@192.168.1.1's password:
engineer>
```

Disable DHCP services on the router, we are providing our own DHCP:

```
set uci.dhcp.dhcp.@lan.dhcpv4 disabled
set uci.dhcp.dhcp.@lan.dhcpv6 disabled
apply
```

Announce our own DNS server in IPv6 router advertisements. Prevents LAN clients from incorrectly getting the router as a DNS server in addition to those configured by DHCP, which could result in confusing failures if the client picked the wrong DNS server to attempt name resolution:

```
add uci.dhcp.dhcp.@lan.dns.
set uci.dhcp.dhcp.@lan.dns.@1.value 2001:8b0:a722::a
apply
```

The above means LAN clients shouldn't use the router for DNS, but if they do, we need to forward DNS queries for `matbooth.co.uk` names to our own DNS server. This means LAN clients that ask the router get LAN addresses rather than external ones that can't be routed:

```
add uci.dhcp.dnsmasq.@dnsmasq.server.
set uci.dhcp.dnsmasq.@dnsmasq.server.@1.value /matbooth.co.uk/192.168.1.10
add uci.dhcp.dnsmasq.@dnsmasq.rebind_domain.
set uci.dhcp.dnsmasq.@dnsmasq.rebind_domain.@1.value matbooth.co.uk
apply
```

### Router Firewall Rules

Use the web interface to forward ports 80, 443, and 22 to `192.168.1.10` for Apache and SSHd.

Port forwarding configures IPv4 NAT firewall rules, but there seems to be no UI for IPv6 "pinhole" firewall rules. The router has pre-configured pinholes for ports 80 and 443, they just need to be given either the IPv6 address, or MAC address, of the server to be routable:

```
set uci.firewall.pinholerule.@pinholerule4E3A.dest_ip 2001:8b0:a722::a
set uci.firewall.pinholerule.@pinholerule4E3A.dest_mac ""
set uci.firewall.pinholerule.@pinholeruleC3A6.dest_ip 2001:8b0:a722::a
set uci.firewall.pinholerule.@pinholeruleC3A6.dest_mac ""
apply
```

There is no pre-configured pinhole for port 22, so add one for SSHd:

```
add uci.firewall.pinholerule.
set uci.firewall.pinholerule.@pinholerule[2].name SSH6 Server
set uci.firewall.pinholerule.@pinholerule[2].family ipv6
set uci.firewall.pinholerule.@pinholerule[2].src wan
set uci.firewall.pinholerule.@pinholerule[2].dest lan
set uci.firewall.pinholerule.@pinholerule[2].dest_ip 2001:8b0:a722::a
set uci.firewall.pinholerule.@pinholerule[2].dest_port 22
set uci.firewall.pinholerule.@pinholerule[2].target ACCEPT
set uci.firewall.pinholerule.@pinholerule[2].enabled 1
add uci.firewall.pinholerule.@pinholerule[2].proto.
set uci.firewall.pinholerule.@pinholerule[2].proto.@1.value tcp
apply
```

Don't masquerade traffic forwarded into the LAN, so servers see real client addresses instead of the router's address. This makes server logs more useful, allows us to restrict incoming connections for some services to LAN-local address only, and allows fail2ban to be used on incoming connections from outside the LAN:

```
set uci.firewall.zone.@lan.masq 0
apply
```

### Kerberos Authentication

To enable Kerberos authentication from outside the LAN, especially from locations with restricted WiFi networks (such as hotels or cafés that don't allow traffic on non-HTTP ports) a proxy is used to route KDC traffic over the HTTPS port. To make this mechanism discoverable to Kerberos clients, the following records need to be added to the public-facing DNS:

```
_kerberos.matbooth.co.uk.  URI  10 1  "krb5srv:m:kkdcp:https://krb.matbooth.co.uk/KdcProxy"
_kpasswd.matbooth.co.uk.   URI  10 1  "krb5srv:m:kkdcp:https://krb.matbooth.co.uk/KdcProxy"
```

If the public-facing DNS provider doesn't support URI records, then extra configuration is required on the workstation to enable Kerberos authentication:

```
$ sudo tee /etc/krb5.conf.d/matbooth_co_uk <<'EOF'
[realms]
 MATBOOTH.CO.UK = {
   kdc = https://krb.matbooth.co.uk/KdcProxy
   kpasswd_server = https://krb.matbooth.co.uk/KdcProxy
 }
[domain_realm]
 .matbooth.co.uk = MATBOOTH.CO.UK
 matbooth.co.uk = MATBOOTH.CO.UK
EOF
```

### Workstation

To allow browsers to trust the staging environment TLS certificates, add the self-signed certificate authority to the system's trust store and then restart your browser:

```
$ sudo cp roles/tls/files/CA.pem /etc/pki/ca-trust/source/anchors/
$ sudo update-ca-trust
```

## First Run

```
$ ./run.sh        # Staging VM
$ PROD=1 ./run.sh # Real hardware
```

If a machine has not yet been provisioned, the script will provision a VM (staging) or boot USB stick to be used on real hardware (production).

Once provisioned, a bootstrap playbook will be executed to configure fundamentals like network adapters, user accounts, public key authentication, LUKS decryption, etc.

## Subsequent Runs

```
$ ./run.sh        # Staging VM
$ PROD=1 ./run.sh # Real hardware
```

Subsequent runs will execute the main playbooks to install and configure all the services. Provisioning and bootstrapping will be skipped.

