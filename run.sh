#!/bin/bash
#
# Steem-in-a-box Main Application Script
#
# Steem-in-a-box (or SIAB for short) is a collection of bash scripts designed to make
# setting up and maintaining steemd (Steem Daemon) easy, whether you're using it for
# a seed node, a witness, or an RPC full node.
#
# Primarily designed for use on Ubuntu Server (16.04 or 18.04), but may
# work on other Debian-based distros.
#
# Released under GNU AGPL by Someguy123
# https://github.com/someguy123/steem-docker
#

# _DIR should be able to determine the absolute path where run.sh is located
_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# If something is wrong with _DIR attempting to locate SIAB, you can override DIR from the CLI
# e.g. export SIAB_DIR='/steem'; ./run.sh logs
: ${SIAB_DIR="$_DIR"}
DIR="$SIAB_DIR"              # The folder where Steem-in-a-box (steem-docker) is located

: ${DOCKER_DIR="$DIR/dkr"}                 # Folder containing Dockerfile used to build Steem low memory node
: ${FULL_DOCKER_DIR="$DIR/dkr_fullnode"}   # Folder containing Dockerfile used to build Steem full node
: ${DATADIR="$DIR/data"}     # Location of the Steem 'data' folder (generally contains witness_node_data_dir)
: ${DOCKER_NAME="seed"}      # A unique name to use for the docker container created by this SIAB install
: ${DOCKER_IMAGE="steem"}    # The tag name of the docker image to use when starting/replaying Steem


# HTTP or HTTPS url to grab the blockchain from. Set compression in BC_HTTP_CMP
: ${BC_HTTP="http://files.privex.io/steem/block_log.lz4"}

# Compression type, can be "xz", "lz4", or "no" (for no compression)
# Uses on-the-fly de-compression while downloading, to conserve disk space
# and save time by not having to decompress after the download is finished
: ${BC_HTTP_CMP="lz4"}

# Anonymous rsync daemon URL to the raw block_log, for repairing/resuming
# a damaged/incomplete block_log. Set to "no" to disable rsync when resuming.
: ${BC_RSYNC="rsync://files.privex.io/steem/block_log"}

: ${REMOTE_WS="wss://steemd.privex.io"}
# Amount of time in seconds to allow the docker container to stop before killing it.
# Default: 600 seconds (10 minutes)
: ${STOP_TIME=600}

# default. override in .env
: ${PORTS="2001"}

# Placeholder variables - used internally by functions. Do not touch.
BUILD_FULL=0 CUST_TAG="steem" BUILD_VER=""

# Array of additional arguments to be passed to Docker during builds
# Generally populated using arguments passed to build/build_full
# But you can specify custom additional build parameters by setting BUILD_ARGS
# as an array in .env
# e.g.
#
#    BUILD_ARGS=('--rm' '-q' '--compress')
#
BUILD_ARGS=()


[[ -f "${DIR}/.env" ]] && source  "${DIR}/.env"


# If MIRA is 1, will install someguy123/steem:latest-mira instead of latest
# and automatically set ENABLE_MIRA to ON when building.
: ${MIRA=0}

if [[ "$MIRA" -eq 1 ]]; then
    : ${SHM_DIR="${DATADIR}/rocksdb"}
    : ${DK_TAG="someguy123/steem:latest-mira"}
    : ${DK_TAG_FULL="someguy123/steem:latest-mira-full"}
else
    : ${SHM_DIR="/dev/shm"}
    : ${DK_TAG="someguy123/steem:latest"}
    : ${DK_TAG_FULL="someguy123/steem:latest-full"}
fi

# Witness Node Data Dir (home of config.ini and blockchain etc.)
: ${WITDIR="$DATADIR/witness_node_data_dir"}
# blockchain folder, used by dlblocks
: ${BC_FOLDER="$WITDIR/blockchain"}
BCDIR="$BC_FOLDER"
: ${EXAMPLE_MIRA="$WITDIR/database.cfg.example"}
: ${MIRA_FILE="$WITDIR/database.cfg"}

