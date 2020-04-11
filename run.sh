#!/usr/bin/env bash
#####################################################################################################
# Steem node manager
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

BOLD="" RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" WHITE="" RESET=""
if [ -t 1 ]; then
    BOLD="$(tput bold)" RED="$(tput setaf 1)" GREEN="$(tput setaf 2)" YELLOW="$(tput setaf 3)" BLUE="$(tput setaf 4)"
    MAGENTA="$(tput setaf 5)" CYAN="$(tput setaf 6)" WHITE="$(tput setaf 7)" RESET="$(tput sgr0)"
fi

SIAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Array of Privex ShellCore modules to be loaded during ShellCore initialisation.
SG_LOAD_LIBS=(gnusafe helpers trap_helper traplib)
# Minimum required version of Privex ShellCore
# If a version older than this is installed, an update will be forced immediately
SIAB_MIN_SC_VER="0.4.3"
# Global variable used by 000_shellcore_setup:_sc_force_update to inform run.sh if it needs to restart the script
_SIAB_RELOAD=0

source "${SIAB_DIR}/scripts/siab_libs.sh"
source "${SIAB_DIR}/scripts/000_shellcore_setup.sh"

siab_load_lib shellcoresetup

_setup_shellcore

# _siab_sc_init "$@"

_sc_version_check "$@"

if (( _SIAB_RELOAD == 1 )); then
    _SIAB_RELOAD=0
    echo -e "${GREEN} >>> Attempting to restart run.sh using command + args: ${RESET}\n"
    echo "      $0 $*"
    echo
    echo -e "${GREEN} [...] Re-executing run.sh ...${RESET}\n\n"
    set +u          # Ignore undefined variables until the script is finished reloading
    cleanup_env     # Remove old SG_ and SRCED_ env vars before reloading to avoid conflicts
    exec "$0" "$@"  # Reload run.sh by replacing the currently running script with run.sh, using the same arguments as before.
    exit
fi

autoupdate_shellcore

# Privex ShellCore Error Handler
# 0 = Abort immediately upon a non-zero return code
# 1 = Ignore the next non-zero return code, then re-enable strict mode (0)
# 2 = Fully disable non-zero error handling, until manually re-enabled via 'error_control 0' or 'error_control 1'
error_control 2

# If set to 1, the run.sh function siab_exit() will ALWAYS print a full traceback at the end of each run.sh execution
# even if no error was detected.
: ${SIAB_TRACE_EXIT=0}

_ERROR_TRIGGERED=0
_SIAB_HANDLE_EXIT=1

print_traceback() { 
    local trace_depth=1
    (( $# > 0 )) && trace_depth=$(($1))
    msgerr nots bold blue "\nTraceback:\n\n${RESET}${BOLD}$(trap_traceback $trace_depth)\n"
}

siab_error() {
    local error_code="$?"
    msg
    msgerr bold red "A fatal error has occurred and SIAB run.sh must exit."
    (( $# >= 1 )) && msgerr bold red "Line number which triggered this: $1"
    (( $# >= 2 )) && msgerr bold red "Bash command / function which triggered this: $2"
    msg
    _ERROR_TRIGGERED=$error_code
    (( error_code == 0 )) && _ERROR_TRIGGERED=1
    exit $error_code
}

siab_exit() {
    local error_code="$?"
    (( _ERROR_TRIGGERED > 0 )) && error_code=$_ERROR_TRIGGERED
    if (( _SIAB_HANDLE_EXIT == 1 )); then
        msg
        # (( error_code == 0 )) && msgerr green "run.sh has finished - exiting SIAB run.sh cleanly."
        (( error_code != 0 )) && msgerr bold red "[ERROR] SIAB not exiting cleanly. Detected non-zero error code while exiting: $error_code"
    fi

    if (( SIAB_TRACE_EXIT == 1 )); then
        msgerr bold red "[DEBUGGING] Detected SIAB_TRACE_EXIT == 1 - always running traceback on exit. Exit code: $error_code"
        print_traceback -1
    fi
    exit $error_code
}

CLEANUP_FILES=()
CLEANUP_FOLDERS=()

siab_cleanup() {
    local path_len f
    for f in "${CLEANUP_FILES[@]}"; do
        path_len=$(len "$f")
        if (( path_len < 5 )); then
            msgerr bold yellow "WARNING: Not cleaning up leftover file '$f' as path is shorter than 5 chars."
            msgerr bold yellow "         This is to prevent accidental deletion of important system files."
        else
            _debug "Removing leftover file: $f"
            rm "$f"
        fi
    done
    for f in "${CLEANUP_FOLDERS[@]}"; do
        path_len=$(len "$f")
        if (( path_len < 5 )); then
            msgerr bold yellow "WARNING: Not cleaning up leftover folder '$f' as path is shorter than 5 chars."
            msgerr bold yellow "         This is to prevent accidental deletion of important system folders."
        else
            _debug "Removing leftover folder: $f"
            rm -r "$f"
        fi
    done
}

siab_abort() {
    local error_code="$?" s_line="$1" s_cmd="$2" s_signal="$3"
    msg "\n"
    msgerr bold red "[ERROR] Detected signal '$s_signal' while executing line number $s_line - last command: $s_cmd"
    print_traceback
    [[ "$s_signal" == "SIGINT" ]] && msgerr bold red "[ERROR] SIGINT (CTRL-C) detected. User requested SIAB to exit immediately. Stopping run.sh ..."
    msg "\n"

    _SIAB_HANDLE_EXIT=0 && error_control 2
    exit 5
}

declare -f -t siab_abort siab_error siab_exit print_traceback

trap_add 'siab_exit' EXIT                                    # ! ! ! TRAP EXIT ! ! !
trap_add 'siab_error ${LINENO} "$BASH_COMMAND"' ERR          # ! ! ! TRAP ERR ! ! !
trap_add 'siab_abort ${LINENO} "$BASH_COMMAND" SIGINT' SIGINT
trap_add 'siab_abort ${LINENO} "$BASH_COMMAND" SIGTERM' SIGTERM
trap_add 'siab_abort ${LINENO} "$BASH_COMMAND" SIGHUP' SIGHUP
# trap_add 'siab_error ${LINENO} "$BASH_COMMAND"' SIGINT       # ! ! ! TRAP ERR ! ! !
# trap_add 'siab_error ${LINENO} "$BASH_COMMAND"' SIGTERM      # ! ! ! TRAP ERR ! ! !
# trap_add 'siab_error ${LINENO} "$BASH_COMMAND"' SIGHUP      # ! ! ! TRAP ERR ! ! !

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
: ${DOCKER_DIR="$DIR/dkr"}
: ${FULL_DOCKER_DIR="$DIR/dkr_fullnode"}
: ${DATADIR="$DIR/data"}
: ${DOCKER_NAME="seed"}


if [[ -f .env ]]; then
    source .env
fi

: ${CONFIG_FILE="${DATADIR}/witness_node_data_dir/config.ini"}
: ${NETWORK="steem"}


if [[ "$NETWORK" == "hive" ]]; then
    : ${DOCKER_IMAGE="hive"}
    : ${STEEM_SOURCE="https://github.com/openhive-network/hive.git"}

    : ${NETWORK_NAME="Hive"}
    : ${SELF_NAME="Hive-in-a-box"}
    
    : ${BC_HTTP="http://files.privex.io/hive/block_log.lz4"}        # HTTP or HTTPS url to grab the blockchain from. Set compression in BC_HTTP_CMP
    : ${BC_HTTP_RAW="http://files.privex.io/hive/block_log"}        # Uncompressed block_log over HTTP
    : ${BC_HTTP_CMP="lz4"}                                          # Compression type, can be "xz", "lz4", or "no" (for no compression)
    : ${BC_RSYNC="rsync://files.privex.io/hive/block_log"}          # Anonymous rsync daemon URL to the raw block_log
    
    : ${ROCKSDB_RSYNC="rsync://files.privex.io/hive/rocksdb/"}      # Rsync URL for MIRA RocksDB files

    : ${DK_TAG_BASE="someguy123/hive"}

    : ${REMOTE_WS="wss://hived.privex.io"}
    : ${REMOTE_RPC="https://hived.privex.io"}

    : ${STOP_TIME=600}          # Amount of time in seconds to allow the docker container to stop before killing it.
    : ${STEEM_RPC_PORT="8091"}  # Local steemd RPC port, used by commands such as 'monitor' which need to query your steemd's HTTP RPC
fi

# the tag to use when running/replaying steemd
: ${DOCKER_IMAGE="steem"}

: ${NETWORK_NAME="Steem"}
: ${SELF_NAME="Steem-in-a-box"}

# HTTP or HTTPS url to grab the blockchain from. Set compression in BC_HTTP_CMP
: ${BC_HTTP="http://files.privex.io/steem/block_log.lz4"}

# Uncompressed block_log over HTTP, used for getting size for truncation, and
# potentially resuming downloads
: ${BC_HTTP_RAW="http://files.privex.io/steem/block_log"}

# Compression type, can be "xz", "lz4", or "no" (for no compression)
# Uses on-the-fly de-compression while downloading, to conserve disk space
# and save time by not having to decompress after the download is finished
: ${BC_HTTP_CMP="lz4"}

# Anonymous rsync daemon URL to the raw block_log, for repairing/resuming
# a damaged/incomplete block_log. Set to "no" to disable rsync when resuming.
: ${BC_RSYNC="rsync://files.privex.io/steem/block_log"}
# Rsync URL for MIRA RocksDB files
: ${ROCKSDB_RSYNC="rsync://files.privex.io/steem/rocksdb/"}

: ${DK_TAG_BASE="someguy123/steem"}
: ${DK_TAG="${DK_TAG_BASE}:latest"}
: ${DK_TAG_FULL="${DK_TAG_BASE}:latest-full"}
: ${SHM_DIR="/dev/shm"}
: ${REMOTE_WS="wss://steemd.privex.io"}
: ${REMOTE_RPC="https://steemd.privex.io"}
# Amount of time in seconds to allow the docker container to stop before killing it.
# Default: 600 seconds (10 minutes)
: ${STOP_TIME=600}

# Git repository to use when building Steem - containing steemd code
: ${STEEM_SOURCE="https://github.com/steemit/steem.git"}

# Local steemd RPC port, used by commands such as 'monitor' which need to query your steemd's HTTP RPC
: ${STEEM_RPC_PORT="8091"}

# Comma separated list of ports to expose to the internet.
# By default, only port 2001 will be exposed (the P2P seed port)
: ${PORTS="2001"}

# blockchain folder, used by dlblocks
: ${BC_FOLDER="$DATADIR/witness_node_data_dir/blockchain"}

: ${EXAMPLE_MIRA="$DATADIR/witness_node_data_dir/database.cfg.example"}
: ${MIRA_FILE="$DATADIR/witness_node_data_dir/database.cfg"}

: ${EXAMPLE_CONF="$DATADIR/witness_node_data_dir/config.ini.example"}
: ${CONF_FILE="$DATADIR/witness_node_data_dir/config.ini"}

# Set these environment vars to skip the yes/no prompts during fix-blocks
# 0 = default (prompt user for action),    1 = automatically answer "yes",    2 = automatically answer "no"
: ${AUTO_FIX_BLOCKLOG=0}
: ${AUTO_FIX_BLOCKINDEX=0}
: ${AUTO_FIX_ROCKSDB=0}

# If AUTO_FIX_BLOCKLOG is set to 1, this controls whether we verify block_log via checksummed rsync, in the
# event that the local block_log is the same size as the remote block_log
# 1 = (default) Do not attempt to verify/repair block_log if the size is equal to the remote server
# 0 = Attempt to verify/repair block_log even if the size is equal to the remote server
: ${AUTO_IGNORE_EQUAL=1}


BUILD_FULL=0        # Internal variable. Set to 1 by build_full to inform child functions
CUST_TAG="steem"    # Placeholder for custom tag var CUST_TAG (shared between functions)
BUILD_VER=""        # Placeholder for BUILD_VER shared between functions


# Array of additional arguments to be passed to Docker during builds
# Generally populated using arguments passed to build/build_full
# But you can specify custom additional build parameters by setting BUILD_ARGS
# as an array in .env
# e.g.
#
#    BUILD_ARGS=('--rm' '-q' '--compress')
#
BUILD_ARGS=()

# MSG_TS_DEFAULT controls whether timestamps are automatically added to any 
# message that doesn't opt-out using 'nots', or whether messages need to 
# specify 'ts' to enable timestamps.
# This allows timestamps to be temporarily disabled per function, preventing the need to
# constantly add "nots".
#
# 1 = msg timestamps are opt-out (to disable timestamps: msg nots green "some message")
# 0 = msg timestamps are opt-in  (to enable timestamps:  msg ts green "some message")
MSG_TS_DEFAULT=1

# easy coloured messages function
# written by @someguy123
function msg () {
    if [[ "$#" -eq 0 ]]; then echo ""; return; fi;
    if [[ "$#" -eq 1 ]]; then
        echo -e "$1"
        return
    fi

    _msg=""

    if (( MSG_TS_DEFAULT == 1 )); then
        [[ "$1" == "ts" ]] && shift
        { [[ "$1" == "nots" ]] && shift; } || _msg="[$(date +'%Y-%m-%d %H:%M:%S %Z')] "
    else
        [[ "$1" == "nots" ]] && shift
        [[ "$1" == "ts" ]] && shift && _msg="[$(date +'%Y-%m-%d %H:%M:%S %Z')] "
    fi

    if [[ "$#" -gt 2 ]] && [[ "$1" == "bold" ]]; then
        echo -n "${BOLD}"
        shift
    fi
    (($#==1)) && _msg+="$@" || _msg+="${@:2}"

    case "$1" in
        bold) echo -e "${BOLD}${_msg}${RESET}";;
        BLUE|blue) echo -e "${BLUE}${_msg}${RESET}";;
        YELLOW|yellow) echo -e "${YELLOW}${_msg}${RESET}";;
        RED|red) echo -e "${RED}${_msg}${RESET}";;
        GREEN|green) echo -e "${GREEN}${_msg}${RESET}";;
        CYAN|cyan) echo -e "${CYAN}${_msg}${RESET}";;
        MAGENTA|magenta|PURPLE|purple) echo -e "${MAGENTA}${_msg}${RESET}";;
        * ) echo -e "${_msg}";;
    esac
}

