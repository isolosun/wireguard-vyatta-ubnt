#!/bin/bash
set -eEu -o pipefail
shopt -s expand_aliases

# Script must run as group 'vyattacfg' to prevent errors and system instability
if [ "$(id -g -n)" != 'vyattacfg' ] ; then
    echo "This script must be executed from vyatta configuration system."
    exit 1
fi

INTERFACE=$1

VYATTA_API=${vyatta_sbindir}/my_cli_shell_api
VYATTA_API_SLUG="interfaces wireguard $INTERFACE"
alias node_exists='$VYATTA_API exists $VYATTA_API_SLUG'
alias node_list='$VYATTA_API listNodes $VYATTA_API_SLUG'
alias node_value='$VYATTA_API returnValue $VYATTA_API_SLUG'
alias node_values='$VYATTA_API returnValues $VYATTA_API_SLUG'

###### DEBUG ######
echo -e "script: $(basename "$0")\nparam1: '${1:-}'"
set -x
###### DEBUG ######

# Create variable for ip route shorthand
ROUTE_SLUG="dev $INTERFACE scope link"
# Create array of all routes for interface
readarray -t ROUTES < <(ip route show $ROUTE_SLUG)
# Create array of all allowed-ips for interface
ALLOWED_IPS=( $(sudo wg show $INTERFACE allowed-ips | sed 's/^.*\t//;s/ /\n/g' | sort -nr -k 2 -t /) )
# Create variable for route-allowed-ips value
ROUTE_ALLOWED_IPS=$(node_value route-allowed-ips || true)

# If one or more routes exist for interface
if [ ${#ROUTES[@]} -gt 0 ]; then
    # Parse all routes for interface
    for route in ${ROUTES[@]}; do
        # Create variable for CIDR from route
        cidr=$(echo "$route" | awk '{print $1}')

        # If route does not match any allowed-ips
        if [[ ! " ${ALLOWED_IPS[@]} " =~ " ${cidr} " ]] || \
        # If route-allowed-ips is false *and* route has CIDR that matches one of the allowed-ips
        ([ "$ROUTE_ALLOWED_IPS" == "false" ] && \
        [[ " ${ALLOWED_IPS[@]} " =~ " ${cidr} " ]]); then
            # Delete route
            sudo ip route del $route $ROUTE_SLUG
        fi
    done
fi

# If route-allowed-ips is true
if [ "${ROUTE_ALLOWED_IPS:-x}" == "true" ]; then
    tnum="$(node_value route-table || true)"           ###### Currently not used ######

    # If allowed-ips exist
    if [ ${#ALLOWED_IPS[@]} -gt 0 ]; then
        # Parse all allowed-ips
        for ip in ${ALLOWED_IPS[@]}; do
            # Peer allowed-ips that are empty will return '(none)'
            # If ip is '(none)', then skip to the next in the list
            if [ $ip == "(none)" ]; then continue; fi

            # If ip does not exist in routing table
            if [[ ! " ${ROUTES[@]:-x} " =~ " ${ip} " ]]; then
                # Create route
                sudo ip route add $ip $ROUTE_SLUG
            fi
        done
    fi
fi
