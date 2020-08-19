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

## Theory of Operation

### Wireless

The `wpa_cli` man page perhaps describes it best:

> **-a file**
>
> Run in daemon mode executing the action file based on events from wpa_supplicant. The specified file will be executed with the first argument set to interface name and second to "CONNECTED" or "DISCONNECTED" depending on the event. This can be used to execute networking tools required to configure the interface.
> Additionally, three environmental variables are available to the file: WPA_CTRL_DIR, WPA_ID, and WPA_ID_STR. WPA_CTRL_DIR contains the absolute path to the ctrl_interface socket. WPA_ID contains the unique network_id identifier assigned to the active network, and WPA_ID_STR contains the content of the id_str option.

There are 6 events of interest:

| `wpa_cli` Event     |     |
| ------------------- | --- |
| CONNECTED           |  Connected |
| DISCONNECTED        |  Disconnected |
| AP-STA-CONNECTED    |  Station connected to AP |
| AP-STA-DISCONNECTED |  Station disconnected from AP |
| AP-ENABLED          |  AP mode entered |
| AP-DISABLED         |  AP mode exited |

The `wpa_supplicant` configuration contains an accesspoint mode network statement and a client (station) mode network statement. When the client is able to connect to the network, it is the preferred network due to its `priority=` value. When the client is unable to connect, the wireless enters access point mode.

The **AP-ENABLED** event triggers the reconfiguration of `systemd-networkd` for access point mode by applying a static IP address to the `wlan0` interface and providing a DHCP server. The `rpi-auto-ap` script also starts a timer (2 minute default) which will revert back to client mode to scan for any available networks. 

The **AP-STA-DISCONNECTED** event causes a check for connected clients, if no clients are present a timer (30 seconds default) is started. Upon timer expiry wireless will be reconfigured for client mode to scan for available networks.

The **CONNECTED** event is used to detect whether wireless has connected to a network. Because **CONNECTED** also occurs for events in other modes, a secondary check to ensure wireless is in client (station) mode is required. If all checks pass, the reconfiguration of `systemd-networkd` for client mode occurs by enabling the DHCP client to obtain an IP address.

A status file is used to manage overlapping wait routines.

### Networking

`systemd-networkd` is used to handle networking changes. Changing between appropriate settings for each mode is accomplished by installing an appropriate configuration file and restarting the `systemd-networkd` service.

## Notes

The **CONNECTED** and **DISCONNECTED** events are reported in various wireless modes, not strictly in client mode. 

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