: ${EXAMPLE_CONF="$WITDIR/config.ini.example"}
: ${CONF_FILE="$WITDIR/config.ini"}

[[ ! -d "${WITDIR}" ]] && msg " >> WITDIR Folder ${WITDIR} did not exist. Creating it." && mkdir -pv "${WITDIR}"
[[ ! -d "${DATADIR}" ]] && msg " >> DATADIR Folder ${DATADIR} did not exist. Creating it." && mkdir -pv "${DATADIR}"
[[ ! -d "${BCDIR}" ]] && msg " >> BCDIR Folder ${BCDIR} did not exist. Creating it." && mkdir -pv "${BCDIR}"
[[ ! -d "${SHM_DIR}" ]] && msg " >> SHM_DIR Folder ${SHM_DIR} did not exist. Creating it." && mkdir -pv "${SHM_DIR}"

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
      DPORTS+=("-p0.0.0.0:$i:$i")
    fi
done

# various helper functions such as 'msg', 'pkg_not_found', 'yesno' and 'containsElement'
source "${DIR}/scripts/000_helpers.sh"
# load docker hub API
source "${DIR}/scripts/010_docker.sh"


help() {
    echo "Usage: $0 COMMAND [DATA]"
    echo
    echo "Commands: 
    start - starts steem container
    clean - Remove blockchain, p2p, and/or shared mem folder contents (warns beforehand)
    dlblocks - download and decompress the blockchain to speed up your first start
    replay - starts steem container (in replay mode)
    memory_replay - starts steem container (in replay mode, with --memory-replay)
    shm_size - resizes /dev/shm to size given, e.g. ./run.sh shm_size 10G 
    stop - stops steem container
    status - show status of steem container
    restart - restarts steem container
    install_docker - install docker
    install - pulls latest docker image from server (no compiling)
    install_full - pulls latest (FULL NODE FOR RPC) docker image from server (no compiling)
    rebuild - builds steem container (from docker file), and then restarts it
    build - only builds steem container (from docker file)
    logs - show all logs inc. docker logs, and steem logs
    wallet - open cli_wallet in the container
    remote_wallet - open cli_wallet in the container connecting to a remote seed
    enter - enter a bash session in the currently running container
    shell - launch the steem container with appropriate mounts, then open bash for inspection
    "
    echo
    exit
}


optimize() {
    echo    75 | sudo tee /proc/sys/vm/dirty_background_ratio
    echo  1000 | sudo tee /proc/sys/vm/dirty_expire_centisecs
    echo    80 | sudo tee /proc/sys/vm/dirty_ratio
    echo 30000 | sudo tee /proc/sys/vm/dirty_writeback_centisecs
}

# Determines whether ENABLE_MIRA was passed in custom build args
# so we don't have to fall back to $MIRA
export MIRA_SET=0

