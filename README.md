# archwrt-dispatcher
Dispatcher for handling iptables nat forwarding and others by systemd service.

### This is a quick and dirty solution

Since `netctl` is a dirty and quick solution, this is quick and dirty.

### Tips for netctl.profile

Just add the following to your netctl.profile: (assuming the WAN interface is `net0`)

```
ExecUpPost="systemctl start archwrt-dispatcher.service;"
ExecDownPre="systemctl stop archwrt-dispatcher.service;"
```

***

__Tipically, the above use the default interface from `ip route`. If you want to assign an interface manually, use the following instead: (assuming the WAN interface is `net0`)__

```
ExecUpPost="systemctl start archwrt-dispatcher@net0.service;"
ExecDownPre="systemctl stop archwrt-dispatcher@net0.service;"
```

### For PPPoE profiles, create the following scripts: (Don't forget the execute permission)__

`/etc/ppp/ip-up.d/10-archwrt-dispatcher.sh`

``` bash
#!/bin/bash
systemctl start "archwrt-dispatcher.service"
```

`/etc/ppp/ip-down.d/10-archwrt-dispatcher.sh`

``` bash
#!/bin/bash
systemctl stop "archwrt-dispatcher.service"
```

***

__Tipically, the above use the default interface from `ip route`. If you want to assign the interface manually, use the following instead:__

`/etc/ppp/ip-up.d/10-archwrt-dispatcher.sh`

``` bash
#!/bin/bash
systemctl start "archwrt-dispatcher@${IFNAME}.service"
```

`/etc/ppp/ip-down.d/10-archwrt-dispatcher.sh`

``` bash
#!/bin/bash
systemctl stop "archwrt-dispatcher@${IFNAME}.service"
```

### Use Full Cone Nat
Default is `true` (need iptables-fullconenat). If you want use `MASQUERADE` instead, set use_fullconenat `false` in `dispatcher.conf`

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
