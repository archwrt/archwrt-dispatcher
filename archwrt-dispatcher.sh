#!/bin/bash
dispacher_dir=/etc/archwrt/dispatcher
. "$dispacher_dir/dispatcher.conf"

start_services() {
	for s in "${services[@]}"; do
        (systemctl start "$s" &) || true
	done
}

stop_services() {
	for s in "${services[@]}"; do
        systemctl stop "$s"
	done
}

# Cloudflare redir
cf_redir() {
	ipset -! flush cloudflare &>/dev/null
	ipset -! create cloudflare nethash

	for net in "${cf_range[@]}"; do
		ipset -! add cloudflare "${net}"
	done

	for net in "${cf_whitelist[@]}"; do
		ipset -! add cloudflare "${net}" nomatch
	done

    iptables -t nat -N CLOUDFLARE
    iptables -t nat -I PREROUTING -j CLOUDFLARE
    iptables -t nat -I OUTPUT -j CLOUDFLARE

	iptables -t nat -A CLOUDFLARE -p tcp -m set --match-set cloudflare dst -m comment --comment "Cloudflare IP" -j DNAT --to-destination "${cf_dest}"
}

up() {
	case $1 in
		default)
			interface=$(ip route | \
				grep default | \
				grep -o 'dev.*' | \
				awk '{print $2}')
            [ -z "$interface" ] && echo 'Read default interface from route failed!' 1>&2 && exit 1
			;;
		*)
			interface=$1
			;;
	esac
	#NAT
	if [[ "$interface" =~ "ppp" ]]; then
		if [ "${use_fullconenat}" = "true"  ]; then
			iptables-restore -w <<-EOF
				*nat
				:PREROUTING ACCEPT [0:0]
				:INPUT ACCEPT [0:0]
				:OUTPUT ACCEPT [0:0]
				:POSTROUTING ACCEPT [0:0]
				-A PREROUTING -i $interface -j FULLCONENAT
				-A POSTROUTING -o $interface -j FULLCONENAT
				COMMIT

				*mangle
				:PREROUTING ACCEPT [0:0]
				:INPUT ACCEPT [0:0]
				:FORWARD ACCEPT [0:0]
				:OUTPUT ACCEPT [0:0]
				:POSTROUTING ACCEPT [0:0]
				-A FORWARD -o $interface -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
				COMMIT
			EOF
		else
			iptables-restore -w <<-EOF
				*nat
				:PREROUTING ACCEPT [0:0]
				:INPUT ACCEPT [0:0]
				:OUTPUT ACCEPT [0:0]
				:POSTROUTING ACCEPT [0:0]
				-A POSTROUTING -o $interface -j MASQUERADE
				COMMIT

				*mangle
				:PREROUTING ACCEPT [0:0]
				:INPUT ACCEPT [0:0]
				:FORWARD ACCEPT [0:0]
				:OUTPUT ACCEPT [0:0]
				:POSTROUTING ACCEPT [0:0]
				-A FORWARD -o $interface -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
				COMMIT
			EOF
		fi
	else
		if [ "${use_fullconenat}" = "true"  ]; then
			iptables-restore -w <<-EOF
				*nat
				:PREROUTING ACCEPT [0:0]
				:INPUT ACCEPT [0:0]
				:OUTPUT ACCEPT [0:0]
				:POSTROUTING ACCEPT [0:0]
				-A POSTROUTING -o $interface -j FULLCONENAT
				-A PREROUTING -i $interface -j FULLCONENAT
				COMMIT
			EOF
		else
			iptables-restore -w <<-EOF
				*nat
				:PREROUTING ACCEPT [0:0]
				:INPUT ACCEPT [0:0]
				:OUTPUT ACCEPT [0:0]
				:POSTROUTING ACCEPT [0:0]
				-A POSTROUTING -o $interface -j MASQUERADE
				COMMIT
			EOF
		fi
	fi

	# Filter Rules
	sed "s,\$interface,$interface,g" "$dispacher_dir/filter.rules" | iptables-restore -w
	sed "s,\$interface,$interface,g" "$dispacher_dir/filter.rules" | ip6tables-restore -w

	[ -n "$cf_dest" ] && cf_redir
	start_services
}

down() {
	cat /usr/share/iptables/empty-{filter,nat,mangle}.rules | iptables-restore -w
	cat /usr/share/iptables/empty-{filter,nat,mangle}.rules | ip6tables-restore -w
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
		shift
		;;
	esac
done