should_build_mira() {
    if (( $MIRA_SET == 0 )); then
        msg bold yellow "No ENABLE_MIRA build argument was specified. Falling back to MIRA env option."
        if (( $MIRA == 1 )); then
            msg yellow " >> Enabling MIRA - setting 'ENABLE_MIRA=ON' as MIRA env var was set to 1"
            BUILD_ARGS+=('--build-arg' "ENABLE_MIRA=ON")
        else
            msg yellow " >> Disabling MIRA - setting 'ENABLE_MIRA=OFF' as MIRA env var wasn't 1 (defaults to 0)"
            BUILD_ARGS+=('--build-arg' "ENABLE_MIRA=OFF")
        fi
    fi
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
    if (( $# >= 1 )); then
        msg yellow " >> Additional build arguments specified."
        for a in "$@"; do
            msg yellow " ++ Build argument: ${BOLD}${a}"
            grep -qi "ENABLE_MIRA" <<< "$a" && MIRA_SET=1
            BUILD_ARGS+=('--build-arg' "$a")
        done
    fi
    msg blue " ++ CUSTOM BUILD SPECIFIED. Building from branch/tag ${BOLD}${BUILD_VER}"
    msg blue " ++ Tagging final image as: ${BOLD}${CUST_TAG}"
    msg yellow " -> Docker build arguments: ${BOLD}${BUILD_ARGS[@]}"
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
        # Scan arguments for tag and build arguments, will set CUST_TAG and append to BUILD_ARGS
        parse_build_args "$@"
        # Check if the user specified ENABLE_MIRA in their build args. If not, fallback to default using $MIRA
        should_build_mira
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
        To use it in this steem-docker, run: 
        ${GREEN}${BOLD}
        docker tag $CUST_TAG steem:latest
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
    should_build_mira
    cd "$DOCKER_DIR"
    docker build "${BUILD_ARGS[@]}" -t "$DOCKER_IMAGE" .
    ret=$?
    if (( $ret == 0 )); then
        msg bold green " +++ Successfully built current stable steemd"
        msg green " +++ Steem node type: ${BOLD}${fmm}"
        msg green " +++ Build args: ${BOLD}${BUILD_ARGS[@]}"
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

setup() {
    cd "$DIR"
    git pull
    git submodule update --init --recursive

    msg green "================================================================\n"
    msg green "Welcome to the Easy Setup Tool for Steem-in-a-box.\n"
    msg green "Developed by Someguy123 ( https://steemit.com/@someguy123 )"
    msg green "Blockchain files hosted by Privex ( www.privex.io || steemit.com/@privex )\n"
    msg green "================================================================\n"
    msg yellow " --- Below are the defaults we use, if you don't specify: ---"
    msg yellow "\tEnable MIRA:\t No"
    msg yellow "\tDownload Blocks:\t No"
    msg yellow "\tContainer Name:\t seed"
    msg yellow "\tLow Memory Mode:\t Yes"
    msg yellow "\tExpose Ports:\t 2001\t (Default P2P port)"
    msg yellow "\t/dev/shm size:\t 64G\t (Only if MIRA is enabled)"
    msg yellow "--------------------------\n\n"
    msg bold green " +++ First, we strongly recommend running this setup tool in 'screen' or 'tmux' +++ "
    msg green " +++ This ensures the setup does not get interrupted if you get disconnected from SSH +++"

    if yesno "${YELLOW}Do you wish to continue? (Y/n) > ${RESET}" defyes invert; then
        return 1
    fi

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
    [[ -f "$BC_FOLDER/block_log.index" ]] && msgts "Removing old block index" && sudo rm -vf "$BC_FOLDER/block_log.index" 2> /dev/null

    if (( $# > 0 )); then
        custom-dlblocks "$@"
        return $?
    fi
    if [[ -f "$BC_FOLDER/block_log" ]]; then
        msgts yellow "It looks like block_log already exists"
        if [[ "$BC_RSYNC" == "no" ]]; then
            msgts red "As BC_RSYNC is set to 'no', we're just going to try to retry the http download"
            msgts "If your HTTP source is uncompressed, we'll try to resume it"
            dl-blocks-http "$BC_HTTP" "$BC_HTTP_CMP"
            return
        else
            msgts green "We'll now use rsync to attempt to repair any corruption, or missing pieces from your block_log."
            dl-blocks-rsync "$BC_RSYNC"
            return
        fi
    fi
    msgts "No existing block_log found. Will use standard http to download, and will\n also decompress lz4 while downloading, to save time."
    msgts "If you encounter an error while downloading the block_log, just run dlblocks again,\n and it will use rsync to resume and repair it"
    dl-blocks-http "$BC_HTTP" "$BC_HTTP_CMP" 
    msgts "FINISHED. Blockchain installed to ${BC_FOLDER}/block_log (make sure to check for any errors above)"
    msgts red "If you encountered an error while downloading the block_log, just run dlblocks again\n and it will use rsync to resume and repair it"
    echo "Remember to resize your /dev/shm, and run with replay!"
    echo "$ ./run.sh shm_size SIZE (e.g. 8G)"
    echo "$ ./run.sh replay"
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
            msgts yellow " -> Removing old block_log..."
            sudo rm -vf "$BC_FOLDER/block_log"
            dl-blocks-rsync "$url"
            return $?
            ;;
        http)
            dl-blocks-http "$url" "$compress"
            return $? 
            ;;
        http-replace)
            msgts yellow " -> Removing old block_log..."
            sudo rm -vf "$BC_FOLDER/block_log"
            dl-blocks-http "$url" "$compress"
            return $?
            ;;
        *)
            msgts red "Invalid download method"
            msgts red "Valid options are http, http-replace, rsync, or rsync-replace"
            return 1
            ;;
    esac 
}

# Internal use
# Usage: dl-blocks-rsync blocklog_url
dl-blocks-rsync() {
    local url="$1"
    msgts "This may take a while, and may at times appear to be stalled. ${YELLOW}${BOLD}Be patient, it takes time (3 to 10 mins) to scan the differences."
    msgts "Once it detects the differences, it will download at very high speed depending on how much of your block_log is intact."
    echo -e "\n==============================================================="
    echo -e "${BOLD}Downloading via:${RESET}\t${url}"
    echo -e "${BOLD}Writing to:${RESET}\t\t${BC_FOLDER}/block_log"
    echo -e "===============================================================\n"
    # I = ignore timestamps and size, vv = be more verbose, h = human readable
    # append-verify = attempt to append to the file, but make sure to verify the existing pieces match the server
    rsync -Ivvh --append-verify --progress "$url" "${BC_FOLDER}/block_log"
    ret=$?
    if (($ret==0)); then
        msgts bold green " (+) FINISHED. Blockchain downloaded via rsync (make sure to check for any errors above)"
    else
        msgts bold red "An error occurred while downloading via rsync... please check above for errors"
    fi
    return $ret
}

# Internal use
# Usage: dl-blocks-http blocklog_url [compress_type]
dl-blocks-http() {
    local url="$1"
    local compression="no"
    (( $# < 1 )) && msgts bold red "ERROR: no url specified for dl-blocks-http" && return 1
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
        msgts bold green " -> Downloading and de-compressing block log on-the-fly..."
    else
        msgts bold green " -> Downloading raw block log..."
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
    if (($ret==0)); then
        msgts bold green " (+) FINISHED. Blockchain downloaded and decompressed (make sure to check for any errors above)"
    else
        msgts bold red "An error occurred while downloading... please check above for errors"
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
                msgts bold red "WARNING: Neither / nor : were present in your tag '$1'"
                DK_TAG="someguy123/steem:$1"
                msgts red "We're assuming you've entered a version, and will try to install @someguy123's image: '${DK_TAG}'"
                msgts yellow "If you *really* specifically want '$1' from Docker hub, set DK_TAG='$1' inside of .env and run './run.sh install'"
            fi
        fi
    fi
    msgts bold red "NOTE: You are installing image $DK_TAG. Please make sure this is correct."
    sleep 2
    msgts yellow " -> Loading image from ${DK_TAG}"
    docker pull "$DK_TAG"
    msgts green " -> Tagging as steem"
    docker tag "$DK_TAG" steem
    msgts bold green " -> Installation completed. You may now configure or run the server"
}

# Usage: ./run.sh install_full
# Downloads the Steem full node image from the pre-set $DK_TAG_FULL in run.sh or .env
# Default tag is normally someguy123/steem:latest-full (official builds by the creator of steem-docker).
#
install_full() {
    msgts yellow " -> Loading image from ${DK_TAG_FULL}"
    docker pull "$DK_TAG_FULL" 
    msgts green " -> Tagging as steem"
    docker tag "$DK_TAG_FULL" steem
    msgts bold green " -> Installation completed. You may now configure or run the server"
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
    msgts bold green " -> Starting container '${DOCKER_NAME}'..."
    seed_exists
    if [[ $? == 0 ]]; then
        docker start $DOCKER_NAME
    else
        docker run ${DPORTS[@]} -v "$SHM_DIR":/shm -v "$DATADIR":/steem -d --name $DOCKER_NAME -t "$DOCKER_IMAGE" steemd --data-dir=/steem/witness_node_data_dir
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
    msgts yellow " -> Removing old container '${DOCKER_NAME}'"
    docker rm $DOCKER_NAME
    msgts green " -> Running steem (image: ${DOCKER_IMAGE}) with replay in container '${DOCKER_NAME}'..."
    docker run ${DPORTS[@]} -v "$SHM_DIR":/shm -v "$DATADIR":/steem -d --name $DOCKER_NAME -t "$DOCKER_IMAGE" steemd --data-dir=/steem/witness_node_data_dir --replay
    msgts bold green " -> Started."
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
    msgts green " -> Setting /dev/shm to $1"
    sudo mount -o remount,size=$1 /dev/shm
    if [[ $? -eq 0 ]]; then
        msgts bold green "Successfully resized /dev/shm"
    else
        msgts bold red "An error occurred while resizing /dev/shm..."
        msgts red "Make sure to specify size correctly, e.g. 64G. You can also try using sudo to run this."
    fi
}

# Usage: ./run.sh stop
# Stops the Steem container, and removes the container to avoid any leftover
# configuration, e.g. replay command line options
#
stop() {
    msgts "If you don't care about a clean stop, you can force stop the container with ${BOLD}./run.sh kill"
    msgts red "Stopping container '${DOCKER_NAME}' (allowing up to ${STOP_TIME} seconds before killing)..."
    docker stop -t ${STOP_TIME} $DOCKER_NAME
    msgts red "Removing old container '${DOCKER_NAME}'..."
    docker rm $DOCKER_NAME
}

sbkill() {
    msgts bold red "Killing container '${DOCKER_NAME}'..."
    docker kill "$DOCKER_NAME"
    msgts red "Removing container ${DOCKER_NAME}"
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
    pkg_not_found jq jq
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
    pkg_not_found jq jq
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

        # Using the function `get_latest_id` - obtain the latest SHA256 sum from Docker Hub for the image we use
        (( $MIRA == 1 )) && rmt_tag='latest-mira' || rmt_tag='latest'
        remote_docker_id="$(get_latest_id 'someguy123/steem' $rmt_tag)"

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
                msgts bold red " !!! Clearing all files in SHM_DIR ( $SHM_DIR )"
                rm -rfv "$SHM_DIR"/*
                mkdir -p "$SHM_DIR" &> /dev/null
                msgts bold green " +++ Cleared shared files directory."
                ;;
            bloc*)
                msgts bold red " !!! Clearing all files in $bc_dir and $p2p_dir"
                rm -rfv "$bc_dir"/*
                rm -rfv "$p2p_dir"/*
                mkdir -p "$bc_dir" "$p2p_dir" &> /dev/null
                msgts bold green " +++ Cleared blockchain files + p2p"
                ;;
            all)
                msgts bold red " !!! Clearing blockchain, p2p, and shared memory files..."
                rm -rfv "$SHM_DIR"/*
                rm -rfv "$bc_dir"/*
                rm -rfv "$p2p_dir"/*
                mkdir -p "$bc_dir" "$p2p_dir" "$SHM_DIR" &> /dev/null
                msgts bold green " +++ Cleared blockchain + p2p + shared memory"
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
        msgts bold red " !!! Clearing blockchain files..."
        rm -rvf "$bc_dir"/*
        mkdir -p "$bc_dir" &> /dev/null
        msgts bold green " +++ Cleared blockchain files"
    else
        msgts yellow " >> Not clearing blockchain folder."
    fi
    
    read -p "Do you want to remove the p2p files? (y/n) > " cleanp2p
    if [[ "$cleanp2p" == "y" ]]; then
        msgts bold red " !!! Clearing p2p files..."
        rm -rvf "$p2p_dir"/*
        mkdir -p "$p2p_dir" &> /dev/null
        msgts bold green " +++ Cleared p2p files"
    else
        msgts yellow " >> Not clearing p2p folder."
    fi
    
    read -p "Do you want to remove the shared memory / rocksdb files? (y/n) > " cleanshm
    if [[ "$cleanshm" == "y" ]]; then
        msgts bold red " !!! Clearing shared memory files..."
        rm -rvf "$SHM_DIR"/*
        mkdir -p "$SHM_DIR" &> /dev/null
        msgts bold green " +++ Cleared shared memory files"
    else
        msgts yellow " >> Not clearing shared memory folder."
    fi

    msgts bold green " ++ Done."
}

err() {
    msg "$@" >&2;
}

sb_debug() {
    local LOG=$(mktemp) upload=0 auto=0
    pkg_not_found nc netcat 
    msg bold green "Outputting log to: $LOG"
    while (( $# > 0 )); do
        [[ "$1" == "upload" ]] && upload=1 && \
                    msg bold green "Upload enabled. Will confirm upload request after generating logs"
        [[ "$1" == "auto" ]] && auto=1 && \
                    msg bold red "WARNING: Unattended mode enabled. Will generate log and upload it to termbin with no user interaction.\n" \
                                 "If this is not what you want to do, you have 10 SECONDS to press CTRL-C to abort." && sleep 10
        shift
    done

    LINE="==================================================="
    {
        msg "${LINE}\n"
        msg "Steem-in-a-box Debug Log \nHostname: $(hostname) \nDate Checked: $(date)"
        msg "${LINE}\n\n\n"
        
        err yellow ">> Loading your config ($CONF_FILE) and redacting private key...\n"

        CONFDATA=$(sed -E "s/private-key.*/private-key = 5xxxxxxxxxxxxxxx/" "$CONF_FILE")
        msg 
        msg "${LINE}"
        msg " --- CONFIG FILE @ $CONF_FILE --- "
        msg "${LINE}\n\n\n"

        cat <<< "$CONFDATA"
        msg "\n\n${LINE}"
        msg " --- END CONFIG ---"
        msg "${LINE}\n\n\n"

        err yellow " >> Checking git status of your SIAB install\n"
        msg " --- Git Status: ---"
        git status
        msg " --- END GIT STATUS --- \n\n"

        err yellow " >> Listing files inside of '$DIR' '$BCDIR' and '$SHM_DIR'"
        
        msg " --- All files in DIR: $DIR ---"
        ls -lah "$DIR"
        msg "--- END DIR FILES ---\n\n"

        msg "--- All files in BCDIR: $BCDIR ---"
        ls -lah "$BCDIR"
        msg "--- END BCDIR FILES ---\n\n"

        msg "--- All files in SHM_DIR: $SHM_DIR --- "
        ls -lah "$SHM_DIR"
        msg "--- END SHM_DIR FILES ---\n\n"

        msg "\n\n\n${LINE}\n\n\n"
    } >> "$LOG"


    {
        err yellow " >> Checking memory usage\n"
        msg " --- FREE MEMORY / USAGE --- "
        free -m
        msg " --- END MEMORY --- \n\n"

        err yellow  " >> Checking /dev/shm and disk space usage\n"
        msg " --- FREE DISK/SHM PLUS USAGE --- "
        df -h
        msg " --- END DISK/SHM --- \n\n"
        err yellow " >> Scanning for OS version, SIAB version information, Docker containers + Images, and Docker version\n"
        msg " ------ VERSION INFORMATION -----"
        msg "\n${LINE}\n"
        msg "Output of 'uname -a':\n"
        uname -a
        msg "\n${LINE}\n"

        msg "Contents of '/etc/lsb-release':\n"
        cat /etc/lsb-release
        msg "\n${LINE}\n"

        P=$(pwd)
        cd "$DIR"

        msg "SIAB GIT STATUS:\n"
        git status
        git log | head -n 15
        
        msg "\n${LINE}\n"
        msg "DOCKER IMAGES:\n"
        docker images
        
        msg "\n${LINE}\n"
        msg "RUNNING CONTAINERS:\n"
        docker ps -a >> "$LOG"

        msg "\n${LINE}\n"
        msg "DOCKER VERSION:\n"
        docker -v
        cd "$P"
        msg " --- END VERSION INFO --- \n\n"
        msg "\n${LINE}\n"
        
        err yellow " >> Dumping all environment variables (will attempt to filter out any that may contain passwords)\n"
        msg " --- All environment variables present --- \n\n"
        unset CONFDATA LS_COLORS &>/dev/null   # These two env vars are spammy in the log, and not needed
        set -o posix ; set | grep -Evi "_pass|_pwd|unlock|_key|token"
        msg "\n${LINE}\n"
        
        msg "--- END ENVIRONMENT VARS --- \n"

        msg "${LINE}\n\n"
        msg "End of Steem-in-a-box Debug Log \nHostname: $(hostname)\nDate Checked: $(date)"
        msg "${LINE}\n\n"


    } >> "$LOG"
    msg "\n=====================================================\n"
    # Strip colour codes from log (https://unix.stackexchange.com/a/55547/166253)
    sed -E -i 's/\x1B\[[0-9;]*[JKmsu]//g' "$LOG"
    msg green "Log has been outputted to: ${BOLD}$LOG"
    msg green "Use 'cat $LOG' or 'nano $LOG' to view the log data"
    msg "\n=====================================================\n"
    if (( $auto == 1 )); then
      msg bold green "Uploading log '$LOG' to termbin in 10 seconds. Press CTRL-C to cancel."
      sleep 10
      cat "$LOG" | nc termbin.com 9999
      msg green "Please give the above link to the person helping you. You can look at it in your browser if you'd like to make sure there's no personal information"
      msg green "\n +++ Debug log completed. Exiting now."
      return 0
    fi
    if (( $upload != 1 )); then
      msg yellow "Did not request upload (use '$0 debug upload' if you want to upload after dumping log)\n"
      msg yellow "Tip: Use '$0 debug upload' if you want to upload the log after dumping it - we'll let you view and edit the log before uploading it"
      msg yellow "Tip: For use in shell scripts, or if you trust that the logs are safe to upload, you can use '$0 debug auto' to automatically upload " \
                 "to Termbin after creating the log - with no prompts"
      msg green "\n +++ Debug log completed. Exiting now."
      return 0
    fi
    while true; do
      echo
      read -p "Do you want to upload the log to termbin? (y)es/(e)dit/(n)o) > " yn
      case $yn in
        [Yy]* )
          msg bold green "Uploading log '$LOG' to termbin"
          cat "$LOG" | nc termbin.com 9999
          msg green "Please give the above link to the person helping you. You can look at it in your browser if you'd like to make sure there's no personal information"
          break;;
        [Ee]* )
          msg "Opening $LOG in editor 'nano'"
          nano "$LOG"
          msg yellow "Looks like you finished editing, or you're happy with the file."
          ;;
        [Nn]* )
          exit 1
          break;;
        * ) msg red "Please answer yes (y), edit (e), or no (n).";;
      esac
    done
    msg green "\n +++ Debug log completed. Exiting now."
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
    install_docker)
        install_docker
        ;;
    install)
        install "${@:2}"
        ;;
    install_full)
        install_full
        ;;
    start)
        start
        ;;
    replay)
        replay
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
    setup)
        setup
        ;;
    debug)
        sb_debug "${@:2}"
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
    ver|version)
        ver
        ;;
    *)
        msg bold red "Invalid cmd"
        help
        ;;
esac

