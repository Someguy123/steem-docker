#!/usr/bin/env bash

__DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
[ -z ${SRCED_00HLP+x} ] && source "$__DIR/000_helpers.sh"

registryBase='https://registry-1.docker.io'
authBase='https://auth.docker.io'
authService='registry.docker.io'
: ${remote_image="someguy123/steem"}
: ${remote_image_tag='latest'}

# Usage: get_docker_token (image)
# Grab an anonymous Docker auth token using curl
# If no arguments passed, gets a token for $remote_image
get_docker_token() {
    pkg_not_found jq jq
    pkg_not_found curl curl
    local rmt_img="$remote_image"
    (( $# > 0 )) && rmt_img="$1"
    curl -fsSL "$authBase/token?service=$authService&scope=repository:$rmt_img:pull" | jq --raw-output '.token'
}


get_all_tags() {
    local rmt_img="$remote_image"
    (( $# > 0 )) && rmt_img="$1"
    token=$(get_docker_token "$rmt_img")
    curl -fsSL -H "Authorization: Bearer $token" "${registryBase}/v2/${rmt_img}/tags/list" | jq
}

# Usage: get_latest_id (image) (tag)
# Outputs the SHA256 hash for the latest version of a docker image on Docker hub.
# If no arguments passed, fallsback to image $remote_image and tag $remote_image_tag
#
# Example:
#   $ get_latest_id someguy123/steem latest-mira
#   sha256:eeb7f8f7257f682748a1340d47f4e6e82fb73db755e5b35944fd4b113f9548e4
#
get_latest_id() {
    local rmt_img="$remote_image" rmt_tag="$remote_image_tag"
    (( $# > 0 )) && rmt_img="$1"
    (( $# > 1 )) && rmt_tag="$2"

    # returns full sha256
    # use ${myvar:7:12} to get 12 char image id
    token=$(get_docker_token "$rmt_img")
    curl_data=$(curl -fsSL \
        -H "Authorization: Bearer $token" \
        -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
        "${registryBase}/v2/${rmt_img}/manifests/${rmt_tag}")
    curl_status=$?
    if [[ "$curl_status" -ne 0 ]]; then
        return $curl_status
    fi
    jq -r ".config.digest" <<< "$curl_data"
}