export -f msg
export RED GREEN YELLOW BLUE BOLD NORMAL RESET

# load helpers
# source "${SIAB_DIR}/scripts/010_helpers.sh"

siab_load_lib helpers docker stateshot

# if the config file doesn't exist, try copying the example config
if [[ ! -f "$CONF_FILE" ]]; then
    if [[ -f "$EXAMPLE_CONF" ]]; then
        echo "${YELLOW}File config.ini not found. copying example (seed)${RESET}"
        cp -vi "$EXAMPLE_CONF" "$CONF_FILE" 
        echo "${GREEN} > Successfully installed example config for seed node.${RESET}"
        echo " > You may want to adjust this if you're running a witness, e.g. disable p2p-endpoint"
    else
        echo "${YELLOW}WARNING: You don't seem to have a config file and the example config couldn't be found...${RESET}"
        echo "${YELLOW}${BOLD}You may want to check these files exist, or you won't be able to launch Steem${RESET}"
        echo "Example Config: $EXAMPLE_CONF"
        echo "Main Config: $CONF_FILE"
    fi
fi

if [[ ! -f "$MIRA_FILE" ]]; then
    if [[ -f "$EXAMPLE_MIRA" ]]; then
        echo "${YELLOW}File database.cfg not found. copying example ${RESET}"
        cp -vi "$EXAMPLE_MIRA" "$MIRA_FILE" 
        echo "${GREEN} > Successfully installed example MIRA config.${RESET}"
        echo " > You may want to adjust this depending on your resources and type of node:"
        echo " - - > https://github.com/steemit/steem/blob/master/doc/mira.md"

    else
        echo "${YELLOW}WARNING: You don't seem to have a MIRA config file (data/database.cfg) and the example config couldn't be found...${RESET}"
        echo "${YELLOW}${BOLD}You may want to check these files exist, or you won't be able to use Steem with MIRA${RESET}"
        echo "Example Config: $EXAMPLE_MIRA"
        echo "Main Config: $MIRA_FILE"
    fi
fi

IFS=","
DPORTS=()
for i in $PORTS; do
    if [[ $i != "" ]]; then
        if grep -q ":" <<< "$i"; then
            DPORTS+=("-p$i")
        else
            DPORTS+=("-p0.0.0.0:$i:$i")
        fi
    fi
done

# load docker hub API
# source "${SIAB_DIR}/scripts/030_docker.sh"

# source "${SIAB_DIR}/scripts/040_stateshot.sh"

help() {
    echo "Usage: $0 COMMAND [DATA]"
    echo
    echo "Commands: 
    start           - starts ${NETWORK_NAME} container
    stop            - stops ${NETWORK_NAME} container
    kill            - force stop ${NETWORK_NAME} container (in event of steemd hanging indefinitely)
    restart         - restarts ${NETWORK_NAME} container
    replay          - starts ${NETWORK_NAME} container (in replay mode)
    memory_replay   - starts ${NETWORK_NAME} container (in replay mode, with --memory-replay - for use with MIRA-enabled images only)
    status          - show status of ${NETWORK_NAME} container

    ver             - check version of ${SELF_NAME}, your ${NETWORK_NAME} docker image, and detect if any updates are available

    fix-blocks      - downloads / repairs your blockchain, block index, and/or rocksdb. 
                      check '$0 fix-blocks help' for more info

    clean           - Remove blockchain, p2p, and/or shared mem folder contents (warns beforehand)
    dlblocks        - download and decompress the blockchain and block_log.index to speed up your first start
    dlblockindex    - download/repair just the block index (block_log.index)
    dlrocksdb       - download / replace RocksDB files - for use with MIRA-enabled ${NETWORK_NAME} images

    shm_size        - resizes /dev/shm to size given, e.g. ./run.sh shm_size 10G 

    install_docker  - install docker
    install         - pulls latest docker image from server (no compiling)
    install_full    - pulls latest (FULL NODE FOR RPC) docker image from server (no compiling)
    rebuild         - builds ${NETWORK_NAME} container (from docker file), and then restarts it
    build           - only builds ${NETWORK_NAME} container (from docker file)
    
    logs            - show all logs inc. docker logs, and ${NETWORK_NAME} logs

    wallet          - open cli_wallet in the container
    remote_wallet   - open cli_wallet in the container connecting to a remote seed

    enter           - enter a bash session in the currently running container
    shell           - launch the ${NETWORK_NAME} container with appropriate mounts, then open bash for inspection
    "
    echo
    exit
}

