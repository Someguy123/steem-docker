#!/usr/bin/env bash
#####################
#
# Various Bash Helper Functions to ease the pain of writing
# complex, user friendly bash scripts.
#
######
#
# Most parts written by Someguy123 https://github.com/Someguy123
# Some parts copied from elsewhere e.g. StackOverflow - but often improved by Someguy123
#
#####################

BOLD="$(tput bold)" RED="$(tput setaf 1)" GREEN="$(tput setaf 2)" YELLOW="$(tput setaf 3)" BLUE="$(tput setaf 4)" 
MAGENTA="$(tput setaf 5)" CYAN="$(tput setaf 6)" WHITE="$(tput setaf 7)" RESET="$(tput sgr0)"

# easy coloured messages function
# written by @someguy123
function msg () {
    # usage: msg [color] message
    if [[ "$#" -eq 0 ]]; then echo ""; return; fi;
    if [[ "$#" -eq 1 ]]; then
        echo -e "$1"
        return
    fi
    if [[ "$#" -gt 2 ]] && [[ "$1" == "bold" ]]; then
        echo -n "${BOLD}"
        shift
    fi
    _msg="[$(date +'%Y-%m-%d %H:%M:%S %Z')] ${@:2}"
    case "$1" in
        bold) echo -e "${BOLD}${_msg}${RESET}";;
        [Bb]*) echo -e "${BLUE}${_msg}${RESET}";;
        [Yy]*) echo -e "${YELLOW}${_msg}${RESET}";;
        [Rr]*) echo -e "${RED}${_msg}${RESET}";;
        [Gg]*) echo -e "${GREEN}${_msg}${RESET}";;
        * ) echo -e "${_msg}";;
    esac
}

export -f msg
export RED GREEN YELLOW BLUE BOLD NORMAL RESET


# From https://stackoverflow.com/a/8574392/2648583
# Usage: containsElement "somestring" "${myarray[@]}"
# Returns 0 (true) if element exists in given array, or 1 if it doesn't.
#
# Example:
# 
#     a=(hello world)
#     if containsElement "hello" "${a[@]}"; then
#         echo "The array 'a' contains 'hello'"
#     else
#         echo "The array 'a' DOES NOT contain 'hello'"
#     fi
#
containsElement () {
    local e match="$1"
    shift
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}

# Usage: yesno [message] (options...)
# Default functionality: returns 0 if yes, 1 if no, and repeat the question if answer is invalid.
# YesNo Function written by @someguy123
#
# Options:
#     Default return code:
#       defno - If empty answer, return 1 (no)
#       defyes - If empty answer, return 0 (yes)
#       deferr - If empty answer, return 3 (you must manually check $? return code)
#       fail - If empty answer, call 'exit 2' to terminate this script.
#     Flip return code:
#       invert - Flip the return codes - return 1 for yes, 0 for no. Bash will then assume no == true, yes == false
#
# Example:
# 
#     if yesno "Do you want to open this? (y/n) > "; then
#         echo "user said yes"
#     else
#         echo "user said no"
#     fi
#
#     yesno "Are you sure? (y/N) > " defno && echo "user said yes" || echo "user said no, or didn't answer"
#
yesno() {
    local MSG invert=0 retcode=3 defact="none" defacts
    defacts=('defno' 'defyes' 'deferr' 'fail')

    MSG="Do you want to continue? (y/n) > "
    (( $# > 0 )) && MSG="$1" && shift

    while (( $# > 0 )); do
        containsElement "$1" "${defacts[@]}" && defact="$1"
        [[ "$1" == "invert" ]] && invert=1
        shift
    done

    local YES=0 NO=1
    (( $invert == 1 )) && YES=1 NO=0

    unset answer
    while true; do
        read -p "$MSG" answer
        if [ -z "$answer" ]; then
            case "$defact" in
                defno)
                    retcode=$NO
                    break
                    ;;
                defyes)
                    retcode=$YES
                    (( $invert == 0 )) && retcode=0 || retcode=1
                    break
                    ;;
                fail)
                    exit 2
                    break
                    ;;
                *)
                    ;;
            esac
        fi
        case "$answer" in
            y|Y|yes|YES)
                retcode=$YES
                break
                ;;
            n|N|no|NO|nope|NOPE|exit)
                retcode=$NO
                break
                ;;
            *)
                msg red " (!!) Please answer by typing yes or no - or the characters y or n - then press enter."
                msg red " (!!) If you want to exit this program, press CTRL-C (hold CTRL and tap the C button on your keyboard)."
                msg
                ;;
        esac
    done
    return $retcode
}


APT_UPDATED="n"
pkg_not_found() {
    # check if a command is available
    # if not, install it from the package specified
    # Usage: pkg_not_found [cmd] [apt-package]
    # e.g. pkg_not_found git git
    if [[ $# -lt 2 ]]; then
        msg red "ERR: pkg_not_found requires 2 arguments (cmd) (package)"
        exit
    fi
    local cmd=$1
    local pkg=$2
    if ! [ -x "$(command -v $cmd)" ]; then
        msg yellow "WARNING: Command $cmd was not found. installing now..."
        if [[ "$APT_UPDATED" == "n" ]]; then
            sudo apt update -qy > /dev/null
            APT_UPDATED="y"
        fi
        sudo apt install -y "$pkg"
    fi
}

# This is an alias function to intercept commands such as 'sudo apt install' and avoid silent failure
# on systems that don't have sudo - especially if it's being ran as root. Some systems don't have sudo, 
# but if this script is being ran as root anyway, then we can just bypass sudo anyway and run the raw command.
#
# If we are in-fact a normal user, then check if sudo is installed - alert the user if it's not.
# If sudo is installed, then forward the arguments to the real sudo command.
#
sudo() {
  # If user is not root, check if sudo is installed, then use sudo to run the command
  if [ "$EUID" -ne 0 ]; then
    if ! [ -x "$(command -v sudo)" ]; then
      msg bold red "ERROR: You are not root, and you don't have sudo installed. Cannot run command '${@:1}'"
      msg red "Please either install sudo and add your user to the sudoers group, or run this script as root."
      sleep 5
      return 3
    fi
    /usr/bin/env sudo "${@:1}"
    return $?
  fi
  # If we got to this point, then the user is already root, so just drop the 'sudo' and run it raw.
  /usr/bin/env "${@:1}"
}

export -f sudo

