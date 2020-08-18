# rpi-auto-ap

## Credits

- Scripts discussed at StackExchange [Automatically Create Hotspot if no Network is Available][1]
- Using systemd for rPi discussed at StackExchange [Use systemd-networkd for general networking][2]
- Inspiration taken from [0unknwn/auto-hotspot][3] and [gitbls/autoAP][4]

## Description

This script is to be used on a Raspberry Pi. It has been tested on Raspbian Buster 2020-05-27 running on Raspberry Pi 2 Model B and Raspberry Pi 4 Model B/2GB.

It will manage the wireless connection of the Raspberry Pi to create a local wireless access point when no wireless client connection can be established. It will maintain access point mode as long as a client is connected. When the last client disconnects it will scan for access points and connect as a client if it can, otherwise it will revert to access point again. The timeout is configurable.

I strongly recommend reading the referenced discussions and suggest checking out the other works this is based on.

## Installation

**Warning:** the installation script will change the Raspberry Pi netwoking to `systemd-networkd`. Make sure you have a **backup** of your files in case the system becomes unstable/unuseable/unreachable. In the best case recover using KVM, in the worst case start with freshly imaged SD card. You have been warned, this script comes without any warranties!

### 1. Step

Manually create `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf` and enter the desired SSID and passwords for AP mode and client mode. If you already have wireless configured, lookup the appropriate values in `/etc/wpa_supplicant/wpa_supplicant.conf`. If you skip this step, `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf` will be created with the values below during the next step.

```
country=CA
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
ap_scan=1

# Wireless Client
network={
    priority=10
    ssid="HomeNetwork"
    psk="SomePassword"
}

# Access point mode
network={
    priority=0
    mode=2
    frequency=2462
    key_mgmt=WPA-PSK
    ssid=RaspberryPi
    psk="raspberry"
}
```

### 2. Step

Run the installation script.

```
sudo ./install.sh
```

In brief, the installation script will perform the following:

- Change the system to `systemd-networkd` by uninstalling several packages
- Install configuration files for `systemd-networkd`
    * `/etc/systemd/network/11-${if_lan}.network`
    * `/etc/systemd/network/21-${if_wlan}-client.network`
    * `/etc/systemd/network/25-${if_wlan}-accesspoint.network`
- Install `systemd-service` to have networking follow wireless status
    * `/etc/systemd/system/wpa_cli@${if_wlan}.service`
- Rename existing `/etc/wpa_supplicant/wpa_supplicant.conf`
- Create `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf` unless it exists
- Install `/usr/local/sbin/rpi-auto-ap`

### 3. Step

Reboot the Raspberry Pi

```
shutdown -r now
```

## References

- StackExchange [Automatically Create Hotspot if no Network is Available][1]
- StackExchange [Use systemd-networkd for general networking][2]
- GitHub [0unknwn/auto-hotspot][3]
- GitHub [gitbls/autoAP][4]

[1]:https://raspberrypi.stackexchange.com/a/100196
[2]:https://raspberrypi.stackexchange.com/a/108593
[3]:https://github.com/0unknwn/auto-hotspot
[4]:https://github.com/gitbls/autoAP

