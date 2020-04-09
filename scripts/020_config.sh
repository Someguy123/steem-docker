#!/usr/bin/env bash

_XDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${_XDIR}/core.sh"

SIAB_LIB_LOADED[config]=1 # Mark this library script as loaded successfully

: ${CONFIG_FILE="${_XDIR}/../data/witness_node_data_dir/config.ini"}


function prepend_config() {
    local tmpconf=$(add-tmpfile)
    cp "$(get_config_location)" "$tmpconf"
    {
        echo "$1"
        cat "$tmpconf"
    } > "$(get_config_location)"
}

function get_config_location() {
    set +u
    if [[ -n ${CONFIG_FILE+x} ]]; then
        echo "$CONFIG_FILE"
    else
        echo "$PWD/config.ini"
    fi
    set -u
}

function has_item() {
    grep -c "^$1" "$(get_config_location)"
}

function config_set() {
    echo "Setting '$1' to '$2' in file $(get_config_location)"
    if [[ $(has_item $1) -eq 0 ]]; then
        # config item not found. try to uncomment
        sed -i -e 's/^#[[:space:]]'"$1"'.*/'"$1"' = '"$2"'/' "$(get_config_location)"
        if [[ $(has_item "$1") -eq 0 ]]; then
            echo "WARNING: $1 was not found as a comment. Prepending to the start of the file"
            # is it still not here? fine. we'll add it to the start
            prepend_config "$1 = $2"
        fi
    else
        # already an entry, let's replace it
        sed -i -e "s/^$1.*/$1 = $2/" "$(get_config_location)"
    fi
}

function add_seed() {
    prepend_config "seed-node = $1"
}

function config_unset() {
    for conitem in "$@"
    do
        echo "Removing item $conitem from $(get_config_location)"

        if [[ $(has_item $conitem) -eq 1 ]]; then
            sed -i -e 's/^'"$conitem"'.*/# \0/' "$(get_config_location)"
        fi
    done
}