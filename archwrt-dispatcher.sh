#!/bin/bash
dispacher_dir=/etc/archwrt/dispatcher
. "$dispacher_dir/dispatcher.conf"

guess_interface() {
#   return $(ip -d route | grep default | head -n 1 | tr ' ' '\n' | grep -A1 dev | tail -n)
    return $(ip route | grep default | grep -o 'dev.*' | awk '{print $2}')
}

start_services() {
    for s in "${services[@]}"; do
        systemctl start "$s" || { echo Error: Starting service $s failed; down; return 1 }
    done
}

stop_services() {
    for s in "${services[@]}"; do
        systemctl stop "$s"
    done
}

# Cloudflare redir
cf_redir() {
    ipset -! flush cloudflare &>/dev/null   || return 1
    ipset -! create cloudflare nethash      || return 1

    for net in "${cf_range[@]}"; do
        ipset -! add cloudflare "${net}"    || return 1
    done

    for net in "${cf_whitelist[@]}"; do
        ipset -! add cloudflare "${net}" nomatch    || return 1
    done

    iptables -t nat -N CLOUDFLARE               || return 1
    iptables -t nat -I PREROUTING -j CLOUDFLARE || return 1
    iptables -t nat -I OUTPUT -j CLOUDFLARE     || return 1
    iptables -t nat -A CLOUDFLARE -p tcp -m set --match-set cloudflare dst -m comment --comment "Cloudflare IP" -j DNAT --to-destination "${cf_dest}" || return 1
}

up() {
    [ -z $wan ] && wan=$1
    if [ -z $wan ]; then
        wan=guess_interface()
        echo Info: WAN interface was set to $interface
    fi
    # nat
    if [ "${use_fullconenat}" = "true" ]; then
        iptables-restore -w <<-EOF || { echo Error: Setting up NAT failed; down; exit 1 }
            *nat
            :PREROUTING ACCEPT [0:0]
            :INPUT ACCEPT [0:0]
            :OUTPUT ACCEPT [0:0]
            :POSTROUTING ACCEPT [0:0]
            -A POSTROUTING -o $wan -j MASQUERADE
            COMMIT
        EOF
    else
        iptables-restore -w <<-EOF || { echo Error: Setting up NAT failed; down; exit 1 }
             *nat
            :PREROUTING ACCEPT [0:0]
            :INPUT ACCEPT [0:0]
            :OUTPUT ACCEPT [0:0]
            :POSTROUTING ACCEPT [0:0]
            -A PREROUTING -i $wan -j FULLCONENAT
            -A POSTROUTING -o $wan -j FULLCONENAT
            COMMIT
        EOF
    fi

    # PPPoE uses extra bytes, reconfigure
    if [[ "$wan" =~ "ppp" ]]; then
        iptables-restore -w <<-EOF || { echo Error: Reconfigure PPP mtu failed; down; exit 1 }
            *mangle
            :PREROUTING ACCEPT [0:0]
            :INPUT ACCEPT [0:0]
            :FORWARD ACCEPT [0:0]
            :OUTPUT ACCEPT [0:0]
            :POSTROUTING ACCEPT [0:0]
            -A FORWARD -o $wan -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
            COMMIT
        EOF
    fi

    # Filter Rules
    sed "s,\$wan,$wan,g;s,\$lan,$lan,g" "$dispacher_dir/filter.rules" | iptables-restore -w || { echo Error: Loading filter.rules failed; down; exit 1 }

    [ -n "$cf_dest" ] && cf_redir || { echo Error: Cloudflare redirect failed; down; exit 1 }
    start_services || { down; exit 1 }
}

down() {
    cat /usr/share/iptables/empty-{filter,nat,mangle}.rules | iptables-restore -w
    stop_services
}

while [ $# -gt 0 ]; do
    case $1 in
    up)
        up "$2"
        shift 2
        ;;
    down)
        down
        shift
        ;;
    restart)
        down
        sleep .5
        up "$2"
        shift 2
        ;;
    *)
        echo <<-EOF
archwrt-dispatcher, a dispatcher for handling iptables nat forwarding and others by systemd service.
Usage:
    $0 up [INTERFACE]
    $0 down
    $0 restart [INTERFACE]
EOF
        shift
        ;;
    esac
done
