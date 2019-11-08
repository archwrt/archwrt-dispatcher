# archwrt-dispatcher
Dispatcher for handling iptables nat forwarding and others by systemd service.

### This is a quick and dirty solution

Since `netctl` is a dirty and quick solution, this is quick and dirty.

### Tips for netctl.profile

Just add the following to your netctl.profile: (assuming the WAN interface is `net0`)

```
ExecUpPost="systemctl start archwrt-dispatcher@net0;"
ExecDownPre="systemctl stop archwrt-dispatcher@net0;"
```
__For PPPoE profiles, change `net0` to `pppX`(at most of time `ppp0` should work)__

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
