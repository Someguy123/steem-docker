#!/usr/bin/env bash

_XDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${_XDIR}/core.sh"
SIAB_LIB_LOADED[docker]=1 # Mark this library script as loaded successfully

_XDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check that both SIAB_LIB_LOADED and SIAB_LIBS exist. If one of them is missing, then detect the folder where this
# script is located, and then source map_libs.sh using a relative path from this script.
array-exists() { declare -p "$1" &> /dev/null; }
{ ! array-exists SIAB_LIB_LOADED || ! array-exists SIAB_LIBS ; } && source "${_XDIR}/siab_libs.sh" || true
SIAB_LIB_LOADED[docker]=1 # Mark this library script as loaded successfully


registryBase='https://registry-1.docker.io'
authBase='https://auth.docker.io'
authService='registry.docker.io'
remote_image="someguy123/steem"

get_docker_token() {
    if [[ ! $(command -v jq) ]]; then
        echo $RED"jq not found. Attempting to install..."$RESET
        sleep 3
        sudo apt update
        sudo apt install -y jq
    fi
    curl -fsSL "$authBase/token?service=$authService&scope=repository:$remote_image:pull" | jq --raw-output '.token'
}

get_all_tags() {
    token=$(get_docker_token)
    echo curl -H "Authorization: Bearer $token" "${registryBase}/v2/${remote_image}/tags/list"
    curl -fsSL -H "Authorization: Bearer $token" "${registryBase}/v2/${remote_image}/tags/list" | jq
}

get_latest_id() {
    # returns full sha256
    # use ${myvar:7:12} to get 12 char image id
    token=$(get_docker_token)
    curl_data=$(curl -fsSL \
        -H "Authorization: Bearer $token" \
        -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
        "${registryBase}/v2/${remote_image}/manifests/latest")
    curl_status=$?
    if [[ "$curl_status" -ne 0 ]]; then
        return $curl_status
    fi
    jq -r ".config.digest" <<< "$curl_data"
}

# get_container_ip [container_name_or_id]
# example:
#   ip=$(get_container_ip "my_container")
#   echo $ip   # outputs: 172.17.0.2
#
get_container_ip() {
    local ct_name="seed"

    (( $# > 0 )) && ct_name="$1"

    docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$ct_name"
}


