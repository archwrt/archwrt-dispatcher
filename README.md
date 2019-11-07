# archwrt-dispatcher
Dispatcher for handling iptables and others by systemd service.

### This is a quick and dirty solution

Dirty solution for setting iptables and managing annoying `After=network.target` services
with `wait-for-oneline.service` and `netctl`'s `ExecUpPost`.

### Tips for netctl.profile

Just add the following to your netctl.profile: (assuming the WAN interface is `net0`)

```
ExecUpPost="systemctl start archwrt-dispatcher@net0;"
ExecDownPre="systemctl stop archwrt-dispatcher@net0;"
```

__For PPPoE profiles, change `net0` to `pppX`(at most of time `ppp0` should work)__


If we just call `systemctl start` in the `nectl`, Some services will wait until `network.target` reached, but `network.target` will never reach until `netctl` finishes. 

Then, it get stucked.

The `archwrt-dispatcher@.service` is created to solve the problem by creating a daemon which helps you to start services soon or later.

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
