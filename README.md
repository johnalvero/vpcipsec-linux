vpcipsec-linux
==============

A script that simplies the setup and configuration of Amazon VPC + IPSec + Racoon + Quagga/BGP.

It takes an Amazon config file and performs the necessary step for bringing up the two tunnels and setting up BGP. Make sure to download the "Generic / Vendor Agnostic" config and save it as vpn.txt. When creating the VPN tunnel, remember to choose BGP routing as opposed to static routing.


Usage:

./vpc.sh vpn.txt

Note: Run the script as root user. Tested with Ubuntu 12.04.