APT_UPDATED="n"
pkg_not_found() {
    # check if a command is available
    # if not, install it from the package specified
    # Usage: pkg_not_found [cmd] [apt-package]
    # e.g. pkg_not_found git git
    if [[ $# -lt 2 ]]; then
        echo "${RED}ERR: pkg_not_found requires 2 arguments (cmd) (package)${NORMAL}"
        exit
    fi
    local cmd=$1
    local pkg=$2
    if ! [ -x "$(command -v $cmd)" ]; then
        echo "${YELLOW}WARNING: Command $cmd was not found. installing now...${NORMAL}"
        if [[ "$APT_UPDATED" == "n" ]]; then
            sudo apt update -y
            APT_UPDATED="y"
        fi
        sudo apt install -y "$pkg"
    fi
}

optimize() {
    echo    75 | sudo tee /proc/sys/vm/dirty_background_ratio
    echo  1000 | sudo tee /proc/sys/vm/dirty_expire_centisecs
    echo    80 | sudo tee /proc/sys/vm/dirty_ratio
    echo 30000 | sudo tee /proc/sys/vm/dirty_writeback_centisecs
}

parse_build_args() {
    BUILD_VER=$1
    CUST_TAG="steem:$BUILD_VER"
    if (( $BUILD_FULL == 1 )); then
        CUST_TAG+="-full"
    fi
    BUILD_ARGS+=('--build-arg' "steemd_version=${BUILD_VER}")
    shift
    if (( $# >= 2 )); then
        if [[ "$1" == "tag" ]]; then
            CUST_TAG="$2"
            msg yellow " >> Custom re-tag specified. Will tag new image with '${CUST_TAG}'"
            shift; shift;    # Get rid of the two tag arguments. Everything after is now build args
        fi
    fi
    local has_steem_src='n'
    if (( $# >= 1 )); then
        msg yellow " >> Additional build arguments specified."
        for a in "$@"; do
            msg yellow " ++ Build argument: ${BOLD}${a}"
            BUILD_ARGS+=('--build-arg' "$a")
            if grep -q 'STEEM_SOURCE' <<< "$a"; then
                has_steem_src='y'
            fi
        done
    fi

    if [[ "$has_steem_src" == "y" ]]; then
        msg bold yellow " [!!] STEEM_SOURCE has been specified in the build arguments. Using source from build args instead of global"
    else
        msg bold yellow " [!!] Did not find STEEM_SOURCE in build args. Using STEEM_SOURCE from environment:"
        msg bold yellow " [!!] STEEM_SOURCE = ${STEEM_SOURCE}"
        BUILD_ARGS+=('--build-arg' "STEEM_SOURCE=${STEEM_SOURCE}")
    fi
    
    msg blue " ++ CUSTOM BUILD SPECIFIED. Building from branch/tag ${BOLD}${BUILD_VER}"
    msg blue " ++ Tagging final image as: ${BOLD}${CUST_TAG}"
    msg yellow " -> Docker build arguments: ${BOLD}${BUILD_ARGS[@]}"
}

build_local() {
    STEEM_SOURCE="local_src_folder"
    DOCKER_DIR="${DIR}/dkr_local"

    if [[ ! -d "${DOCKER_DIR}/src" ]]; then
        msg bold red "ERROR: You must place the source code inside of ${DOCKER_DIR}/src"
        return 1
    fi

    msg green " >>> Local build requested."
    msg green " >>> Will build Steem using code stored in '${DOCKER_DIR}/src' instead of remote git repo"
    build "$@"
}

# Build standard low memory node as a docker image
# Usage: ./run.sh build [version] [tag tag_name] [build_args]
# Version is prefixed with v, matching steem releases
# e.g. build v0.20.6
#
# Override destination tag:
#   ./run.sh build v0.21.0 tag 'steem:latest'
#
# Additional build args:
#   ./run.sh build v0.21.0 ENABLE_MIRA=OFF
#
# Or combine both:
#   ./run.sh build v0.21.0 tag 'steem:mira' ENABLE_MIRA=ON
#
build() {
    fmm="Low Memory Mode (For Seed / Witness nodes)"
    (( $BUILD_FULL == 1 )) && fmm="Full Memory Mode (For RPC nodes)" && DOCKER_DIR="$FULL_DOCKER_DIR"
    BUILD_MSG=" >> Building docker container [[ ${fmm} ]]"
    if (( $# >= 1 )); then
        parse_build_args "$@"
        sleep 2
        cd "$DOCKER_DIR"
        msg bold green "$BUILD_MSG"
        docker build "${BUILD_ARGS[@]}" -t "$CUST_TAG" .
        ret=$?
        if (( $ret == 0 )); then
            echo "${RED}
    !!! !!! !!! !!! !!! !!! READ THIS !!! !!! !!! !!! !!! !!!
    !!! !!! !!! !!! !!! !!! READ THIS !!! !!! !!! !!! !!! !!!
        For your safety, we've tagged this image as $CUST_TAG
        To use it in this ${SELF_NAME}, run: 
        ${GREEN}${BOLD}
        docker tag $CUST_TAG ${DOCKER_IMAGE}:latest
        ${RESET}${RED}
    !!! !!! !!! !!! !!! !!! READ THIS !!! !!! !!! !!! !!! !!!
    !!! !!! !!! !!! !!! !!! READ THIS !!! !!! !!! !!! !!! !!!
        ${RESET}
            "
            msg bold green " +++ Successfully built steemd"
            msg green " +++ Steem node type: ${BOLD}${fmm}"
            msg green " +++ Version/Branch: ${BOLD}${BUILD_VER}"
            msg green " +++ Build args: ${BOLD}${BUILD_ARGS[@]}"
            msg green " +++ Docker tag: ${CUST_TAG}"
        else
            msg bold red " !!! ERROR: Something went wrong during the build process."
            msg red " !!! Please scroll up and check for any error output during the build."
        fi
        return
    fi
    msg bold green "$BUILD_MSG"
    cd "$DOCKER_DIR"
    docker build -t "$DOCKER_IMAGE" .
    ret=$?
    if (( $ret == 0 )); then
        msg bold green " +++ Successfully built current stable steemd"
        msg green " +++ Steem node type: ${BOLD}${fmm}"
        msg green " +++ Docker tag: ${DOCKER_IMAGE}"
    else
        msg bold red " !!! ERROR: Something went wrong during the build process."
        msg red " !!! Please scroll up and check for any error output during the build."
    fi
}

# Build full memory node (for RPC nodes) as a docker image
# Usage: ./run.sh build_full [version]
# Version is prefixed with v, matching steem releases
# e.g. build_full v0.20.6
build_full() {
    BUILD_FULL=1
    build "$@"
}

# Usage: ./run.sh dlblocks [override_dlmethod] [url] [compress]
# Download the block_log from a remote server and de-compress it on-the-fly to save space, 
# then places it correctly into $BC_FOLDER
# Automatically attempts to resume partially downloaded block_log's using rsync, or http if
# rsync is disabled in .env
# 
#   override_dlmethod - use this to force downloading a certain way (OPTIONAL)
#                     choices:
#                       - rsync - download via rsync, resume if exists, using append-verify and ignore times
#                       - rsync-replace - download whole file via rsync, delete block_log before download
#                       - http - download via http. if uncompressed, try to resume when possible
#                       - http-replace - do not attempt to resume. delete block_log before download
#
#   url - Download/install block log using the supplied dlmethod from this url. (OPTIONAL)
#
#   compress -  Only valid for http/http-replace. Decompress the file on the fly. (OPTIONAL)
#               options: xz, lz4, no (no compression) 
#               if a custom url is supplied, but no compression method, it is assumed it is raw and not compressed.
#
# Example: The default compressed lz4 download failed, but left it's block_log in place. 
# You don't want to use rsync to resume, because your network is very fast
# Instead, you can continue your download using the uncompressed version over HTTP:
#
#   ./run.sh dlblocks http "http://files.privex.io/steem/block_log"
#
# Or just re-download the whole uncompressed file instead of resuming:
#
#   ./run.sh dlblocks http-replace "http://files.privex.io/steem/block_log"
#
dlblocks() {
    pkg_not_found rsync rsync
    pkg_not_found lz4 liblz4-tool
    pkg_not_found xz xz-utils
    
    [[ ! -d "$BC_FOLDER" ]] && mkdir -p "$BC_FOLDER"
    [[ -f "$BC_FOLDER/block_log.index" ]] && msg "Removing old block index" && sudo rm -vf "$BC_FOLDER/block_log.index" 2> /dev/null

    if (( $# > 0 )); then
        custom-dlblocks "$@"
        return $?
    fi
    if [[ -f "$BC_FOLDER/block_log" ]]; then
        msg yellow "It looks like block_log already exists"
        if [[ "$BC_RSYNC" == "no" ]]; then
            msg red "As BC_RSYNC is set to 'no', we're just going to try to retry the http download"
            msg "If your HTTP source is uncompressed, we'll try to resume it"
            dl-blocks-http "$BC_HTTP" "$BC_HTTP_CMP"
            return
        else
            msg green "We'll now use rsync to attempt to repair any corruption, or missing pieces from your block_log."
            dl-blocks-rsync "$BC_RSYNC"
            return
        fi
    fi
    msg "No existing block_log found. Will use standard http to download, and will\n also decompress lz4 while downloading, to save time."
    msg "If you encounter an error while downloading the block_log, just run dlblocks again,\n and it will use rsync to resume and repair it"
    dl-blocks-http "$BC_HTTP" "$BC_HTTP_CMP" 
    msg "FINISHED. Blockchain installed to ${BC_FOLDER}/block_log (make sure to check for any errors above)"
    msg red "If you encountered an error while downloading the block_log, just run dlblocks again\n and it will use rsync to resume and repair it"
    echo "Remember to resize your /dev/shm, and run with replay!"
    echo "$ ./run.sh shm_size SIZE (e.g. 8G)"
    echo "$ ./run.sh replay"
}


# internal helper function for handling AUTO_FIX_ prompts
# if first arg is 1, will return 0 (true) immediately
# if first arg is 2, will return 1 (false) immediately
# if first arg is any other number, e.g. 0, then will display a prompt using 'yesno' with arg 2+
#
# usage:
#     if _fixbl_prompt ${AUTO_FIX_BLOCKLOG} "Trim blocklog? (y/N) > " defno; then
#       echo "trimming blocklog"
#     else
#       echo "not trimming blocklog"
#     fi
#
_fixbl_prompt() {
    (( $1 == 1 )) || { (( $1 != 2 )) && yesno "${@:2}"; };
}

local-file-size() {
    local curr_os=$(uname -s)

    if grep -qi "linux" <<< "$curr_os"; then
        stat --printf="%s" "$1"
    elif egrep -qi "darwin|freebsd|openbsd" <<< "$curr_os"; then
        stat -f "%z" "$1"
    else
        du --apparent-size --block-size=1 "$1"
    fi
}

# usage: fix-blocks-blocklog (path to local block_log)
#
# example:
#   # With no arguments, it will default to ${BC_FOLDER}/block_log
#   fix-blocks-blocklog
#   # Otherwise, you can specify the path to the local block_log to be repaired
#   fix-blocks-blocklog "/steem/data/witness_node_data_dir/blockchain/block_log"
#
fix-blocks-blocklog() {
    msg
    msg bold green " ========================================================================"
    msg bold green " =                                                                      ="
    msg bold green " =      Updating, trimming, and validating your block_log               ="
    msg bold green " =                                                                      ="
    msg bold green " ========================================================================"
    msg

    local local_bsz=0 local_bl="${BC_FOLDER}/block_log"
    local remote_bsz=$(remote-file-size "$BC_HTTP_RAW" | tr -d '\r')
    (( $# > 0 )) && local_bl="$1"
    _debug "before local-file-size"
    if [[ -f "$local_bl" ]]; then
        local_bsz=$(local-file-size "$local_bl")
    fi

    _debug "before casting local_bsz / remote_bsz"
    _debug "local_bsz   is:   $local_bsz"
    _debug "remote_bsz  is:   $remote_bsz"

    _debug "casting remote_bsz"
    remote_bsz=$((remote_bsz))
    _debug "casting local_bsz"
    local_bsz=$((local_bsz))

    msg
    msg nots cyan   "    Local block_log path:    ${BOLD}$local_bl"
    msg nots cyan   "    Local block_log size:    ${BOLD}$local_bsz bytes"
    msg
    msg nots cyan   "    Remote block_log URL:    ${BOLD}$BC_HTTP_RAW"
    msg nots cyan   "    Remote block_log size:   ${BOLD}$remote_bsz bytes"
    msg

    _debug "before if (( $local_bsz > $remote_bsz ))"

    if (( $local_bsz > $remote_bsz )); then
        msg nots yellow " >> Your block_log file is larger than the remote block_log at $BC_HTTP_RAW"
        msg
        msg nots yellow " >> To repair your block_log - we'll need to trim it"
        msg nots yellow " >> You won't be able to use the remote server's copy of block_log.index, and/or RocksDB unless your block_log"
        msg nots yellow " >> is the same size as the server's copy."
        msg
        if _fixbl_prompt "$AUTO_FIX_BLOCKLOG" " ${MAGENTA}Do you want to trim your block_log down to $remote_bsz bytes?${RESET} (y/n) > "; then
            msg green " [...] Trimming local block_log down to $remote_bsz bytes..."
            truncate -s "$remote_bsz" "$local_bl"
            msg green " [+++] Truncated block_log down to $remote_bsz bytes."
        else
            msg red " [!!!] Not trimming block_log"
        fi
    elif (( $local_bsz < $remote_bsz )); then
        msg nots yellow " >> Your block_log file is smaller than the remote block_log at $BC_HTTP_RAW"
        msg
        msg nots yellow " >> To repair your block_log - we'll need to download the rest of the block_log using rsync, "
        msg nots yellow " >> which will append to your block_log, instead of downloading it from scratch."
        msg nots yellow " >> You won't be able to use the remote server's copy of block_log.index, and/or RocksDB unless your block_log"
        msg nots yellow " >> is the same size as the server's copy."
        msg
        if _fixbl_prompt "$AUTO_FIX_BLOCKLOG" " ${MAGENTA}Do you want to download the rest of the block_log?${RESET} (y/n) > "; then
            msg green " [...] Downloading block_log via rsync using --append ..."
            rsync -Ivh --progress --append "$BC_RSYNC" "$local_bl"
            msg green " [+++] Finished downloading block_log"
        else
            msg red " [!!!] Not downloading block_log"
        fi
    else
        msg nots yellow " >> It appears your local block_log is the same size as the remote block_log at $BC_HTTP_RAW"
        msg
        msg nots yellow " >> If you believe your block_log is corrupted, we can repair it using rsync."
        msg nots yellow " >> WARNING: This may take several hours, depending on your disk speed, network, and CPU performance."
        msg nots yellow " >> You can say no, and we'll continue with the next fix-blocks step."
        msg

        # If AUTO_FIX_BLOCK_LOG is set to 1 (auto yes), but AUTO_IGNORE_EQUAL is also set to 1 (ignore equal size), 
        # then we need to change _auto_fix to 2 (auto no), since the block_log is the same size as the remote server.
        local _auto_fix=$(($AUTO_FIX_BLOCKLOG))
        (( AUTO_FIX_BLOCKLOG == 1 )) && (( AUTO_IGNORE_EQUAL == 1 )) && _auto_fix=2

        if _fixbl_prompt "$_auto_fix" " ${MAGENTA}Do you want to check your block_log for corruption via rsync?${RESET} (y/N) > " defno; then
            msg green " [...] Verifying / repairing block_log via rsync using --inplace ..."
            msg green " [...] It may take 30-60 minutes before you see any progress here ..."
            rsync -Ivhc --progress --inplace "$BC_RSYNC" "$local_bl"
            msg green " [+++] Finished validating block_log"
        else
            msg nots red "\n [!!!] Not validating block_log"
        fi
    fi
    return 0
}

fix-blocks-index() {
    error_control 0

    msg
    msg bold green " ========================================================================"
    msg bold green " =                                                                      ="
    msg bold green " =      Downloading / replacing your block_log.index                    ="
    msg bold green " =                                                                      ="
    msg bold green " ========================================================================"
    msg
    

    local local_idx="${BC_FOLDER}/block_log.index"
    (( $# > 0 )) && local_idx="$1"

    if _fixbl_prompt "$AUTO_FIX_BLOCKINDEX" "${MAGENTA}Do you want to replace your block_log.index to match the server?${RESET} (Y/n) > " defyes; then
        msg green " [...] Updating block_log.index to match the remote server's copy ..."
        # raise_error "something went wrong"
        rsync -Ivhc --partial-dir="${DIR}/.rsync-partial" --progress "${BC_RSYNC}.index" "${local_idx}"
        msg green " [+++] Finished downloading/validating block_log.index"
    else
        msg nots red "\n [!!!] Not replacing block_log.index"
    fi
}

fix-blocks-rocksdb() {
    msg
    msg bold green " ========================================================================"
    msg bold green " =                                                                      ="
    msg bold green " =      Synchronising RocksDB Files for MIRA nodes                      ="
    msg bold green " =                                                                      ="
    msg bold green " ========================================================================"
    msg

    msg nots yellow " >> If you use a MIRA-enabled image, i.e. using RocksDB instead of shared_memory.bin, then your"
    msg nots yellow " >> RocksDB files must have been generated using the same block_log and block_log.index"
    msg
    msg nots cyan   "    Local RocksDB/SHM_DIR folder:    ${BOLD}$SHM_DIR"
    msg nots cyan   "    Remote RocksDB source:           ${BOLD}$ROCKSDB_RSYNC"
    msg
    msg nots yellow " >> If you've repaired your block_log or block_log.index, and you use MIRA, then it's important that"
    msg nots yellow " >> your RocksDB files match the remote server's copy exactly."
    msg
    if _fixbl_prompt "$AUTO_FIX_ROCKSDB" " ${MAGENTA}Do you want to synchronise your MIRA RocksDB files with the server?${RESET} (y/N) > " defno; then
        msg
        msg nots green "\n [...] Updating RocksDB files to match the remote server's copy ..."
        _SILENCE_RDB_INTRO=1 dlrocksdb
        msg
        msg green " [+++] Finished downloading/validating RocksDB files into $SHM_DIR \n"
    else
        msg nots red "\n [!!!] Not synchronising RocksDB files with remote server \n"
    fi
}

_fix_blocks_help() {
    MSG_TS_DEFAULT=0
    msg
    msg green "Usage:"
    msg green "    $0 fix-blocks (blocklog|index|rocksdb|all) (auto)"
    msg
    msg yellow "Examples:"
    msg bold   "\t # Download/replace/repair the block_log, block_log.index, and rocksdb files - prompting user before starting each action"
    msg bold   "\t $0 fix-blocks"
    msg
    msg bold   "\t # Compare the local block_log size against the remote server block_log, will show a yes/no prompt allowing user to decide"
    msg bold   "\t # whether or not to update / verify / truncate their local block_log."
    msg bold   "\t $0 fix-blocks blocklog"
    msg
    msg bold   "\t # Synchronise RocksDB files with server, and skip the yes/no prompt"
    msg bold   "\t $0 fix-blocks rocksdb auto"
    msg
    msg bold   "\t # Automatically attempt to repair block_log and block_log.index non-interactively, while skipping the RocksDB download/repair step."
    msg bold   "\t AUTO_FIX_BLOCKLOG=1 AUTO_FIX_BLOCKINDEX=1 AUTO_FIX_ROCKSDB=2 $0 fix-blocks"
    msg
    msg yellow "If no blockchain component is specified (e.g. blocklog or index), fix-blocks will try to repair (with prompts) in order:" 
    msg
    msg yellow "    - block_log"
    msg yellow "    - block_log.index"
    msg yellow "    - rocksdb"
    msg

    msg bold green "Environment Variables"
    msg
    msg green " Several AUTO_FIX_ env vars are available, allowing the fix-blocks yes/no prompts to be automatically answered."
    msg green " They're most useful when running fix-blocks from within a non-interactive script, e.g. via crontab. "
    msg
    msg green " All AUTO_FIX_ env vars can be one of three values:"
    msg green "     0 = prompt before taking action (default)"
    msg green "     1 = automatically answer yes to prompts"
    msg green "     2 = automatically answer no to prompts"
    msg
    msg green " - AUTO_FIX_BLOCKLOG   (def: 0) - Controls whether block_log update/verify/truncate prompt is automatically responded to"
    msg green " - AUTO_FIX_BLOCKINDEX (def: 0) - Controls whether block_log.index synchronization prompt is automatically responded to"
    msg green " - AUTO_FIX_ROCKSDB    (def: 0) - Controls whether rocksdb synchronization prompt is automatically responded to"
    msg
    msg green " - AUTO_IGNORE_EQUAL   (def: 1) - Additional control when AUTO_FIX_BLOCKLOG is set to 1 (auto yes) - controls whether block_log"
    msg green "                       should be rsync verified against the remote server in the event that the local block_log is the same size"
    msg green "                       as the remote block_log."
    msg
    msg green "                       When set to 1:   Do not attempt to verify/repair the block_log if it's the same size as the remote server"
    msg green "                       When set to 0:   Always verify/repair the block_log, even when it's the same size as the remote server"
    msg
    
    msg
    msg bold green "Available fix-blocks actions and descriptions"
    msg
    msg green " blocklog / block_log / blocks      - Fast and easy repair of local block_log, using size comparisons against the remote"
    msg green "                                      blockchain mirror. Uses rsync to quickly append to block_log if it's too small, while"
    msg green "                                      using inplace rsync with checksumming to test block_log for corruption if block_log is the same size. "
    msg green "                                      If local block_log is larger than the remote server's, the command can automatically trim the "
    msg green "                                      block_log to the correct size."
    msg
    msg green " index / blockindex / block_index   - Download / replace / repair local block_log.index from remote blockchain mirror, using rsync with checksumming. "
    msg
    msg green " rocksdb / rocks / mira             - Download / replace / repair local RocksDB files (for MIRA images) from remote blockchain mirror, "
    msg green "                                      using rsync with checksumming, and partial-dir allowing for resuming of download if it fails. "
    msg

    MSG_TS_DEFAULT=1

}

fix-blocks() {
    error_control 0
    local local_bl="${BC_FOLDER}/block_log"
    if (( $# > 0 )); then
        case "$1" in
            help|HELP|--help|-h|-?)
                _fix_blocks_help
                return $?;;
            
            blocklog|blocks|block_log|blockchain)
                fix-blocks-blocklog
                return $?;;
            
            index|blockindex|block_index|block_log.index)
                fix-blocks-index
                return $?;;
            
            rocks*|mira|MIRA)
                fix-blocks-rocksdb
                return $?;;
            
            all)
                echo
                ;;
            
            *)
                msg bold red "\n[!!!] Invalid option '$1' ...\n"
                msg red " > Displaying fix-blocks help."
                sleep 0.5
                _fix_blocks_help
                return 0
                ;;

        esac
    fi      
    msg
    fix-blocks-blocklog "$local_bl"
    msg "\n"
    fix-blocks-index "${local_bl}.index"
    msg "\n"
    fix-blocks-rocksdb
    msg "\n"
    return 0
}

# usage: insert_env [env_line] (env_file)
# example:
#
#       insert_env "SHM_DIR=${DATADIR}/rocksdb"
#
#       insert_env "DATADIR=/steem/data" "/steem/.env"
#
insert_env() {
    local env_line="$1" env_file="${DIR}/.env"

    (( $# >= 2 )) && env_file="$2"

    local env_dir="$(dirname "$env_file")"

    # If the .env file doesn't exist, then we need to attempt to create it
    if [[ ! -f "$env_file" ]]; then
        msg yellow " [...] File '$env_file' does not exist. Creating it."

        # Check if we 
        if ! ( [[ -w "$env_dir" ]] && [[ -x "$env_dir" ]] ) && ! can_write "$env_dir"; then
            msg bold red " [!!!] ERROR: Your user does not have permission to write to '$env_dir'"
            if ! sudo -n ls >/dev/null; then
                msg bold red " [!!!] Attempted to test whether sudo works, but failed. Giving up."
                msg bold red "       Please manually add the line '$env_line' to '$env_file'"
                return 3
            fi
            msg yellow " >> The 'sudo' command appears to work. Attempting to create .env with correct permissions using sudo..."
            sudo -n touch "$env_file"
            sudo -n chown "$(whoami):$(whoami)" "$env_dir" "$env_file"
            sudo -n chmod 700 "$env_file"
            # echo "SHM_DIR=${out_dir}" | sudo -n tee -a "$env_file" > /dev/null
        else
            touch "$env_file"
        fi
        msg green " [+++] Created .env file at: $env_file"
    fi

    if ! [[ -w "$env_file" ]] && ! can_write "$env_file"; then
        msg bold red " [!!!] ERROR: Your user does not have permission to write to '$env_file'"
        if ! sudo -n ls >/dev/null; then
            msg bold red " [!!!] Attempted to test whether sudo works, but failed. Giving up."
            msg bold red "       Please manually add the line '$env_line' to '$env_file'"
            return 3
        fi
        msg yellow " >> The 'sudo' command appears to work. Attempting to correct .env permissions using sudo..."
        sudo -n touch "$env_file"
        sudo -n chown "$(whoami):$(whoami)" "$env_dir" "$env_file"
        sudo -n chmod 700 "$env_file"
        echo "SHM_DIR=${out_dir}" | sudo -n tee -a "$env_file" > /dev/null
    fi

    msg yellow " [...] Inserting '${env_line}' into '$env_file'"
    echo "$env_line" >> "$env_file"
    msg green " [+++] Added '${env_line}' to '${env_file}'"
    return 0
}

# usage: _foldersync-repair [rsync_url] [output_folder]
# If user has existing RocksDB files, rsync must ignore local file timestamps/sizes and verify
# local files against the server using checksums to ensure there's no hidden corruption.
_foldersync-repair() {
    # I = ignore timestamps and size, vv = be more verbose, h = human readable
    # r = recursive, c = compare files using checksumming
    # delete        = remove any local files in out_dir which don't exist on the server
    # partial-dir   = store partially downloaded file chunks in this folder, allowing downloads to be resumed
    rsync -Irvhc --delete --inplace --progress "$1" "$2"
}

# usage: _foldersync-fresh [rsync_url] [output_folder]
# If user doesn't have existing RocksDB files, we can use standard rsync recursive+delete
# We don't need to bother with checksums, nor ignoring local file timestamps.
_foldersync-fresh() {
    # r = recursive, vv = be more verbose, h = human readable
    # delete        = remove any local files in out_dir which don't exist on the server
    # partial-dir   = store partially downloaded file chunks in this folder, allowing downloads to be resumed
    rsync -rvh --delete --inplace --progress "$1" "$2"
}

_dlrocksdb() {
    local url="$ROCKSDB_RSYNC" out_dir="$SHM_DIR" 
    # rdb_folder_existed is changed to 1 if we detect existing RocksDB files
    # used to decide whether we need to ignore timestamps + use rsync checksumming
    local rdb_folder_existed=0

    MSG_TS_DEFAULT=0

    (( $# > 0 )) && url="$1"
    (( $# > 1 )) && out_dir="$2"

    ######
    # If the RocksDB folder doesn't exist, then we create it and we download the RocksDB files from scratch
    # without needing Rsync checksumming + timestamp/size ignoring
    #
    # If it does exist, we check if it's empty. If it's empty, we use the same "fresh" rsync download method.
    #
    # If the folder isn't empty (i.e. at least 1 file), then we have to use the "rsync repair/replace" method,
    # which disables timestamp/size comparisons, and enables additional checksumming to guarantee we don't have
    # any corrupted RocksDB files locally.
    ######
    msg
    if [[ ! -d "$out_dir" ]]; then
        msg yellow " >> Output directory '$out_dir' doesn't exist..."
        msg green  " >> Creating folder + parent folders of '$out_dir' ..."
        mkdir -v -p "$out_dir"
        msg
        msg green " >> As the output folder didn't exist, will download RocksDB using faster method without rsync"
        msg green " >> additional checksumming\n"
    else
        # Get list of files in rocksdb folder using `ls`, then count number of entries to detect if folder is empty
        local rdb_files=($(ls "$out_dir"))
        local total_rdb_files=$((${#rdb_files[@]}))
        if (( total_rdb_files > 0 )); then
            msg green " >> Output directory '$out_dir' already exists."
            msg green " >> To ensure your existing RocksDB files match the remote server exactly, we're going to "
            msg green " >> enable Rsync's checksum feature, as well as ignoring size/timestamps. \n"

            msg red " [!!] This may be **slower** than deleting and re-downloading them from scratch."
            msg red " [!!] "
            msg red " [!!] If your system has a ${BOLD}slow CPU, or slow drives (e.g. spinning HDDs)${RESET}${RED}, we recommend "
            msg red " [!!] deleting your RocksDB files and re-running '$0 fix-blocks rocksdb'"
            msg red " [!!] This will download RocksDB without secondary checksumming:"
            msg
            msg cyan "            sudo rm -rf \"$out_dir\""""
            msg cyan "            $0 fix-blocks rocksdb"""
            msg
            msg yellow " [!!] "
            msg yellow " [!!] If you have a ${BOLD}slow network connection (i.e. below 100mbps)${RESET}${YELLOW}, you don't need to"
            msg yellow " [!!] take any action - just wait while we repair your RocksDB files. "
            msg yellow " [!!] On slow networks, it's best to use this partial repair process, which will attempt to"
            msg yellow " [!!] download only the portions of each file which doesn't match our server."
            msg yellow " [!!] \n"
            rdb_folder_existed=1
        else
            msg green " >> Output directory '$out_dir' already exists."
            msg green " >> Folder appears to be empty. Downloading RocksDB using faster method without rsync"
            msg green " >> additional checksumming\n"
            rdb_folder_existed=0
        fi

    fi

    msg yellow "This may take a while, and may at times appear to be stalled. ${BOLD}Be patient, it may take time (3 to 10 mins) to scan the differences."
    msg yellow "Once it detects the differences, it will download at very high speed depending on how much of your RocksDB files are intact."
    echo -e "\n==============================================================="
    echo -e "${BOLD}Downloading via:${RESET}\t${url}"
    echo -e "${BOLD}Writing to:${RESET}\t\t${out_dir}"
    echo -e "===============================================================\n"

    if (( rdb_folder_existed == 0 )); then
        msg ts bold green " [+] Downloading RocksDB using 'fresh download' method"
        msg ts bold green " [+] This should take no more than a few minutes before it starts to show download progress\n"
        _foldersync-fresh "$url" "$out_dir"
    else
        msg green " [+] Depending on your CPU / Disk speeds, this may take 10+ minutes before it displays any"
        msg green " [+] download progress. Please be patient."
        msg green " [+] If you have a fast network (100mbps+), ${BOLD}consider deleting RocksDB${RESET}${GREEN} and re-running this"
        msg green " [+] command, as explained above in bold yellow text.\n"
        msg ts bold green " [+] Downloading RocksDB using 'repair existing & download new files' method ...\n"

        _foldersync-repair "$url" "$out_dir"
    fi
    # rsync -Irvhc --delete --partial-dir="${DIR}/.rsync-partial" --progress "$url" "${out_dir}"
    ret=$?
    msg
    if (( ret == 0 )); then
        msg ts bold green " (+) FINISHED. RocksDB downloaded via rsync (make sure to check for any errors above)"
    else
        msg ts bold red "An error occurred while downloading RocksDB via rsync... please check above for errors"
    fi
    return $ret

}

# Internal variable used to silence the large "RocksDB Downloader" intro message block
_SILENCE_RDB_INTRO=0
# Set this to 1 in your .env to ignore SHM_DIR containing /dev/shm when using MIRA related functions
# such as dlrocksdb
: ${RDB_IGNORE_SHM=0}

# usage: ./run.sh dlrocksdb (rocksdb_rsync_url) (rocksdb_output)
#
# with no args, equivalent to:
#   ./run.sh dlrocksdb "$ROCKSDB_RSYNC" "$SHM_DIR"
#
# NOTE: if SHM_DIR contains "/dev/shm" - function will recommend changing this to "$DATADIR/rocksdb"
# Disable this by setting "RDB_IGNORE_SHM=1"
#
# example: 
#   ./run.sh dlrocksdb "rsync://files.privex.io/steem/rocksdb/" "/steem/data/rocksdb/"
#
dlrocksdb() {
    local url="$ROCKSDB_RSYNC" out_dir="$SHM_DIR" env_file="${DIR}/.env"
    msg
    if (( _SILENCE_RDB_INTRO == 0 )); then
        msg bold green " ############################################################################################ "
        msg bold green " #                                                                                          # "
        msg bold green " #                                                                                          # "
        msg bold green " #                          Steem-in-a-Box RocksDB Downloader                               # "
        msg bold green " #                                                                                          # "
        msg bold green " #                   (C) 2020 Someguy123 - https://steempeak.com/@someguy123                # "
        msg bold green " #                                                                                          # "
        msg bold green " #                                                                                          # "
        msg bold green " #    SRC: github.com/Someguy123/steem-docker                                               # "
        msg bold green " #                                                                                          # "
        msg bold green " #    Fast and easy download + installation of RocksDB files from Privex Inc.               # "
        msg bold green " #                                                                                          # "
        msg bold green " #    Do you enjoy our convenient block_log and MIRA RocksDB files?                         # "
        msg bold green " #    Support our community services by buying a server from https://www.privex.io/ :)      # "
        msg bold green " #                                                                                          # "
        msg bold green " #                                                                                          # "
        msg bold green " ############################################################################################ "
        msg
    fi
    if (( $# == 1 )); then
        if egrep -q "rsync|@" <<< "$1"; then
            msg yellow " >>> Detected argument 1 as an rsync URI. Using '$1' as ROCKSDB_RSYNC url"
            url="$1"
        else
            msg yellow " >>> Argument 1 does not appear to be an rsync URI. Assuming argument is RocksDB output path: '$1'"
            out_dir="$1"
        fi
    elif (( $# >= 2 )); then
        msg yellow " >>> Using argument 1 as an rsync URI: '$1'"
        msg yellow " >>> Using argument 2 as an RocksDB output path: '$2'"
        url="$1"
        out_dir="$2"
    fi
    msg

    if grep -q "/dev/shm" <<< "$out_dir"; then
        msg bold red "WARNING: The RocksDB output directory appears to be, or is within /dev/shm - Output directory is currently: $out_dir"
        msg green "We strongly recommend that you store RocksDB on your disk, rather than inside of /dev/shm"

        if (( RDB_IGNORE_SHM == 0 )) && yesno "${BOLD}${YELLOW}Do you want us to store RocksDB inside of '${DATADIR}/rocksdb/' instead?${RESET} (Y/n) > " defyes; then
            out_dir="${DATADIR}/rocksdb/"
            msg green " >> We'll download RocksDB into '$out_dir' this time."
            msg green " >> For the Steem daemon to correctly use the RocksDB files, you'll need to correct SHM_DIR inside of your '.env' file."
            if yesno "${BOLD}${YELLOW}Do you want us to automatically create/update your .env file with 'SHM_DIR=$out_dir' ? ${RESET} (Y/n) > " defyes; then
                insert_env "SHM_DIR=${out_dir}"
                if (( $? != 0 )); then
                    msg bold red " [!!!] Error returned by insert_env function. Read above."
                    return 1
                fi
            else
                msg yellow " >> Not modifying .env file"
            fi
        else
            msg yellow " >> Not modifying RocksDB output directory"
            msg yellow " >> Will output RocksDB to original directory: $out_dir"
        fi
    fi
    msg


    _dlrocksdb "$url" "$out_dir"

}


# Returns the size (in bytes) of a file on a HTTP(S) server
#
# usage:
#
#     $ s=$(remote-file-size "http://files.privex.io/steem/block_log")
#     $ echo $s
#     270743893301
#
# original source: https://stackoverflow.com/a/4497786
#
remote-file-size() {
    local url="$1"

    curl -sI "$url" | grep -i "content-length" | awk '{print $2}'
}

custom-dlblocks() {
    local compress="no" # to be overriden if we have 2+ args
    local dlvia="$1"
    local url;

    if (( $# > 1 )); then
        url="$2"
    else
        if [[ "$dlvia" == "rsync" ]]; then url="$BC_RSYNC"; else url="$BC_HTTP"; fi
        compress="$BC_HTTP_CMP"
    fi
    (( $# >= 3 )) && compress="$3"

    case "$dlvia" in
        rsync)
            dl-blocks-rsync "$url"
            return $?
            ;;
        rsync-replace)
            msg yellow " -> Removing old block_log..."
            sudo rm -vf "$BC_FOLDER/block_log"
            dl-blocks-rsync "$url"
            return $?
            ;;
        http)
            dl-blocks-http "$url" "$compress"
            return $? 
            ;;
        http-replace)
            msg yellow " -> Removing old block_log..."
            sudo rm -vf "$BC_FOLDER/block_log"
            dl-blocks-http "$url" "$compress"
            return $?
            ;;
        *)
            msg red "Invalid download method"
            msg red "Valid options are http, http-replace, rsync, or rsync-replace"
            return 1
            ;;
    esac 
}

# Internal use
# Usage: dl-blocks-rsync blocklog_url
dl-blocks-rsync() {
    local url="$1" ret
    msg "This may take a while, and may at times appear to be stalled. ${YELLOW}${BOLD}Be patient, it takes time (3 to 10 mins) to scan the differences."
    msg "Once it detects the differences, it will download at very high speed depending on how much of your block_log is intact."
    echo -e "\n==============================================================="
    echo -e "${BOLD}Downloading via:${RESET}\t${url}"
    echo -e "${BOLD}Writing to:${RESET}\t\t${BC_FOLDER}/block_log"
    echo -e "===============================================================\n"
    # I = ignore timestamps and size, vv = be more verbose, h = human readable
    # append-verify = attempt to append to the file, but make sure to verify the existing pieces match the server
    rsync -Ivvh --append-verify --progress "$url" "${BC_FOLDER}/block_log"
    ret=$?
    if (( ret != 0 )); then
        msg bold red "An error occurred while downloading the blockchain via rsync... please check above for errors"
        return $ret
    fi
    
    msg bold green " (+) FINISHED. Blockchain downloaded via rsync (make sure to check for any errors above)"

    msg green " [+] Downloading block_log.index from ${url}.index"
    rsync -Ivhc --append-verify --progress "${url}.index" "${BC_FOLDER}/block_log.index"

    ret=$?
    if (( ret != 0 )); then
        msg bold red "An error occurred while downloading the block index via rsync... please check above for errors"
        return $ret
    fi
    msg bold green " (+) FINISHED. Block index downloaded via rsync (make sure to check for any errors above)"
    return $ret
}

# Internal use
# Usage: dl-blocks-http blocklog_url [compress_type]
dl-blocks-http() {
    local url="$1" ret compression="no"

    (( $# < 1 )) && msg bold red "ERROR: no url specified for dl-blocks-http" && return 1
    if (( $# == 2 )); then
        compression="$2"
        if [[ "$2" != "lz4" && "$2" != "xz" && "$2" != "no" ]]; then
            echo "${RED}ERROR: Unknown compression type '$2' passed to dl-blocks-http.${RESET}"
            echo "Please correct your http compression type."
            echo "Choices: lz4, xz, no (for uncompressed)"
            return 1
        fi
    fi
    echo -e "\n==============================================================="
    echo -e "${BOLD}Downloading via:${RESET}\t${url}"
    echo -e "${BOLD}Writing to:${RESET}\t\t${BC_FOLDER}/block_log"
    [[ "$compression" != "no" ]] && \
        echo -e "${BOLD}Compression:${RESET}\t\t$compression"
    echo -e "===============================================================\n"

    if [[ "$compression" != "no" ]]; then 
        msg bold green " -> Downloading and de-compressing block log on-the-fly..."
    else
        msg bold green " -> Downloading raw block log..."
    fi

    case "$compression" in 
        lz4)
            wget "$url" -O - | lz4 -dv - "$BC_FOLDER/block_log"
            ;;
        xz)
            wget "$url" -O - | xz -dvv - "$BC_FOLDER/block_log"
            ;;
        no)
            wget -c "$url" -O "$BC_FOLDER/block_log"
            ;;
    esac
    ret=$?
    if (( ret != 0 )); then
        msg bold red "An error occurred while downloading the block index via HTTP... please check above for errors"
        return $ret
    fi
    msg bold green " (+) FINISHED. Blockchain downloaded and decompressed (make sure to check for any errors above)"

    msg bold green " [+] Downloading block_log.index from ${BC_HTTP_RAW}.index"
    wget -c "${BC_HTTP_RAW}.index" -O "${BC_FOLDER}/block_log.index"
    
    ret=$?
    if (( ret != 0 )); then
        msg bold red "An error occurred while downloading the block index via HTTP... please check above for errors"
        return $ret
    fi
    return $ret
}

# Usage: ./run.sh install_docker
# Downloads and installs the latest version of Docker using the Get Docker site
# If Docker is already installed, it should update it.
install_docker() {
    sudo apt update
    # curl/git used by docker, xz/lz4 used by dlblocks, jq used by tslogs/pclogs
    sudo apt install curl git xz-utils liblz4-tool jq
    curl https://get.docker.com | sh
    if [ "$EUID" -ne 0 ]; then 
        echo "Adding user $(whoami) to docker group"
        sudo usermod -aG docker $(whoami)
        echo "IMPORTANT: Please re-login (or close and re-connect SSH) for docker to function correctly"
    fi
}

# Usage: ./run.sh install [tag]
# Downloads the Steem low memory node image from someguy123's official builds, or a custom tag if supplied
#
#   tag - optionally specify a docker tag to install from. can be third party
#         format: user/repo:version    or   user/repo   (uses the 'latest' tag)
#
# If no tag specified, it will download the pre-set $DK_TAG in run.sh or .env
# Default tag is normally someguy123/steem:latest (official builds by the creator of steem-docker).
#
install() {
    if (( $# == 1 )); then
        DK_TAG=$1
        # If neither '/' nor ':' are present in the tag, then for convenience, assume that the user wants
        # someguy123/steem with this specific tag.
        if grep -qv ':' <<< "$1"; then
            if grep -qv '/' <<< "$1"; then
                msg bold red "WARNING: Neither / nor : were present in your tag '$1'"
                DK_TAG="someguy123/steem:$1"
                msg red "We're assuming you've entered a version, and will try to install @someguy123's image: '${DK_TAG}'"
                msg yellow "If you *really* specifically want '$1' from Docker hub, set DK_TAG='$1' inside of .env and run './run.sh install'"
            fi
        fi
    fi
    msg bold red "NOTE: You are installing image $DK_TAG. Please make sure this is correct."
    sleep 2
    msg yellow " -> Loading image from ${DK_TAG}"
    docker pull "$DK_TAG"
    msg green " -> Tagging as ${DOCKER_IMAGE}"
    docker tag "$DK_TAG" "${DOCKER_IMAGE}"
    msg bold green " -> Installation completed. You may now configure or run the server"
}

# Usage: ./run.sh install_full
# Downloads the Steem full node image from the pre-set $DK_TAG_FULL in run.sh or .env
# Default tag is normally someguy123/steem:latest-full (official builds by the creator of steem-docker).
#
install_full() {
    msg yellow " -> Loading image from ${DK_TAG_FULL}"
    docker pull "$DK_TAG_FULL" 
    msg green " -> Tagging as steem"
    docker tag "$DK_TAG_FULL" steem
    msg bold green " -> Installation completed. You may now configure or run the server"
}

# Internal Use Only
# Checks if the container $DOCKER_NAME exists. Returns 0 if it does, -1 if not.
# Usage:
# if seed_exists; then echo "true"; else "false"; fi
#
seed_exists() {
    seedcount=$(docker ps -a -f name="^/"$DOCKER_NAME"$" | wc -l)
    if [[ $seedcount -eq 2 ]]; then
        return 0
    else
        return -1
    fi
}

# Internal Use Only
# Checks if the container $DOCKER_NAME is running. Returns 0 if it's running, -1 if not.
# Usage:
# if seed_running; then echo "true"; else "false"; fi
#
seed_running() {
    seedcount=$(docker ps -f 'status=running' -f name=$DOCKER_NAME | wc -l)
    if [[ $seedcount -eq 2 ]]; then
        return 0
    else
        return -1
    fi
}

# Usage: ./run.sh start
# Creates and/or starts the Steem docker container
start() {
    msg bold green " -> Starting container '${DOCKER_NAME}'..."
    seed_exists
    if [[ $? == 0 ]]; then
        docker start $DOCKER_NAME
    else
        if (( $# > 0 )); then
            msg green "Appending extra arguments: $*"
            docker run ${DPORTS[@]} -v "$SHM_DIR":/shm -v "$DATADIR":/steem -d --name $DOCKER_NAME -t "$DOCKER_IMAGE" steemd --data-dir=/steem/witness_node_data_dir "$@"
        else
            docker run ${DPORTS[@]} -v "$SHM_DIR":/shm -v "$DATADIR":/steem -d --name $DOCKER_NAME -t "$DOCKER_IMAGE" steemd --data-dir=/steem/witness_node_data_dir
        fi
    fi
}

# Usage: ./run.sh replay
# Replays the blockchain for the Steem docker container
# If steem is already running, it will ask you if you still want to replay
# so that it can stop and remove the old container
#
replay() {
    seed_running
    if [[ $? == 0 ]]; then
        echo $RED"WARNING: Your Steem server ($DOCKER_NAME) is currently running"$RESET
        echo
        docker ps
        echo
        read -p "Do you want to stop the container and replay? (y/n) > " shouldstop
        if [[ "$shouldstop" == "y" ]]; then
            stop
        else
            echo $GREEN"Did not say 'y'. Quitting."$RESET
            return
        fi
    fi 
    msg yellow " -> Removing old container '${DOCKER_NAME}'"
    docker rm $DOCKER_NAME
    if (( $# > 0 )); then
        msg green " -> Running steem (image: ${DOCKER_IMAGE}) with replay in container '${DOCKER_NAME}' - extra args: '$*'..."
        docker run ${DPORTS[@]} -v "$SHM_DIR":/shm -v "$DATADIR":/steem -d --name $DOCKER_NAME -t "$DOCKER_IMAGE" steemd --data-dir=/steem/witness_node_data_dir --replay "$@"
    else
        msg green " -> Running steem (image: ${DOCKER_IMAGE}) with replay in container '${DOCKER_NAME}'..."
        docker run ${DPORTS[@]} -v "$SHM_DIR":/shm -v "$DATADIR":/steem -d --name $DOCKER_NAME -t "$DOCKER_IMAGE" steemd --data-dir=/steem/witness_node_data_dir --replay
    fi
    msg bold green " -> Started."
}

# For MIRA, replay with --memory-replay
memory_replay() {
    seed_running
    if [[ $? == 0 ]]; then
        echo $RED"WARNING: Your Steem server ($DOCKER_NAME) is currently running"$RESET
	echo
        docker ps
	echo
	read -p "Do you want to stop the container and replay? (y/n) > " shouldstop
    if [[ "$shouldstop" == "y" ]]; then
		stop
	else
		echo $GREEN"Did not say 'y'. Quitting."$RESET
		return
	fi
    fi 
    echo "Removing old container"
    docker rm $DOCKER_NAME
    echo "Running steem with --memory-replay..."
    docker run ${DPORTS[@]} -v "$SHM_DIR":/shm -v "$DATADIR":/steem -d --name $DOCKER_NAME -t "$DOCKER_IMAGE" steemd --data-dir=/steem/witness_node_data_dir --replay --memory-replay
    echo "Started."
}

# Usage: ./run.sh shm_size size
# Resizes the ramdisk used for storing Steem's shared_memory at /dev/shm
# Size should be specified with G (gigabytes), e.g. ./run.sh shm_size 64G
#
shm_size() {
    if (( $# != 1 )); then
        msg red "Please specify a size, such as ./run.sh shm_size 64G"
    fi
    msg green " -> Setting /dev/shm to $1"
    sudo mount -o remount,size=$1 /dev/shm
    if [[ $? -eq 0 ]]; then
        msg bold green "Successfully resized /dev/shm"
    else
        msg bold red "An error occurred while resizing /dev/shm..."
        msg red "Make sure to specify size correctly, e.g. 64G. You can also try using sudo to run this."
    fi
}

# Usage: ./run.sh stop
# Stops the Steem container, and removes the container to avoid any leftover
# configuration, e.g. replay command line options
#
stop() {
    msg "If you don't care about a clean stop, you can force stop the container with ${BOLD}./run.sh kill"
    msg red "Stopping container '${DOCKER_NAME}' (allowing up to ${STOP_TIME} seconds before killing)..."
    docker stop -t ${STOP_TIME} $DOCKER_NAME
    msg red "Removing old container '${DOCKER_NAME}'..."
    docker rm $DOCKER_NAME
}

sbkill() {
    msg bold red "Killing container '${DOCKER_NAME}'..."
    docker kill "$DOCKER_NAME"
    msg red "Removing container ${DOCKER_NAME}"
    docker rm "$DOCKER_NAME"
}

# Usage: ./run.sh enter
# Enters the running docker container and opens a bash shell for debugging
#
enter() {
    docker exec -it $DOCKER_NAME bash
}

# Usage: ./run.sh shell
# Runs the container similar to `run` with mounted directories, 
# then opens a BASH shell for debugging
# To avoid leftover containers, it uses `--rm` to remove the container once you exit.
#
shell() {
    docker run ${DPORTS[@]} -v "$SHM_DIR":/shm -v "$DATADIR":/steem --rm -it "$DOCKER_IMAGE" bash
}


# Usage: ./run.sh wallet
# Opens cli_wallet inside of the running Steem container and
# connects to the local steemd over websockets on port 8090
#
wallet() {
    docker exec -it $DOCKER_NAME cli_wallet -s ws://127.0.0.1:8090
}

# Usage: ./run.sh remote_wallet [wss_server]
# Connects to a remote websocket server for wallet connection. This is completely safe
# as your wallet/private keys are never sent to the remote server.
#
# By default, it will connect to wss://steemd.privex.io:443 (ws = normal websockets, wss = secure HTTPS websockets)
# See this link for a list of WSS nodes: https://www.steem.center/index.php?title=Public_Websocket_Servers
# 
#    wss_server - a custom websocket server to connect to, e.g. ./run.sh remote_wallet wss://rpc.steemviz.com
#
remote_wallet() {
    if (( $# == 1 )); then
        REMOTE_WS=$1
    fi
    docker run -v "$DATADIR":/steem --rm -it "$DOCKER_IMAGE" cli_wallet -s "$REMOTE_WS"
}

# Usage: ./run.sh logs
# Shows the last 30 log lines of the running steem container, and follows the log until you press ctrl-c
#
logs() {
    msg blue "DOCKER LOGS: (press ctrl-c to exit) "
    docker logs -f --tail=30 $DOCKER_NAME
    #echo $RED"INFO AND DEBUG LOGS: "$RESET
    #tail -n 30 $DATADIR/{info.log,debug.log}
}

# Usage: ./run.sh pclogs
# (warning: may require root to work properly in some cases)
# Used to watch % replayed during blockchain replaying.
# Scans and follows a large portion of your steem logs then filters to only include the replay percentage
#   example:    2018-12-08T23:47:16    22.2312%   6300000 of 28338603   (60052M free)
#
pclogs() {
    if [[ ! $(command -v jq) ]]; then
        msg red "jq not found. Attempting to install..."
        sleep 3
        sudo apt-get update -y > /dev/null
        sudo apt-get install -y jq > /dev/null
    fi
    local LOG_PATH=$(docker inspect $DOCKER_NAME | jq -r .[0].LogPath)
    local pipe=/tmp/dkpipepc.fifo
    trap "rm -f $pipe" EXIT
    if [[ ! -p $pipe ]]; then
        mkfifo $pipe
    fi
    # the sleep is a dirty hack to keep the pipe open

    sleep 1000000 < $pipe &
    tail -n 5000 -f "$LOG_PATH" &> $pipe &
    while true
    do
        if read -r line <$pipe; then
            # first grep the data for "objects cached" to avoid
            # needlessly processing the data
            L=$(egrep --colour=never "objects cached|M free" <<< "$line")
            if [[ $? -ne 0 ]]; then
                continue
            fi
            # then, parse the line and print the time + log
            L=$(jq -r ".time +\" \" + .log" <<< "$L")
            # then, remove excessive \r's causing multiple line breaks
            L=$(sed -e "s/\r//" <<< "$L")
            # now remove the decimal time to make the logs cleaner
            L=$(sed -e 's/\..*Z//' <<< "$L")
            # and finally, strip off any duplicate new line characters
            L=$(tr -s "\n" <<< "$L")
            printf '%s\r\n' "$L"
        fi
    done
}

# Original grep/sed snippet made by @drakos
clean-logs() {
    msgerr cyan "Monitoring and cleaning replay logs for ${DOCKER_NAME}"

    docker logs --tail=5000000 -f -t "$DOCKER_NAME" | \
        grep -E '[0-9]{2}%.*M free|[0-9]{2}%.*objects cached|Performance report at block|Done reindexing|Migrating state to disk|Converting index.*to mira type' | \
        sed -e "s/\r\x1B\[0m//g"
}

# Usage: ./run.sh tslogs
# (warning: may require root to work properly in some cases)
# Shows the Steem logs, but with UTC timestamps extracted from the docker logs.
# Scans and follows a large portion of your steem logs, filters out useless data, and appends a 
# human readable timestamp on the left. Time is normally in UTC, not your local. Example:
#
#   2018-12-09T01:04:59 p2p_plugin.cpp:212            handle_block         ] Got 21 transactions 
#                   on block 28398481 by someguy123 -- Block Time Offset: -345 ms
#
tslogs() {
    if [[ ! $(command -v jq) ]]; then
        msg red "jq not found. Attempting to install..."
        sleep 3
        sudo apt update
        sudo apt install -y jq
    fi
    local LOG_PATH=$(docker inspect $DOCKER_NAME | jq -r .[0].LogPath)
    local pipe=/tmp/dkpipe.fifo
    trap "rm -f $pipe" EXIT
    if [[ ! -p $pipe ]]; then
        mkfifo $pipe
    fi
    # the sleep is a dirty hack to keep the pipe open

    sleep 10000 < $pipe &
    tail -n 100 -f "$LOG_PATH" &> $pipe &
    while true
    do
        if read -r line <$pipe; then
            # first, parse the line and print the time + log
            L=$(jq -r ".time +\" \" + .log" <<<"$line")
            # then, remove excessive \r's causing multiple line breaks
            L=$(sed -e "s/\r//" <<< "$L")
            # now remove the decimal time to make the logs cleaner
            L=$(sed -e 's/\..*Z//' <<< "$L")
            # remove the steem ms time because most people don't care
            L=$(sed -e 's/[0-9]\+ms //' <<< "$L")
            # and finally, strip off any duplicate new line characters
            L=$(tr -s "\n" <<< "$L")
            printf '%s\r\n' "$L"
        fi
    done
}

# Internal use only
# Used by `ver` to pretty print new commits on origin/master
simplecommitlog() {
    local commit_format;
    local args;
    commit_format=""
    commit_format+="    - Commit %Cgreen%h%Creset - %s %n"
    commit_format+="      Author: %Cblue%an%Creset %n"
    commit_format+="      Date/Time: %Cblue%ai%Creset%n"
    if [[ "$#" -lt 1 ]]; then
        echo "Usage: simplecommitlog branch [num_commits]"
        echo "invalid use of simplecommitlog. exiting"
        exit -1
    fi
    branch="$1"
    args="$branch"
    if [[ "$#" -eq 2 ]]; then
        count="$2"
        args="-n $count $args"
    fi
    git --no-pager log --pretty=format:"$commit_format" $args
}


# Usage: ./run.sh ver
# Displays information about your Steem-in-a-box version, including the docker container
# as well as the scripts such as run.sh. Checks for updates using git and DockerHub API.
#
ver() {
    LINE="==========================="
    ####
    # Update git, so we can detect if we're outdated or not
    # Also get the branch to warn people if they're not on master
    ####
    git remote update >/dev/null
    current_branch=$(git branch | grep \* | cut -d ' ' -f2)
    git_update=$(git status -uno)


    ####
    # Print out the current branch, commit and check upstream 
    # to return commits that can be pulled
    ####
    echo "${BLUE}Current Steem-in-a-box version:${RESET}"
    echo "    Branch: $current_branch"
    if [[ "$current_branch" != "master" ]]; then
        echo "${RED}WARNING: You're not on the master branch. This may prevent you from updating${RESET}"
        echo "${GREEN}Fix: Run 'git checkout master' to change to the master branch${RESET}"
    fi
    # Warn user of modified core files
    git_status=$(git status -s)
    modified=0
    while IFS='' read -r line || [[ -n "$line" ]]; do
        if grep -q " M " <<< $line; then
            modified=1
        fi
    done <<< "$git_status"
    if [[ "$modified" -ne 0 ]]; then
        echo "    ${RED}ERROR: Your steem-in-a-box core files have been modified (see 'git status'). You will not be able to update."
        echo "    Fix: Run 'git reset --hard' to reset all core files back to their originals before updating."
        echo "    This will not affect your running witness, or files such as config.ini which are supposed to be edited by the user${RESET}"
    fi
    echo "    ${BLUE}Current Commit:${RESET}"
    simplecommitlog "$current_branch" 1
    echo
    echo
    # Check for updates and let user know what's new
    if grep -Eiq "up.to.date" <<< "$git_update"; then
        echo "    ${GREEN}Your steem-in-a-box core files (run.sh, Dockerfile etc.) up to date${RESET}"
    else
        echo "    ${RED}Your steem-in-a-box core files (run.sh, Dockerfile etc.) are outdated!${RESET}"
        echo
        echo "    ${BLUE}Updates in the current published version of Steem-in-a-box:${RESET}"
        simplecommitlog "HEAD..origin/master"
        echo
        echo
        echo "    Fix: ${YELLOW}Please run 'git pull' to update your steem-in-a-box. This should not affect any running containers.${RESET}"
    fi
    echo $LINE

    ####
    # Show the currently installed image information
    ####
    echo "${BLUE}Steem image installed:${RESET}"
    # Pretty printed docker image ID + creation date
    dkimg_output=$(docker images -f "reference=steem:latest" --format "Tag: {{.Repository}}, Image ID: {{.ID}}, Created At: {{.CreatedSince}}")
    # Just the image ID
    dkimg_id=$(docker images -f "reference=steem:latest" --format "{{.ID}}")
    # Used later on, for commands that depend on the image existing
    got_dkimg=0
    if [[ $(wc -c <<< "$dkimg_output") -lt 10 ]]; then
        echo "${RED}WARNING: We could not find the currently installed image (${DOCKER_IMAGE})${RESET}"
        echo "${RED}Make sure it's installed with './run.sh install' or './run.sh build'${RESET}"
    else
        echo "    $dkimg_output"
        got_dkimg=1
        echo "${BLUE}Checking for updates...${RESET}"
        remote_docker_id="$(get_latest_id)"
        if [[ "$?" == 0 ]]; then
            remote_docker_id="${remote_docker_id:7:12}"
            if [[ "$remote_docker_id" != "$dkimg_id" ]]; then
                echo "    ${YELLOW}An update is available for your Steem installation"
                echo "    Your image ID: $dkimg_id    Image ID on Docker Hub: ${remote_docker_id}"
                echo "    NOTE: If you have built manually with './run.sh build', your image will not match docker hub."
                echo "    To update, use ./run.sh install - a replay may or may not be required (ask in #witness on steem.chat)${RESET}"
            else
                echo "${GREEN}Your installed docker image ($dkimg_id) matches Docker Hub ($remote_docker_id)"
                echo "You're running the latest version of Steem from @someguy123's builds${RESET}"
            fi
        else
            echo "    ${YELLOW}An error occurred while checking for updates${RESET}"
        fi

    fi

    echo $LINE

    msg green "Build information for currently installed Steem image '${DOCKER_IMAGE}':"

    docker run --rm -it "${DOCKER_IMAGE}" cat /steem_build.txt

    echo "${BLUE}Steem version currently running:${RESET}"
    # Verify that the container exists, even if it's stopped
    if seed_exists; then
        _container_image_id=$(docker inspect "$DOCKER_NAME" -f '{{.Image}}')
        # Truncate the long SHA256 sum to the standard 12 character image ID
        container_image_id="${_container_image_id:7:12}"
        echo "    Container $DOCKER_NAME is running on docker image ID ${container_image_id}"
        # If the docker image check was successful earlier, then compare the image to the current container 
        if [[ "$got_dkimg" == 1 ]]; then
            if [[ "$container_image_id" == "$dkimg_id" ]]; then
                echo "    ${GREEN}Container $DOCKER_NAME is running image $container_image_id, which matches steem:latest ($dkimg_id)"
                echo "    Your container will not change Steem version on restart${RESET}"
            else
                echo "    ${YELLOW}Warning: Container $DOCKER_NAME is running image $container_image_id, which DOES NOT MATCH steem:latest ($dkimg_id)"
                echo "    Your container may change Steem version on restart${RESET}"
            fi
        else
            echo "    ${YELLOW}Could not get installed image earlier. Skipping image/container comparison.${RESET}"
        fi
        echo "    ...scanning logs to discover blockchain version - this may take 30 seconds or more"
        l=$(docker logs "$DOCKER_NAME")
        if grep -q "blockchain version" <<< "$l"; then
            echo "  " $(grep "blockchain version" <<< "$l")
        else
            echo "    ${RED}Could not identify blockchain version. Not found in logs for '$DOCKER_NAME'${RESET}"
        fi
    else
        echo "    ${RED}Unfortunately your Steem container doesn't exist (start it with ./run.sh start or replay)..."
        echo "    We can't identify your blockchain version unless the container has been started at least once${RESET}"
    fi

}

# Usage: ./run.sh start
# Very simple status display, letting you know if the container exists, and if it's running.
status() {
    
    if seed_exists; then
        echo "Container exists?: "$GREEN"YES"$RESET
    else
        echo "Container exists?: "$RED"NO (!)"$RESET 
        echo "Container doesn't exist, thus it is NOT running. Run '$0 install && $0 start'"$RESET
        return
    fi

    if seed_running; then
        echo "Container running?: "$GREEN"YES"$RESET
    else
        echo "Container running?: "$RED"NO (!)"$RESET
        echo "Container isn't running. Start it with '$0 start' or '$0 replay'"$RESET
        return
    fi

}

rpc-global-props() {
    if (( $# < 1 )); then
        local ct_ip=$(get_container_ip "$DOCKER_NAME")
        local rpc_url="http://${ct_ip}:${STEEM_RPC_PORT}"
    else
        local rpc_url="$1"
    fi
    # local rpc_url="https://steemd.privex.io/"

    curl -fsSL --data '{"jsonrpc": "2.0", "method": "condenser_api.get_dynamic_global_properties", "params": [], "id": 1}' "$rpc_url"
}

_LN="======================================================================\n"

: ${MONITOR_INTERVAL=10}

MONITOR_INTERVAL=$((MONITOR_INTERVAL))

siab-monitor() {
    local props head_block block_time seconds_behind time_behind
    local blocks_synced=0 started_at="$(rfc_datetime)" starting_block=0
    local time_since_start mins_since_start bps=0 bpm=0
    local remote_props remote_head_block blocks_behind mins_remaining
    error_control 0
    msg
    msg nots bold green "--- Steem-in-a-box Sync Monitor --- \n"
    msg nots bold green "Monitoring your local steemd instance\n"
    msg nots bold green "Block data will update every 10 seconds, showing the block number that your node is synced up to"
    msg nots bold green "the date/time that block was produced, and how far behind in days/hours/minutes that block is.\n"
    msg nots bold green "After the first check, we'll also output how many blocks have been synced so far, as well as"
    msg nots bold green "the estimated blocks per second (BPS) that your node is syncing by.\n"
    msg nots bold yellow "NOTE: This will not work with a replaying node. Only with a node which is synchronising.\n"
    
    msg nots "$_LN"


    while true; do
        error_control 1
        props=$(rpc-global-props)
        ret=$?
        if (( ret != 0 )); then
            msg bold red "Error while obtaining Local RPC global props. Will try again soon..."
            msg nots "$_LN"
            sleep "$MONITOR_INTERVAL"
            continue
        fi
        head_block=$(echo "$props" | jq -r '.result.head_block_number')
        block_time=$(echo "$props" | jq -r '.result.time')
        if [ -z "$head_block" ] || [ -z "$block_time" ] || [[ "$head_block" == "null" ]] || [[ "$block_time" == "null" ]]; then
            msg bold red "Local RPC head block / block time was empty. Will try again soon..."
            msg nots "$_LN"
            sleep "$MONITOR_INTERVAL"
            continue
        fi

        current_timestamp=$(rfc_datetime)
        error_control 2
        seconds_behind=$(compare_dates "$current_timestamp" "$block_time")
        if (( ret != 0 )); then
            msg bold red "Local RPC timestamp was invalid (err: compare_dates). Will try again soon..."
            msg nots "$_LN"; sleep "$MONITOR_INTERVAL"; continue
        fi
        time_behind="$(human_seconds "${seconds_behind}")"
        if (( ret != 0 )); then
            msg bold red "Local RPC timestamp was invalid (err: human_seconds). Will try again soon..."
            msg nots "$_LN"; sleep "$MONITOR_INTERVAL"; continue
        fi
        error_control 0

        msg green "Current block:             ${head_block}"
        msg green "Block time:                ${block_time}"
        msg green "Time behind head block:    ${time_behind}"
        msg

        (( starting_block == 0 )) && starting_block="$head_block"

        blocks_synced=$((head_block - starting_block))

        if (( blocks_synced > 0 )); then
            msg green "New blocks since start:      $blocks_synced"
            time_since_start=$(compare_dates "$(rfc_datetime)" "$started_at")
            bps=$((blocks_synced/time_since_start))
            mins_since_start=$((time_since_start / 60))
            msg green "Blocks per second:           $bps"

            error_control 1
            remote_props=$(rpc-global-props "$REMOTE_RPC")
            ret=$?
            if (( ret == 0 )); then
                remote_head_block=$(echo "$remote_props" | jq -r '.result.head_block_number')
                if [ -z "$remote_head_block" ]; then
                    msg bold red "Remote RPC head block / block time was empty. Will try again soon..."
                    msg nots "$_LN"
                    sleep "$MONITOR_INTERVAL"
                    continue
                fi
                msg green "Latest network block:        $remote_head_block (from RPC $REMOTE_RPC)"

                blocks_behind=$(( remote_head_block - head_block ))
                mins_remaining=$(( (blocks_behind / bps) / 60 ))
                msg green "Blocks behind:               $blocks_behind"
                msg green "ETA til Synced:              $mins_remaining minutes"
                if (( mins_since_start > 0 )); then
                    bpm=$(( blocks_synced / (time_since_start / 60) ))
                    msg green "Blocks per minute:           $bpm"
                fi
            else
                msg bold red "Error while obtaining Remote RPC global props. Will try again soon..."
                msg nots "$_LN"
                sleep "$MONITOR_INTERVAL"
                continue
            fi
            
            msg
        fi
        msg nots "$_LN"
        sleep "$MONITOR_INTERVAL"
    done
}

# Usage: ./run.sh clean [blocks|shm|all]
# Removes blockchain, p2p, and/or shared memory folder contents, with interactive prompts.
#
# To skip the "are you sure" prompt, specify either:
#     'blocks' (clear blockchain+p2p)
#     'shm' (SHM_DIR, usually /dev/shm)
#     'all' (clear both of the above)
#
# Example (delete blockchain+p2p folder contents without asking first):
#     ./run.sh clean blocks
#
sb_clean() {
    bc_dir="${DATADIR}/witness_node_data_dir/blockchain"
    p2p_dir="${DATADIR}/witness_node_data_dir/p2p"
    
    # To prevent the risk of glob problems due to non-existant folders,
    # we re-create them silently before we touch them.
    mkdir -p "$bc_dir" "$p2p_dir" "$SHM_DIR" &> /dev/null

    msg yellow " :: Blockchain:           $bc_dir"
    msg yellow " :: P2P files:            $p2p_dir"
    msg yellow " :: Shared Mem / Rocksdb: $SHM_DIR"
    msg
    
    if (( $# == 1 )); then
        case $1 in
            sh*)
                msg bold red " !!! Clearing all files in SHM_DIR ( $SHM_DIR )"
                rm -rfv "$SHM_DIR"/*
                mkdir -p "$SHM_DIR" &> /dev/null
                msg bold green " +++ Cleared shared files directory."
                ;;
            bloc*)
                msg bold red " !!! Clearing all files in $bc_dir and $p2p_dir"
                rm -rfv "$bc_dir"/*
                rm -rfv "$p2p_dir"/*
                mkdir -p "$bc_dir" "$p2p_dir" &> /dev/null
                msg bold green " +++ Cleared blockchain files + p2p"
                ;;
            all)
                msg bold red " !!! Clearing blockchain, p2p, and shared memory files..."
                rm -rfv "$SHM_DIR"/*
                rm -rfv "$bc_dir"/*
                rm -rfv "$p2p_dir"/*
                mkdir -p "$bc_dir" "$p2p_dir" "$SHM_DIR" &> /dev/null
                msg bold green " +++ Cleared blockchain + p2p + shared memory"
                ;;
            *)
                msg bold red " !!! Invalid option. Either run './run.sh clean' for interactive mode, "
                msg bold red " !!!   or for automatic mode specify 'blocks' (blockchain + p2p), "
                msg bold red " !!!   'shm' (shared memory/rocksdb) or 'all' (both blocks and shm)"
                return 1
                ;;
        esac
        return
    fi

    msg green " (+) To skip these prompts, you can run './run.sh clean' with 'blocks', 'shm', or 'all'"
    msg green " (?) 'blocks' = blockchain + p2p folder, 'shm' = shared memory folder, 'all' = blocks + shm"
    msg green " (?) Example: './run.sh clean blocks' will clear blockchain + p2p without any warnings."

    read -p "Do you want to remove the blockchain files? (y/n) > " cleanblocks
    if [[ "$cleanblocks" == "y" ]]; then
        msg bold red " !!! Clearing blockchain files..."
        rm -rvf "$bc_dir"/*
        mkdir -p "$bc_dir" &> /dev/null
        msg bold green " +++ Cleared blockchain files"
    else
        msg yellow " >> Not clearing blockchain folder."
    fi
    
    read -p "Do you want to remove the p2p files? (y/n) > " cleanp2p
    if [[ "$cleanp2p" == "y" ]]; then
        msg bold red " !!! Clearing p2p files..."
        rm -rvf "$p2p_dir"/*
        mkdir -p "$p2p_dir" &> /dev/null
        msg bold green " +++ Cleared p2p files"
    else
        msg yellow " >> Not clearing p2p folder."
    fi
    
    read -p "Do you want to remove the shared memory / rocksdb files? (y/n) > " cleanshm
    if [[ "$cleanshm" == "y" ]]; then
        msg bold red " !!! Clearing shared memory files..."
        rm -rvf "$SHM_DIR"/*
        mkdir -p "$SHM_DIR" &> /dev/null
        msg bold green " +++ Cleared shared memory files"
    else
        msg yellow " >> Not clearing shared memory folder."
    fi

    msg bold green " ++ Done."
}

# For use by @someguy123 for generating binary images
# ./run.sh publish [mira|nomira] [version] (extratag def: latest)
# e.g. ./run.sh publish mira v0.22.1
# e.g. ./run.sh publish nomira some-branch-fix v0.22.1-fixed
#
# disable extra tag:
# e.g. ./run.sh publish nomira some-branch-fix n/a
#
publish() {
    if (( $# < 2 )); then
        msg green "Usage: $0 publish [mira|nomira] [version] (extratag def: latest)"
        msg yellow "Environment vars:\n\tMAIN_TAG - Override the primary tag (default: someguy123/steem:\$V)\n"
        return 1
    fi
    MKMIRA="$1"
    BUILD_OPTS=()
    case "$MKMIRA" in
        mira)
            BUILD_OPTS+=("ENABLE_MIRA=ON")
            ;;
        nomira)
            BUILD_OPTS+=("ENABLE_MIRA=OFF")
            ;;
        *)
            msg red "Invalid 1st argument for publish"
            msg green "Usage: $0 publish [mira|nomira] [version] (extratag def: latest)"
            return 1
            ;;
    esac

    V="$2"
    
    : ${MAIN_TAG="someguy123/steem:$V"}
    [[ "$MKMIRA" == "mira" ]] && SECTAG="latest-mira" || SECTAG="latest"
    (( $# > 2 )) && SECTAG="$3"
    if [[ "$SECTAG" == "n/a" ]]; then
        msg bold yellow  " >> Will build tag $V as tags $MAIN_TAG (no second tag)"
    else
        SECOND_TAG="someguy123/steem:$SECTAG"
        msg bold yellow " >> Will build tag $V as tags $MAIN_TAG and $SECOND_TAG"
    fi
    sleep 5
    ./run.sh build "$V" tag "$MAIN_TAG" "${BUILD_OPTS[@]}"
    [[ "$SECTAG" != "n/a" ]] && docker tag "$MAIN_TAG" "$SECOND_TAG"
    docker push "$MAIN_TAG"
    [[ "$SECTAG" != "n/a" ]] && docker push "$SECOND_TAG"

    msg bold green " >> Finished"
}


if [ "$#" -lt 1 ]; then
    help
fi

case $1 in
    build)
        msg bold yellow "You may want to use '$0 install' for a binary image instead, it's faster."
        build "${@:2}"
        ;;
    build_full)
        msg bold yellow "You may want to use '$0 install_full' for a binary image instead, it's faster."
        build_full "${@:2}"
        ;;
    build_local)
        build_local "${@:2}"
        ;;
    install_docker)
        install_docker
        ;;
    install)
        install "${@:2}"
        ;;
    install_full)
        install_full
        ;;
    publish)
        publish "${@:2}"
        ;;
    start)
        start "${@:2}"
        ;;
    replay)
        replay "${@:2}"
        ;;
    memory_replay)
        memory_replay
        ;;
    shm_size)
        shm_size $2
        ;;
    stop)
        stop
        ;;
    kill)
        sbkill
        ;;
    restart)
        stop
        sleep 5
        start
        ;;
    rebuild)
        stop
        sleep 5
        build
        start
        ;;
    clean)
        sb_clean "${@:2}"
        ;;
    optimize)
        msg "Applying recommended dirty write settings..."
        optimize
        ;;
    status)
        status
        ;;
    wallet)
        wallet
        ;;
    remote_wallet)
        remote_wallet "${@:2}"
        ;;
    dlblocks)
        dlblocks "${@:2}"
        ;;
    dlblockindex|dlblocksindex|dl-block-index|dlblocks-index)
        fix-blocks-index "${@:2}"
        ;;
    dlrocksdb)
        dlrocksdb "${@:2}"
        ;;
    fix-blocks|fix_blocks|fixblocks)
        fix-blocks "${@:2}"
        ;;
    monitor)
        siab-monitor "${@:2}"
        ;;
    stateshot)
        install-stateshot "${@:2}"
        ;;
    enter)
        enter
        ;;
    shell)
        shell
        ;;
    logs)
        logs
        ;;
    pclogs)
        pclogs
        ;;
    tslogs)
        tslogs
        ;;
    clean_logs|cleanlogs|clean-logs)
        clean-logs
        ;;
    ver|version)
        ver
        ;;
    *)
        msg bold red "Invalid cmd"
        help
        ;;
esac

exit 0

