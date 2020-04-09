#!/usr/bin/env bash
#####################################################################################################
# Helper functions for installing, loading, and updating Privex ShellCore
# Part of someguy123/steem-docker
# Released under GNU AGPL by Someguy123
#
# Github: https://github.com/Someguy123/steem-docker
#
# **Steem-in-a-box** is a toolkit for using the Steem Docker images[1] published by @someguy123.
# It's purpose is to simplify the deployment of `steemd` nodes.
#
# For more information, see README.md - or run `./run.sh help`
#
# [1] https://hub.docker.com/r/someguy123/steem/tags/
#
#####################################################################################################

_XDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${_XDIR}/core.sh"

SIAB_LIB_LOADED[shellcoresetup]=1 # Mark this library script as loaded successfully

# Check that both SIAB_LIB_LOADED and SIAB_LIBS exist. If one of them is missing, then detect the folder where this
# script is located, and then source map_libs.sh using a relative path from this script.
# array-exists() { declare -p "$1" &> /dev/null; }
# { ! array-exists SIAB_LIB_LOADED || ! array-exists SIAB_LIBS ; } && source "${_XDIR}/siab_libs.sh" || true


# returns 0 if version $1 > $2
#   if version_gt 1.1.0 1.0.0; then 
#     echo "version 1.1.0 is newer than 1.0.0"
#   else
#     echo "version 1.1.0 is older than 1.0.0"
#   fi
#
# source: https://stackoverflow.com/a/24067243
version_gt() { test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"; }
# returns 0 if version $1 <= $2
version_lte() { version_gt "$@" && return 1 || return 0; }

# Error handling function for ShellCore
_sc_fail() { >&2 echo "Failed to load or install Privex ShellCore..." && exit 1; }

_setup_shellcore() {
    # Check if SG_DIR has been set in the environment.
    if [ -z ${SG_DIR+x} ]; then   # If not, detect if it's installed into HOME or globally. Fallback to auto-install via CDN.
        # Run ShellCore auto-install if we can't detect an existing ShellCore load.sh file.
        [[ -f "${HOME}/.pv-shcore/load.sh" ]] || [[ -f "/usr/local/share/pv-shcore/load.sh" ]] || \
            { curl -fsS https://cdn.privex.io/github/shell-core/install.sh | bash >/dev/null; } || _sc_fail

        # Attempt to load the local install of ShellCore first, then fallback to global install if it's not found.
        [[ -d "${HOME}/.pv-shcore" ]] && source "${HOME}/.pv-shcore/load.sh" || \
            source "/usr/local/share/pv-shcore/load.sh" || _sc_fail
    else  # If SG_DIR is set, then we should try loading ShellCore from that folder.
        source "${SG_DIR}/load.sh" || _sc_fail
    fi
}

_sc_force_update() {
    echo
    echo "${YELLOW} >>> Please wait a moment while we update ShellCore. This will only take a few seconds :)${RESET}"
    echo "${RESET}"
    set +u   # Ignore undefined variables until the script is finished reloading
    unset SG_LOAD_LIBS  # Do not load extra modules e.g. traplib until script has been reloaded
    update_shellcore
    source "${SG_DIR}/load.sh"
    echo "${GREEN} >>> Finished updating ShellCore :) - Current ShellCore Version: ${BOLD}${S_CORE_VER}${RESET}"
    _SIAB_RELOAD=1   # Inform run.sh that it must reload itself because ShellCore has been updated
}

_sc_version_check() {

    if ! version_gt "$SIAB_MIN_SC_VER" "$S_CORE_VER"; then
        return 0
    fi
    echo
    echo "${YELLOW} >>> Steem-in-a-box uses the Privex ShellCore library ( https://github.com/Privex/shell-core ) for certain functionality ${RESET}"
    echo
    echo " >>> Current Privex ShellCore version:     ${BOLD}${S_CORE_VER}${RESET}"
    echo " >>> Required Privex ShellCore version:    ${BOLD}${SIAB_MIN_SC_VER}${RESET} (or newer)${RESET}"
    echo
    echo "${YELLOW} >>> To ensure Steem-in-a-box functions correctly, we're going to update your Privex ShellCore installation immediately.${RESET}"
    echo "${YELLOW} >>> ShellCore is installed at: ${BOLD}${SG_DIR}${RESET}"
    _sc_force_update "$@"
}

_siab_sc_init() {
    # Load, or install + load Privex ShellCore.
    _setup_shellcore
    # Ensure user is running the minimum required version of ShellCore for this SIAB release.
    # If not, force a ShellCore update and restart the script.
    _sc_version_check "$@"
    # Quietly automatically update Privex ShellCore every 14 days (default)
    autoupdate_shellcore
}


