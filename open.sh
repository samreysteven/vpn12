#!/bin/bash
#OpenVPN Installer for Centos 5 & 6
#Prequisites: 
#Known issues Centos 6 isnt currently working due to ca.crt error
#Written by Onessa credits to Keith from SaveSrv.net for tutorial I used as base Original Tutorial > https://safesrv.net/install-openvpn-on-centos/
if [ $USER != 'root' ]
then
echo "REQUIRES ROOT"
exit 0
fi

###Determine OS Version and Architecture
read -p "What version of Centos are you Running? [5,6]?" VERSION
echo $VERSION
ARCH=$(uname -m | sed 's/x86_//;s/i[3-6]86/32/')

###Determine Server IP
yum install wget -y
IP=$(wget -qO- ifconfig.me/ip)

###Installing OpenVpn Dependicies
echo Installing OpenVpn Dependicies
yum install iptables gcc make rpm-build autoconf.noarch zlib-devel pam-devel openssl-devel -y
echo Installed OpenVpn Dependicies

###Download LZO RPM and Configure RPMForge Repo
wget http://openvpn.net/release/lzo-1.08-4.rf.src.rpm
echo Downloaded LZO RPM

##Download RPMForge Repo
if [[ "$VERSION" = "5" && "$ARCH" = "32" ]]
then
    wget http://packages.sw.be/rpmforge-release/rpmforge-release-0.5.2-2.el5.rf.i386.rpm
elif [[ "$VERSION" = "5" && "$ARCH" = "64" ]]
then
    wget http://packages.sw.be/rpmforge-release/rpmforge-release-0.5.2-2.el5.rf.x86_64.rpm
elif [[ "$VERSION" = "6" && "$ARCH" = "32" ]]
then
    wget http://pkgs.repoforge.org/rpmforge-release/rpmforge-release-0.5.2-1.el6.rf.i686.rpm
elif [[ "$VERSION" = "6" && "$ARCH" = "64" ]]
then
    wget http://pkgs.repoforge.org/rpmforge-release/rpmforge-release-0.5.2-2.el6.rf.x86_64.rpm
fi

echo Downloaded Centos $VERSION $ARCH Rpmforge RPM

###Build the rpm packages
rpmbuild --rebuild lzo-1.08-4.rf.src.rpm
rpm -Uvh lzo-*.rpm
rpm -Uvh rpmforge-release*
echo rpm packages built

###Install OpenVPN
yum install openvpn -y
echo Openvpn installed

###Copy the easy-rsa folder to /etc/openvpn/
cp -R /usr/share/doc/openvpn-2.2.2/easy-rsa/ /etc/openvpn/
echo easy-rsa copied to /etc/openvpn/

###CentOS 6 patch for /etc/openvpn/easy-rsa/2.0/vars
#OLDRSA="export KEY_CONFIG=`$EASY_RSA\/whichopensslcnf $EASY_RSA`"
#NEWRSA="export KEY_CONFIG=\/etc\/openvpn\/easy-rsa\/2.0\/openssl-1.0.0.cnf"
if [ ["$VERSION" = "6" ];
then 
    sed -i 's/export KEY_CONFIG=`$EASY_RSA\/whichopensslcnf $EASY_RSA`/export KEY_CONFIG=\/etc\/openvpn\/easy-rsa\/2.0\/openssl-1.0.0.cnf/g'  /etc/openvpn/easy-rsa/2.0/vars
fi

###Now let’s create the certificate
cd /etc/openvpn/easy-rsa/2.0
chmod 755 *
source ./vars
./vars
./clean-all

###Build CA
cd /etc/openvpn/easy-rsa/2.0
./build-ca
echo certificate built

###Build key Server
cd /etc/openvpn/easy-rsa/2.0
./build-key-server server
echo key Server built

###Build Diffie Hellman
echo Build Diffie Hellman
./build-dh
echo Diffie Hellman built

###Create OpenVPN server conf
touch /etc/openvpn/server.conf
echo "local 123.123.123.123 #- your_server_ip goes here
port 1194 #- port
proto udp #- protocol
dev tun
tun-mtu 1500
tun-mtu-extra 32
mssfix 1450
ca /etc/openvpn/easy-rsa/2.0/keys/ca.crt
cert /etc/openvpn/easy-rsa/2.0/keys/server.crt
key /etc/openvpn/easy-rsa/2.0/keys/server.key
dh /etc/openvpn/easy-rsa/2.0/keys/dh1024.pem
plugin /usr/share/openvpn/plugin/lib/openvpn-auth-pam.so /etc/pam.d/login
client-cert-not-required
username-as-common-name
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 5 30
comp-lzo
persist-key
persist-tun
status 1194.log
verb 3
reneg-sec 0" > '/etc/openvpn/server.conf'
sed -i s/123.123.123.123/$IP/g /etc/openvpn/server.conf
echo default server copied to /etc/openvpn/server.conf


###Start OpenVPN and Chkconfig it to autostart on boot
service openvpn start
chkconfig openvpn on

###enable IP forwarding
sed -i 's/net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/g' /etc/sysctl.conf
sysctl -p
echo ipv4 forwarding enabled

###Route Iptables
echo iptables setup
iptables -F
read -p "What type of Virtualization are you using? [openvz,xen,kvm]?" VMVIRTTYPE
echo $VMVIRTTYPE

if [ "$VMVIRTTYPE" = "openvz" ]
then
      iptables -t nat -A POSTROUTING -o venet0 -j SNAT --to-source $IP
elif [ "$VMVIRTTYPE" = "xen" ]
then
      iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
elif [ "$VMVIRTTYPE" = "kvm" ]
then
      iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
fi
service iptables save
echo iptables configured and saved for openvpn

###Create Server.opvn
touch /etc/openvpn/server.ovpn
echo "client
dev tun
proto udp
remote 123.123.123.123 1194 # - Your server IP and OpenVPN Port
resolv-retry infinite
nobind
tun-mtu 1500
tun-mtu-extra 32
mssfix 1450
persist-key
persist-tun
ca ca.crt
auth-user-pass
comp-lzo
verb 3" > '/etc/openvpn/server.ovpn'
sed -i s/123.123.123.123/$IP/g /etc/openvpn/server.ovpn
echo server.opvn saved to /etc/openvpn/server.ovpn
exit 0
fi

###Output 
cd /etc/openvpn/easy-rsa/2.0/keys/
cp ca.crt /etc/openvpn/
cd /etc/openvpn/
tar -czvf config.tar.gz ca.crt server.ovpn
cp config.tar.gz /root/
cd

#Info
clear
echo "Sudah selesai pak, silahkan ambil config pada root"

