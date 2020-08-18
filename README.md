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

# Access point mode - needs to be first!
network={
    priority=0
    mode=2
    frequency=2462
    key_mgmt=WPA-PSK
    ssid=RaspberryPi
    psk="raspberry"
}

# Wireless Client
network={
    priority=10
    ssid="HomeNetwork"
    psk="SomePassword"
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

## Notes

Some confusion around the **CONNECTED** and **DISCONNECTED** events reported to the actions script.

From the `wpa_cli` manual page:

> Additionally, three environmental variables are available to
> the file: WPA_CTRL_DIR, WPA_ID, and WPA_ID_STR. WPA_CTRL_DIR
> contains the absolute path to the ctrl_interface socket. WPA_ID
> contains the unique network_id identifier assigned to the active
> network, and WPA_ID_STR contains the content of the id_str option.

From `wpa_supplicant/wpa_cli.c`:

```
    if (str_starts(pos, WPA_EVENT_CONNECTED)) {
        int new_id = -1;
        os_unsetenv("WPA_ID");
        os_unsetenv("WPA_ID_STR");
        os_unsetenv("WPA_CTRL_DIR");

        pos = os_strstr(pos, "[id=");
        if (pos)
            copy = os_strdup(pos + 4);

        if (copy) {
            pos2 = id = copy;
            while (*pos2 && *pos2 != ' ')
                pos2++;
            *pos2++ = '\0';
            new_id = atoi(id);
            os_setenv("WPA_ID", id, 1);
            while (*pos2 && *pos2 != '=')
                pos2++;
            if (*pos2 == '=')
                pos2++;
            id = pos2;
            while (*pos2 && *pos2 != ']')
                pos2++;
            *pos2 = '\0';
            os_setenv("WPA_ID_STR", id, 1);
            os_free(copy);
        }

        os_setenv("WPA_CTRL_DIR", ctrl_iface_dir, 1);

        if (wpa_cli_connected <= 0 || new_id != wpa_cli_last_id) {
            wpa_cli_connected = 1;
            wpa_cli_last_id = new_id;
            wpa_cli_exec(action_file, ifname, "CONNECTED");
        }
    } else if (str_starts(pos, WPA_EVENT_DISCONNECTED)) {
        if (wpa_cli_connected) {
            wpa_cli_connected = 0;
            wpa_cli_exec(action_file, ifname, "DISCONNECTED");
        }
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

