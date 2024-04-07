#!/bin/bash
dispacher_dir=/etc/archwrt/dispatcher
. "$dispacher_dir/dispatcher.conf"

if ! modinfo xt_FULLCONENAT &> /dev/null; then
  # fallback to MASQUERADE
  use_fullconenat = "false"
fi

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
    iptables -w -t mangle -A FORWARD -o $wan -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
  fi

  if [ -n "${lan}" ] && [ -n "${lan_net}" ] && [ "${iptables_no_masq}" != "true" ]; then
    if [ "${use_fullconenat}" = "true"  ]; then
	    iptables -w -t nat -A PREROUTING -i $wan -j FULLCONENAT
      iptables -w -t nat -A POSTROUTING -d $lan_net -o $lan -j FULLCONENAT
      iptables -w -t nat -A POSTROUTING -s $lan_net -o $wan -j FULLCONENAT
    else
      iptables -w -t nat -A POSTROUTING -d $lan_net -o $lan -j MASQUERADE
  	  iptables -w -t nat -A POSTROUTING -s $lan_net -o $wan -j MASQUERADE
    fi
  fi

	# Filter Rules
	# iptables
	sed "s/\$wan/$wan/g;s/\$lan/$lan/g;s/\$allowed_ports/$allowed_ports/g" "$dispacher_dir/filter.rules" \
		| iptables-restore -w || { echo Error: Loading filter.rules failed; down; exit 1; }
	#ip6tables
	sed "s/\$wan/$wan/g;s/\$lan/$lan/g;s/\$allowed_ports/$allowed_ports/g" "$dispacher_dir/filter6.rules" \
		| ip6tables-restore -w || { echo Error: Loading filter.rules failed; down; exit 1; }

	if [ -n "$cf_dest" ]; then
    cf_redir || { echo "Error: Cloudflare redirect failed" 1>&2; down; exit 1; }
	fi

	start_services

  if [ -n "$dns_hijack" ]; then
    iptables -w -t nat -I PREROUTING -s $lan_net -p udp -m udp --dport 53 -m comment --comment dns_redir -j DNAT --to-destination $dns_hijack
  fi
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
