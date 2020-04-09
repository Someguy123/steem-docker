#!/usr/bin/env bash

SIAB_SCRIPTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# return 0 if array (i.e. x=() ) exists, otherwise return 1
array-exists() { declare -p "$1" &> /dev/null; }

# if [ -z ${S_CORE_VER+x} ]; then
#     source "${SIAB_SCRIPTS_DIR}/000_shellcore_setup.sh"
#     _setup_shellcore
# fi

# Small shim in-case logging isn't loaded yet.
if ! command -v _debug > /dev/null; then 
    _debug() { ((SG_DEBUG<1)) && return; echo "$@"; } 
fi

if ! array-exists SIAB_LIB_LOADED; then
    _debug "[siab_libs.sh] SIAB_LIB_LOADED not set. Declaring SIAB_LIB_LOADED assoc array."
    declare -A SIAB_LIB_LOADED
    SIAB_LIB_LOADED=(
        [shellcoresetup]=0
        [helpers]=0
        [config]=0
        [docker]=0
        [stateshot]=0
    )
    
fi

if ! array-exists SIAB_LIBS; then
    _debug "[siab_libs.sh] SIAB_LIBS not set. Declaring SIAB_LIBS assoc array."
    declare -A SIAB_LIBS
    # We don't quote the keys - while bash ignores quotes, zsh treats them literally and would
    # require that the keys are accessed with the same quote style as they were set.
    SIAB_LIBS=( 
        [shellcoresetup]="${SIAB_SCRIPTS_DIR}/000_shellcore_setup.sh"
        [helpers]="${SIAB_SCRIPTS_DIR}/010_helpers.sh"
        [config]="${SIAB_SCRIPTS_DIR}/020_config.sh"
        [docker]="${SIAB_SCRIPTS_DIR}/030_docker.sh"
        [stateshot]="${SIAB_SCRIPTS_DIR}/040_stateshot.sh"
    )
fi

siab_load_lib() {
    (($#<1)) && { >&2 msgerr "[ERROR] siab_load_lib expects at least one argument!" && return 1; }
    local a
    for a in "$@"; do
        if ((${SIAB_LIB_LOADED[$a]}<1)); then
            _debug "[map_libs.siab_load_lib] Loading library '$a' from location '${SIAB_LIBS[$a]}' ..."
            source "${SIAB_LIBS[$a]}"
        else
            _debug "[map_libs.siab_load_lib] Library '$a' is already loaded..."
        fi
    done
}
