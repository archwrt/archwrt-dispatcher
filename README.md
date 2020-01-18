# archwrt-dispatcher
Dispatcher for handling iptables nat forwarding and others by systemd service.

## Description
This is a quick and dirty solution. Since `netctl` is a dirty and quick solution, this is quick and dirty.

## Installation

### Arch Linux

Package is available on [edward-p/archwrt-dispatcher](https://repo.edward-p.xyz/).
You can also get iptables-fullconenat from this repo.

## Configuration

### Enable

1. netctl.profile

Just add the following to your netctl.profile: (assuming the WAN interface is `net0`)

```
ExecUpPost="systemctl start archwrt-dispatcher@net0;"
ExecDownPre="systemctl stop archwrt-dispatcher@net0;"
```

2. pppd

```
ln -sf /usr/share/archwrt/ppp.up-10-archwrt.sh /etc/ppp/ip-up.d/10-archwrt.sh
ln -sf /usr/share/archwrt/ppp.down-10-archwrt.sh /etc/ppp/ip-down.d/10-archwrt.sh
```

3. read from route table

You can also use `archwrt-dispatcher.service` and we can get WAN interface from the route table.

### Interfaces

You can set WAN interface in following methods:

1. WAN interface
- systemd @.service unit
- systemd .service unit (get from route table)
- pppd environment 

2. LAN interface (bridge)

Set `lan` variable in the `/etc/archwrt/dispatcher/dispatcher.conf`, default is `br0`

### `use_fullconenat`
Default is `true` (need iptables-fullconenat). If you want use `MASQUERADE` instead, set it `false` in `dispatcher.conf`

### Managing Services

Set `services` array in the `/etc/archwrt/dispatcher/dispatcher.conf`

### iptables Filter table

The default policy for INPUT is DROP
If you need unblock a port, edit the `/etc/archwrt/dispatcher/filter.rules`
e.g. To open tcp port 80, add this line to the end of the INPUT Chain:

```
-A INPUT -p tcp --dport 80 -j ACCEPT
```

### Cloudflare Redirection

Just read the script and `/etc/archwrt/dispatcher/dispatcher.conf`
If you don't want this, just set `cf_dest` to empty string or comment it.

## TODO

- IPv6 support
