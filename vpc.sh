#!/bin/bash
#
# Setup a VPC IPSEC connectivity
# Oct 5, 2013

exec 2>&1

error() {
	echo "$@" >&2
	exit 1
}

# Some basic checks
[ -z "$1" ] && error "Usage: $0 <generic-config-file-from-amazon.txt>"
[ -r "$1" ] || error "Could not read VPN config file $1."
[ "`id -u`" = 0 ] || error "You must be root to run this program."


# Install needed applications. Modify this line for CentOS.
apt-get install ipsec-tools racoon quagga

# Define user variables

# Amazon-side subnet
REMOTE_NET="10.10.20.0/24"

# Local WAN interface
WAN_INT="eth1"
SOFT_ROUTER_PASSWORD="testPassword"

# Extract IP / networks from generic amazon config file
T1_OIP_CG=$(cat $1 |grep -m 1 "\- Customer Gateway" | tail -1 | awk '{print $5}')
T1_OIP_PG=$(cat $1 |grep -m 1 "\- Virtual Private Gateway" | tail -1 | awk '{print $6}')
T1_IIP_CG=$(cat $1 |grep -m 2 "\- Customer Gateway" | tail -1 | awk '{print $5}')
T1_IIP_PG=$(cat $1 |grep -m 2 "\- Virtual Private Gateway" | tail -1 | awk '{print $6}')
T2_OIP_CG=$(cat $1 |grep -m 4 "\- Customer Gateway" | tail -1  | awk '{print $5}')
T2_OIP_PG=$(cat $1 |grep -m 3 "\- Virtual Private Gateway" | tail -1 | awk '{print $6}')
T2_IIP_CG=$(cat $1 |grep -m 5 "\- Customer Gateway" | tail -1 | awk '{print $5}')
T2_IIP_PG=$(cat $1 |grep -m 4 "\- Virtual Private Gateway" | tail -1 | awk '{print $6}')
T1_PSK=$(cat $1 | grep  -m 1 "\- Pre-Shared Key" | tail -1 | awk '{print $5}')
T2_PSK=$(cat $1 | grep  -m 2 "\- Pre-Shared Key" | tail -1 | awk '{print $5}')
T1_REMOTE_AS=$(cat $1 | grep -m 1 'Virtual Private  Gateway ASN' | tail -1 |  awk '{print $7}')
T2_REMOTE_AS=$(cat $1 | grep -m 2 'Virtual Private  Gateway ASN' | tail -1 |  awk '{print $7}')
T1_NEIGHBOR_IP=$(cat $1 | grep -m 1 "Neighbor IP Address" | tail -1 | awk '{print $6}')
T2_NEIGHBOR_IP=$(cat $1 | grep -m 2 "Neighbor IP Address" | tail -1 | awk '{print $6}')
CONNECTION_ID=$(cat $1 | grep 'Your VPN Connection ID' | awk '{print $6}')

# Check weather we got all the values
[ -z "$T1_OIP_CG" ]		&& error "Could not extract T1_OIP_CG from $1."
[ -z "$T1_OIP_PG" ]		&& error "Could not extract T1_OIP_PG from $1."
[ -z "$T1_IIP_CG" ]		&& error "Could not extract T1_IIP_CG from $1."
[ -z "$T1_IIP_PG" ]		&& error "Could not extract T1_IIP_PG from $1."
[ -z "$T2_OIP_CG" ]		&& error "Could not extract T2_OIP_CG from $1."
[ -z "$T2_OIP_PG" ]		&& error "Could not extract T2_OIP_PG from $1."
[ -z "$T2_IIP_CG" ]		&& error "Could not extract T2_IIP_CG from $1."
[ -z "$T2_IIP_PG" ]		&& error "Could not extract T2_IIP_PG from $1."
[ -z "$T1_PSK" ]		&& error "Could not extract T1_PSK from $1."
[ -z "$T2_PSK" ]		&& error "Could not extract T2_PSK from $1."
[ -z "$T1_REMOTE_AS" ]		&& error "Could not extract T1_REMOTE_AS from $1."
[ -z "$T2_REMOTE_AS" ]		&& error "Could not extract T2_REMOTE_AS from $1."
[ -z "$T1_NEIGHBOR_IP" ]	&& error "Could not extract T1_NEIGHBOR_IP from $1."
[ -z "$T2_NEIGHBOR_IP" ]	&& error "Could not extract T2_NEIGHBOR_IP from $1."


# Setkey config
cat << EOF > /etc/ipsec-tools.d/awsvpc.conf
flush;
spdflush;

