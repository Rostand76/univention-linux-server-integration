#!/bin/bash

#
#   This script will allow your linux desktop to join a Univention Server domain
#   This will allow you connect to an LDAP,Kerberos,Samba server 
#   This was tested on Centos7.5 logging into Univention Server, but might work for other servers too
#
#   https://www.univention.com/
#

# this script was made following this website post
# https://help.univention.com/t/member-server-kerberos-user-authentication/4516/4

#
#   User Edit Section
#
# Set IP of Domain-Controller
MASTER_IP=192.168.100.85 # LDAP Server IP
ldap_master=third.ad # my DNS to the ldap 
ldap_base="dc=third,dc=ad"
hostname=$(hostname) # set the hostname you want to register with Univention

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# the rest of this script should just work by it self.
# for an explanation of what this script is doing, go to https://docs.software-univention.de/domain-4.1.html#ext-dom-ubuntu

# Step 0
# install all necessary packages
systemctl stop sssd
dnf install epel-release -y
dnf install -y sssd sssd-tools redhat-lsb-core sssd-ldap openldap-clients authconfig  oddjob-mkhomedir  samba4-common krb5-workstation

echo " Variables set: going to step 1"

# step 1
# integration into the LDAP directory and SSL certificate authority
echo " Attempting to connect to the LDAP server to obtain certificate"
echo " Please enter the password for the root user to the LDAP Server (for copying certs)"
echo "     ssh root@${ldap_master} [enter password]"

mkdir /etc/univention
mkdir -p /etc/univention/ssl/ucsCA/

ssh -n root@${MASTER_IP} 'ucr shell | grep -v ^hostname=' >/etc/univention/ucr_master
echo "master_ip=${MASTER_IP}" >>/etc/univention/ucr_master
chmod 660 /etc/univention/ucr_master
. /etc/univention/ucr_master

# add the ldap dns and ip into /etc/hosts
echo "${MASTER_IP} ${ldap_master}" >>/etc/hosts


echo " step1: complete"
echo ""
echo " step2: starting"

# step 2
# Create account on the server to Gain read access
wget -O /etc/openldap/cacerts/CAcert.pem \
    http://${ldap_master}/ucs-root-ca.crt

wget -O /etc/univention/ssl/ucsCA/CAcert.pem \
     http://${ldap_master}/ucs-root-ca.crt

# Create an account and save the password
yum install -y sssd redhat-lsb-core authconfig-gtk
password="$(tr -dc A-Za-z0-9_ </dev/urandom | head -c20)"
echo "     ssh root@${ldap_master} [enterdevlab.asrc password]"
ssh -n root@${ldap_master} udm linux-servers/linux create \
    --position "cn=computers,${ldap_base}" \
    --set name=$(hostname) --set password="${password}" \
    --set operatingSystem="$(lsb_release -is)" \
    --set operatingSystemVersion="$(lsb_release -rs)"
printf '%s' "$password" >/etc/ldap.secret
chmod 0400 /etc/ldap.secret

echo "step2: complete"
echo ""
echo "step3: starting"

# Step 3
# Create ldap.conf locally
cat >/etc/openldap/ldap.conf <<__EOF__
TLS_CACERT /etc/openldap/cacerts/CAcert.pem
URI ldap://$ldap_master:7389
BASE $ldap_base
__EOF__
echo "step3:complete"
echo ""
echo "step4: starting"

# sssd
cat >/etc/sssd/sssd.conf <<___EOF___
[sssd]
config_file_version = 2
reconnection_retries = 3
sbus_timeout = 30
services = nss, pam, sudo
domains = $kerberos_realm
[nss]
reconnection_retries = 3
[pam]
reconnection_retries = 3
[domain/$kerberos_realm]
auth_provider = krb5
krb5_kdcip = 192.168.100.85
krb5_realm = $kerberos_realm
krb5_server = ${ldap_master}
krb5_kpasswd = ${ldap_master}
id_provider = ldap
ldap_uri = ldap://${ldap_master}:7389
ldap_search_base = ${ldap_base}
ldap_tls_reqcert = never
ldap_tls_cacert = /etc/univention/ssl/ucsCA/CAcert.pem
cache_credentials = true
enumerate = true
ldap_default_bind_dn = cn=$(hostname),cn=computers,${ldap_base}
ldap_default_authtok_type = password
ldap_default_authtok = $(cat /etc/ldap.secret)
___EOF___

#kerbores configuration
cat >/etc/krb5.conf <<___EOF___
includedir /var/lib/sss/pubconf/krb5.include.d/
[libdefaults]
 default_realm = THIRD.AD
    kdc_timesync = 1
    ccache_type = 4
    forwardable = true
    proxiable = true
    default_tkt_enctypes = arcfour-hmac-md5 des-cbc-md5 des3-hmac-sha1 des-cbc-crc des-cbc-md4 des3-cbc-sha1 aes128-cts-hmac-sha1-96 aes256-cts-hmac-sha1-96
    permitted_enctypes = des3-hmac-sha1 des-cbc-crc des-cbc-md4 des-cbc-md5 des3-cbc-sha1 arcfour-hmac-md5 aes128-cts-hmac-sha1-96 aes256-cts-hmac-sha1-96
    allow_weak_crypto=true

[realms]
THIRD.AD = {
  kdc = 192.168.100.85
  kdc = ucs.third.ad
  admin_server = 192.168.100.85
  admin_server = ucs.third.ad
   kpasswd_server = 192.168.100.23 ucs.third.cm
}
[domain_realm]
 third.cm = THIRD.AD
 .third.cm = THIRD.AD
___EOF___

chmod 600 /etc/sssd/sssd.conf
echo "session optional pam_oddjob_mkhomedir.so skel=/etc/skel/ umask=0022" >> /etc/pam.d/system-auth
systemctl enable --now oddjobd
authconfig --updateall --enableldap --enableldapauth

echo "step4: complete"

#systemctl start sssd


#  LAST STEP !!
# this will launch the authconfig gui with stuff filled in already. Please verify the settings and click apply to actually join 
#     the workstation to the Univention server

# launch authconfig gui
#authconfig-gtk

# once the gui loads, click apply
