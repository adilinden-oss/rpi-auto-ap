#!/bin/bash

# MIT License
# 
# Copyright (c) 2020 Adi Linden
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# This script heavily leans on the work done by others, namely:
#
#   - StackExchange "Automatically Create Hotspot if no Network is Available"
#       https://raspberrypi.stackexchange.com/a/100196
#   - StackExchange "Use systemd-networkd for general networking"
#       https://raspberrypi.stackexchange.com/a/108593
#   - GitHub 0unknwn/auto-hotspot
#       https://github.com/0unknwn/auto-hotspot
#   - GitHub gitbls/autoAP
#       https://github.com/gitbls/autoAP
#

# Default interfaces
if_lan="eth0"
if_wlan="wlan0"

# Default AP settings
#
# IEEE 802.11b/g Channel Assignments
# ----------------------------------
#   1   2412
#   2   2417
#   3   2422
#   4   2427
#   5   2432
#   6   2437
#   7   2442
#   8   2447
#   9   2452
#  10   2457
#  11   2462
ap_ip="192.168.252.1/28"
ap_ssid="RaspberryPi"
ap_psk="raspberry"
ap_freq="2412"
ap_country="CA"

# Must be root!
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    echo
    echo "    sudo $0"
    echo
    exit 1
fi

# deinstall classic networking
echo "Deinstalling classic networking"
# Note: Keeping rsyslog
#apt --autoremove purge ifupdown dhcpcd5 isc-dhcp-client isc-dhcp-common rsyslog
#apt-mark hold ifupdown dhcpcd5 isc-dhcp-client isc-dhcp-common rsyslog raspberrypi-net-mods openresolv
apt --autoremove purge -y ifupdown dhcpcd5 isc-dhcp-client isc-dhcp-common
apt-mark hold ifupdown dhcpcd5 isc-dhcp-client isc-dhcp-common raspberrypi-net-mods openresolv
rm -r /etc/network /etc/dhcp

# setup/enable systemd-resolved and systemd-networkd
echo "Setting up \"systemd-resolved\" and \"systemd-networkd\""
apt-mark hold avahi-daemon libnss-mdns
apt install -y libnss-resolve
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemctl enable systemd-networkd.service systemd-resolved.service

###                ###
### systemd BUGFIX ###
###                ###
# 
# See https://raspberrypi.stackexchange.com/questions/108592/ and 
# https://github.com/systemd/systemd/issues/12388. I quote:
#
# > It should be said that there is a known bug. If you get error messages like:
# > 
# >     DNSSEC validation failed for question google.com IN A: no-signature
# > 
# > then you hit Sporadic "DNSSEC validation failed" — "no-signature" #12388.
# > You can workaround this with adding option DNSSEC=no to 
# > /etc/systemd/resolved.conf and reboot to disable DNS record signing.
if ! grep -q "^DNSSEC=no" /etc/systemd/resolved.conf; then
    cat >> /etc/systemd/resolved.conf <<END

# Added by rpi-auto-ap installation to workaround systemd bug
# Sporadic "DNSSEC validation failed" — "no-signature" #12388
# https://github.com/systemd/systemd/issues/12388
DNSSEC=no

END
fi

# Install configuration files for `systemd-networkd`
echo "Installing \"systemd-networkd\" configurations"
cat > /etc/systemd/network/11-${if_lan}.network <<END
[Match]
Name=$if_lan

[Network]
DHCP=Yes
MulticastDNS=yes

[DHCP]
RouteMetric=10
UseDomains=yes
END

cat > /etc/systemd/network/21-${if_wlan}-client.network <<END
[Match]
Name=$if_wlan

[Network]
DHCP=yes
MulticastDNS=yes

[DHCP]
RouteMetric=20
UseDomains=yes
END
        
cat > /etc/systemd/network/25-${if_wlan}-accesspoint.network <<END
[Match]
Name=$if_wlan

[Network]
Address=$ap_ip
DHCPServer=yes
MulticastDNS=yes
END

# Install systemd-service to have networking follow wireless status
echo "Installing \"wpa_cli@${if_wlan}.service\""
cat > /etc/systemd/system/wpa_cli@${if_wlan}.service <<END
[Unit]
Description=wpa_cli to trigger setup and teardown of access point mode
After=wpa_supplicant@%i.service
BindsTo=wpa_supplicant@%i.service

[Service]
Type=simple
ExecStartPre=/usr/local/sbin/rpi-auto-ap --reset
ExecStart=/sbin/wpa_cli -i %I -a /usr/local/sbin/rpi-auto-ap
Restart=on-failure
TimeoutSec=1

[Install]
WantedBy=multi-user.target
END

systemctl daemon-reload
systemctl enable --now wpa_cli@${if_wlan}.service

# Move existing `/etc/wpa_supplicant/wpa_supplicantconf` out of the way
if [ -f "/etc/wpa_supplicant/wpa_supplicant.conf" ]; then
    echo "\"Moving wpa_supplicant.conf\" to \"wpa_supplicant.conf-orig\""
    mv "/etc/wpa_supplicant/wpa_supplicant.conf" "/etc/wpa_supplicant/wpa_supplicant.conf-orig"
fi

# Create `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf`
if [ -f "/etc/wpa_supplicant/wpa_supplicant-${if_wlan}.conf" ]; then
	echo "Found \"wpa_supplicant-${if_wlan}.conf\" please review its settings! Run:"
	echo
	echo "    cat /etc/wpa_supplicant/wpa_supplicant-${if_wlan}.conf"
	echo
else
	echo "Creating \"wpa_supplicant-${if_wlan}.conf\" please review its settings! Run:"
	echo
	echo "    cat /etc/wpa_supplicant/wpa_supplicant-${if_wlan}.conf"
	echo
	cat > /etc/wpa_supplicant/wpa_supplicant-${if_wlan}.conf <<END
country=$ap_country
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
ap_scan=1

# Access point mode - needs to be first!
network={
    priority=0
    mode=2
    frequency=$ap_freq
    key_mgmt=WPA-PSK
    ssid="$ap_ssid"
    psk="$ap_psk"
}

# Wireless Client
network={
    priority=10
    ssid="HomeNetwork"
    psk="SomePassword"
}
END
fi

# Install `rpi-auto-ap`
echo "Installing \"rpi-auto-ap\""
install -m 755 rpi-auto-ap /usr/local/sbin/

# Finished!
echo "Installation completed, please reboot."
echo
echo "    sudo shutdown -r now"
echo

# End