spdadd $T1_IIP_CG $T1_IIP_PG any -P out ipsec
   esp/tunnel/$T1_OIP_CG-$T1_OIP_PG/require;

spdadd $T1_IIP_PG $T1_IIP_CG any -P in ipsec
   esp/tunnel/$T1_OIP_PG-$T1_OIP_CG/require;

spdadd $T2_IIP_CG $T2_IIP_PG any -P out ipsec
   esp/tunnel/$T2_OIP_CG-$T2_OIP_PG/require;

spdadd $T2_IIP_PG $T2_IIP_CG any -P in ipsec
   esp/tunnel/$T2_OIP_PG-$T2_OIP_CG/require;

spdadd $T1_IIP_CG $REMOTE_NET any -P out ipsec
   esp/tunnel/$T1_OIP_CG-$T1_OIP_PG/require;

spdadd $REMOTE_NET $T1_IIP_CG any -P in ipsec
   esp/tunnel/$T1_OIP_PG-$T1_OIP_CG/require;

spdadd $T2_IIP_CG $REMOTE_NET any -P out ipsec
   esp/tunnel/$T2_OIP_CG-$T2_OIP_PG/require;

spdadd $REMOTE_NET $T2_IIP_CG any -P in ipsec
   esp/tunnel/$T2_OIP_PG-$T2_OIP_CG/require;
EOF

# Pre-shared key file
cat << EOF > /etc/racoon/$CONNECTION_ID.txt
# VPC IPSEC
$T1_OIP_PG $T1_PSK
$T2_OIP_PG $T2_PSK
EOF


# Racoon
cat << EOF > /etc/racoon/racoon.conf
# VPC IPSEC

log notify;
path pre_shared_key "/etc/racoon/$CONNECTION_ID.txt";

remote $T2_OIP_PG {
        exchange_mode main;
        lifetime time 28800 seconds;
        proposal {
                encryption_algorithm aes128;
                hash_algorithm sha1;
                authentication_method pre_shared_key;
                dh_group 2;
        }
        generate_policy off;
#       my_identifier address $T2_OIP_CG;
#	peers_identifier address $T2_OIP_PG;

}

remote $T1_OIP_PG {
        exchange_mode main;
        lifetime time 28800 seconds;
        proposal {
                encryption_algorithm aes128;
                hash_algorithm sha1;
                authentication_method pre_shared_key;
                dh_group 2;
        }
        generate_policy off;
#       my_identifier address $T1_OIP_CG;
#	peers_identifier address $T1_OIP_PG;

}

sainfo address $T1_IIP_CG any address $T1_IIP_PG any {
    pfs_group 2;
    lifetime time 3600 seconds;
    encryption_algorithm aes128;
    authentication_algorithm hmac_sha1;
    compression_algorithm deflate;
}

sainfo address $T2_IIP_CG any address $T2_IIP_PG any {
    pfs_group 2;
    lifetime time 3600 seconds;
    encryption_algorithm aes128;
    authentication_algorithm hmac_sha1;
    compression_algorithm deflate;
}
EOF


# IP Alias for tunnel. Everything sent through this tunnel will be encrypted
ip a a $T1_IIP_CG dev $WAN_INT
ip a a $T2_IIP_CG dev $WAN_INT

# Enable zebra and bgpd
sed -i 's/zebra\=no/zebra=yes/' /etc/quagga/daemons
sed -i 's/bgpd\=no/bgpd=yes/' /etc/quagga/daemons

# bgpd config
cat << EOF > /etc/quagga/bgpd.conf
hostname ec2-vpn
password $SOFT_ROUTER_PASSWORD
enable password $SOFT_ROUTER_PASSWORD
!
log file /var/log/quagga/bgpd
!debug bgp events
!debug bgp zebra
debug bgp updates
!
router bgp 65000
bgp router-id $T1_OIP_CG
network $T1_IIP_CG
network $T2_IIP_CG
!network 0.0.0.0/0
!
! aws tunnel #1 neighbour
neighbor $T1_NEIGHBOR_IP remote-as $T1_REMOTE_AS
!
! aws tunnel #2 neighbour
neighbor $T2_NEIGHBOR_IP remote-as $T2_REMOTE_AS
!
line vty
EOF

# zebra config
cat << EOF > /etc/quagga/zebra.conf
hostname ec2-vpn
password $SOFT_ROUTER_PASSWORD
enable password $SOFT_ROUTER_PASSWORD
!
! list interfaces
interface $WAN_INT
interface lo
!
line vty
EOF

# start the services
service racoon restart
service setkey restart
service quagga restart

echo "You may now ping the following tunnel IPs $T1_IIP_PG and $T2_IIP_PG."
