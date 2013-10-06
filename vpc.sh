#!/bin/bash
#
# Setup a VPC IPSEC connectivity
# Oct 5, 2013

if [[ -z $1 ]];
then
	echo "No file specified."
	exit 1
fi

if [[ ! -s $1 ]];
then
	echo "Not a valid file."
	exit 1
fi

# Install needed applications
apt-get install ipsec-tools racoon quagga

# Define user variables
REMOTE_NET="192.168.200.0/24"
WAN_INT="eth1"
SOFT_ROUTER_PASSWORD="testPassword"

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
cat << EOF >> /etc/racoon/psk.txt
# VPC IPSEC
$T1_OIP_PG $T1_PSK
$T2_OIP_PG $T2_PSK
EOF


# Racoon
cat << EOF > /etc/racoon/racoon.conf

# VPC IPSEC

log notify;
path pre_shared_key "/etc/racoon/psk.txt";

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
        my_identifier address $T2_OIP_CG;
	peers_identifier address $T2_OIP_PG;

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
        my_identifier address $T1_OIP_CG;
	peers_identifier address $T1_OIP_PG;

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


# IP Alias
ip a a $T1_IIP_CG dev $WAN_INT
ip a a $T2_IIP_CG dev $WAN_INT

service racoon restart
service setkey restart

# Tunnel should be up by now. Now setup BGP

sed -i 's/zebra\=no/zebra=yes/' /etc/quagga/daemons
sed -i 's/bgpd\=no/bgpd=yes/' /etc/quagga/daemons


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
network 0.0.0.0/0
!
! aws tunnel #1 neighbour
neighbor $T1_NEIGHBOR_IP remote-as $T1_REMOTE_AS
!
! aws tunnel #2 neighbour
neighbor $T2_NEIGHBOR_IP remote-as $T2_REMOTE_AS
!
line vty
EOF


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

service quagga restart

# make service autorun
