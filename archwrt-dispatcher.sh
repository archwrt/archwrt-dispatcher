#!/bin/bash
dispacher_dir=/etc/archwrt/dispatcher
. "$dispacher_dir/dispatcher.conf"

if [ "$nat_type" = "fullcone" ]; then
	if ! modinfo xt_FULLCONENAT &>/dev/null && ! modinfo nft_fullcone &>/dev/null; then
		# fallback to MASQUERADE
		nat_type="masquerade"
	fi
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

down() {
	stop_services
	case $nat_type in
	einat) clear_einat ;;
	fullcone | masquerade)
		if [ "$use_nftables" = "true" ]; then
			clear_nft
		else
			clear_legacy
		fi
		;;
	*) ;;
	esac

}

clear_legacy() {
	cat /usr/share/iptables/empty-{filter,nat,mangle}.rules | iptables-restore -w
}

clear_nft() {
	nft flush ruleset
}

clear_einat() {
	systemctl stop _archwrt-dispatcher-einat.service
	systemctl reset-failed _archwrt-dispatcher-einat.service
	if [ "$use_nftables" = "true" ]; then
		clear_nft
	else
		clear_legacy
	fi
}

add_rules_legacy() {

	if [ -n "$dns_hijack" ]; then
		iptables -w -t nat -I PREROUTING -s $lan_net -p udp -m udp --dport 53 -m comment --comment dns_redir -j DNAT --to-destination $dns_hijack
	fi

	if [[ "$wan" =~ "ppp" ]]; then
		iptables -w -t mangle -A FORWARD -o $wan -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
		ip6tables -w -t mangle -A FORWARD -o $wan -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
	fi

	if [ "${nat_type}" != "einat" ]; then
		#NAT
		if [ -n "${lan}" ] && [ -n "${lan_net}" ] && [ "${iptables_no_masq}" != "true" ]; then
			if [ "${nat_type}" = "fullcone" ]; then
				iptables -w -t nat -A PREROUTING -i $wan -j FULLCONENAT
				iptables -w -t nat -A POSTROUTING -d $lan_net -o $lan -j FULLCONENAT
				iptables -w -t nat -A POSTROUTING -s $lan_net -o $wan -j FULLCONENAT
			else
				iptables -w -t nat -A POSTROUTING -d $lan_net -o $lan -j MASQUERADE
				iptables -w -t nat -A POSTROUTING -s $lan_net -o $wan -j MASQUERADE
			fi
		fi
	fi

	# Filter Rules
	# iptables
	sed "s/\$wan/$wan/g;s/\$lan/$lan/g;s/\$allowed_ports/$allowed_ports/g" "$dispacher_dir/filter.rules" |
		iptables-restore -w || {
		echo Error: Loading filter.rules failed
		down
		exit 1
	}
	#ip6tables
	sed "s/\$wan/$wan/g;s/\$lan/$lan/g;s/\$allowed_ports/$allowed_ports/g" "$dispacher_dir/filter6.rules" |
		ip6tables-restore -w || {
		echo Error: Loading filter.rules failed
		down
		exit 1
	}

}

add_rules_nft() {

	if [[ "$wan" =~ "ppp" ]]; then
		nft add table inet mangle
		nft add chain inet mangle FORWARD '{ type filter hook forward priority -150; policy accept; }'
		nft add rule inet mangle FORWARD oifname $wan tcp flags syn / syn,rst counter tcp option maxseg size set rt mtu

	fi

	nft add table ip nat
	nft add chain ip nat PREROUTING '{ type nat hook prerouting priority -100; policy accept; }'
	nft add chain ip nat POSTROUTING '{ type nat hook postrouting priority 100; policy accept; }'

	if [ -n "$dns_hijack" ]; then
		nft insert rule ip nat PREROUTING ip saddr $lan_net udp dport 53 counter dnat to $dns_hijack comment "dns_redir"
	fi

	if [ "${nat_type}" != "einat" ]; then
		if [ -n "${lan}" ] && [ -n "${lan_net}" ] && [ "${iptables_no_masq}" != "true" ]; then
			if [ "${nat_type}" = "fullcone" ]; then
				nft add rule ip nat PREROUTING iifname $wan counter fullcone
				nft add rule ip nat POSTROUTING oifname $lan ip daddr $lan_net counter fullcone
				nft add rule ip nat POSTROUTING oifname $wan ip saddr $lan_net counter fullcone
			else
				nft add rule ip nat POSTROUTING oifname $lan ip daddr $lan_net counter masquerade
				nft add rule ip nat POSTROUTING oifname $wan ip saddr $lan_net counter masquerade
			fi
		fi
	fi

	# Filter Rules
	sed "s/\$wan/$wan/g;s/\$lan/$lan/g;s/\$allowed_ports/$allowed_ports/g" "$dispacher_dir/filter.nft" |
		nft -f /dev/stdin || {
		echo Error: Loading filter.rules failed
		down
		exit 1
	}

}

add_rules_einat() {
	systemd-run -u _archwrt-dispatcher-einat.service \
		-p 'AmbientCapabilities=CAP_SYS_ADMIN CAP_NET_ADMIN' \
		-p 'CapabilityBoundingSet=CAP_SYS_ADMIN CAP_NET_ADMIN' \
		-p 'DynamicUser=yes' \
		-p 'User=einat' \
		-p 'NoNewPrivileges=yes' \
		-p 'ProtectSystem=strict' \
		-p 'ProtectHome=yes' \
		-p 'ConfigurationDirectory=einat' \
		-p 'PrivateTmp=yes' \
		-p 'ProtectKernelTunables=yes' \
		-p 'ProtectKernelModules=yes' \
		-p 'ProtectControlGroups=yes' \
		-p 'LockPersonality=yes' \
		-p 'RestrictRealtime=yes' \
		einat --ifname $wan --hairpin-if lo,$lan &>/dev/null

	if [ "$use_nftables" = "true" ]; then
		add_rules_nft
	else
		add_rules_legacy
	fi
}

up() {
	case $1 in
	default)
		wan=$(ip route |
			grep default |
			grep -o 'dev.*' |
			awk '{print $2}')
		[ -z "$wan" ] && {
			echo 'Read default interface from route failed!' 1>&2
			exit 1
		}
		;;
	*)
		wan=$1
		;;
	esac

	case $nat_type in
	einat) add_rules_einat ;;
	fullcone | masquerade)
		if [ "$use_nftables" = "true" ]; then
			add_rules_nft
		else
			add_rules_legacy
		fi
		;;
	*) ;;
	esac

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
