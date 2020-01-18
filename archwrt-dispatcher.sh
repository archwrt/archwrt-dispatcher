#!/bin/bash
dispacher_dir=/etc/archwrt/dispatcher
. "$dispacher_dir/dispatcher.conf"

start_services() {
	for s in "${services[@]}"; do
		(systemctl start "$s" &) || true
		#If this failed, it could be the problem of the service itself. We keep starting other sercives.
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

down() {
    stop_services
	cat /usr/share/iptables/empty-{filter,nat,mangle}.rules | iptables-restore -w
}

up() {
	case $1 in
		default)
			wan=$(ip route | \
				grep default | \
				grep -o 'dev.*' | \
				awk '{print $2}')
			[ -z "$wan" ] && { echo 'Read default interface from route failed!' 1>&2;  exit 1; }
			;;
		*)
			wan=$1
			;;
	esac
	#NAT
	if [[ "$wan" =~ "ppp" ]]; then
		if [ "${use_fullconenat}" = "true"  ]; then
			iptables-restore -w <<-EOF || { echo 'Setting up NAT for $wan failed'; down; exit 1; }
				*nat
				:PREROUTING ACCEPT [0:0]
				:INPUT ACCEPT [0:0]
				:OUTPUT ACCEPT [0:0]
				:POSTROUTING ACCEPT [0:0]
				-A PREROUTING -i $wan -j FULLCONENAT
				-A POSTROUTING -o $wan -j FULLCONENAT
				COMMIT

				*mangle
				:PREROUTING ACCEPT [0:0]
				:INPUT ACCEPT [0:0]
				:FORWARD ACCEPT [0:0]
				:OUTPUT ACCEPT [0:0]
				:POSTROUTING ACCEPT [0:0]
				-A FORWARD -o $wan -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
				COMMIT
			EOF
		else
			iptables-restore -w <<-EOF || { echo 'Setting up NAT for $wan failed'; down; exit 1; }
				*nat
				:PREROUTING ACCEPT [0:0]
				:INPUT ACCEPT [0:0]
				:OUTPUT ACCEPT [0:0]
				:POSTROUTING ACCEPT [0:0]
				-A POSTROUTING -o $wan -j MASQUERADE
				COMMIT

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
	else
		if [ "${use_fullconenat}" = "true"  ]; then
			iptables-restore -w <<-EOF || { echo 'Setting up NAT for $wan failed'; down; exit 1; }
				*nat
				:PREROUTING ACCEPT [0:0]
				:INPUT ACCEPT [0:0]
				:OUTPUT ACCEPT [0:0]
				:POSTROUTING ACCEPT [0:0]
				-A POSTROUTING -o $wan -j FULLCONENAT
				-A PREROUTING -i $wan -j FULLCONENAT
				COMMIT
			EOF
		else
			iptables-restore -w <<-EOF || { echo 'Setting up NAT for $wan failed'; down; exit 1; }
				*nat
				:PREROUTING ACCEPT [0:0]
				:INPUT ACCEPT [0:0]
				:OUTPUT ACCEPT [0:0]
				:POSTROUTING ACCEPT [0:0]
				-A POSTROUTING -o $wan -j MASQUERADE
				COMMIT
			EOF
		fi
	fi

	# Filter Rules
	sed "s,\$wan,$wan,g;s,\$lan,$lan,g" "$dispacher_dir/filter.rules" \
		| iptables-restore -w || { echo Error: Loading filter.rules failed; down; exit 1; }

	if [ -n "$cf_dest" ]; then
		cf_redir || { echo "Error: Cloudflare redirect failed" 1>&2; down; exit 1; }
	fi

	start_services
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
		cat <<-EOF
			Usage:
			    $0 up [wan]
				$0 down
				$0 restart [wan]
			wan:
				default - use default wan from route table as wan interface
				foo - use foo as wan interface
				bar - use bar as wan interface
		EOF
        exit 0
		;;
	esac
done
