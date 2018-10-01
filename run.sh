#!/bin/bash
#
# Steem node manager
# Released under GNU AGPL by Someguy123
#

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOCKER_DIR="$DIR/dkr"
FULL_DOCKER_DIR="$DIR/dkr_fullnode"
DATADIR="$DIR/data"
DOCKER_NAME="seed"

BOLD="$(tput bold)"
RED="$(tput setaf 1)"
GREEN="$(tput setaf 2)"
YELLOW="$(tput setaf 3)"
BLUE="$(tput setaf 4)"
MAGENTA="$(tput setaf 5)"
CYAN="$(tput setaf 6)"
WHITE="$(tput setaf 7)"
RESET="$(tput sgr0)"
: ${DK_TAG="someguy123/steem:latest"}
DK_TAG_FULL=someguy123/steem:latest-full
: ${DK_TAG_FULL="someguy123/steem:latest-full"}
SHM_DIR=/dev/shm
: ${REMOTE_WS="wss://steemd.privex.io"}

# default. override in .env
PORTS="2001"

if [[ -f .env ]]; then
    source .env
fi

if [[ ! -f data/witness_node_data_dir/config.ini ]]; then
    echo "config.ini not found. copying example (seed)";
    cp data/witness_node_data_dir/config.ini.example data/witness_node_data_dir/config.ini
fi

IFS=","
DPORTS=()
for i in $PORTS; do
    if [[ $i != "" ]]; then
	    DPORTS+=("-p0.0.0.0:$i:$i")
    fi
done

# load docker hub API
source scripts/000_docker.sh

help() {
    echo "Usage: $0 COMMAND [DATA]"
    echo
    echo "Commands: "
    echo "    start - starts steem container"
    echo "    dlblocks - download and decompress the blockchain to speed up your first start"
    echo "    replay - starts steem container (in replay mode)"
    echo "    shm_size - resizes /dev/shm to size given, e.g. ./run.sh shm_size 10G "
    echo "    stop - stops steem container"
    echo "    status - show status of steem container"
    echo "    restart - restarts steem container"
    echo "    install_docker - install docker"
    echo "    install - pulls latest docker image from server (no compiling)"
    echo "    install_full - pulls latest (FULL NODE FOR RPC) docker image from server (no compiling)"
    echo "    rebuild - builds steem container (from docker file), and then restarts it"
    echo "    build - only builds steem container (from docker file)"
    echo "    logs - show all logs inc. docker logs, and steem logs"
    echo "    wallet - open cli_wallet in the container"
    echo "    remote_wallet - open cli_wallet in the container connecting to a remote seed"
    echo "    enter - enter a bash session in the container"
    echo
    exit
}

optimize() {
    echo    75 | sudo tee /proc/sys/vm/dirty_background_ratio
    echo  1000 | sudo tee /proc/sys/vm/dirty_expire_centisecs
    echo    80 | sudo tee /proc/sys/vm/dirty_ratio
    echo 30000 | sudo tee /proc/sys/vm/dirty_writeback_centisecs
}

build() {
    if (( $# == 1 )); then
	BUILD_VER=$1
	echo $BLUE"CUSTOM BUILD SPECIFIED. Building from branch/tag $BUILD_VER"$RESET
	sleep 2
	cd $DOCKER_DIR
	CUST_TAG="steem:$BUILD_VER"
        docker build --build-arg "steemd_version=$BUILD_VER" -t "$CUST_TAG" .
	echo $RED"For your safety, we've tagged this image as $CUST_TAG"$RESET
	echo $RED"To use it in this steem-docker, run: docker tag $CUST_TAG steem:latest"$RESET
	return
    fi
    echo $GREEN"Building docker container"$RESET
    cd $DOCKER_DIR
    docker build -t steem .
}

build_full() {
    if (( $# == 1 )); then
	BUILD_VER=$1
	echo $BLUE"CUSTOM (FULL NODE) BUILD SPECIFIED. Building from branch/tag $BUILD_VER"$RESET
	sleep 2
	cd $FULL_DOCKER_DIR
	CUST_TAG="steem:$BUILD_VER"
        docker build --build-arg "steemd_version=$BUILD_VER" -t "$CUST_TAG" .
	echo $RED"For your safety, we've tagged this image as $CUST_TAG"$RESET
	echo $RED"To use it in this steem-docker, run: docker tag $CUST_TAG steem:latest"$RESET
	return
    fi
    echo $GREEN"Building full-node docker container"$RESET
    cd $FULL_DOCKER_DIR
    docker build -t steem .
}

dlblocks() {
    if [[ ! -d "$DATADIR/blockchain" ]]; then
        mkdir "$DATADIR/blockchain"
    fi
    echo "Removing old block log"
    sudo rm -f $DATADIR/witness_node_data_dir/blockchain/block_log
    sudo rm -f $DATADIR/witness_node_data_dir/blockchain/block_log.index
    echo "Download @gtg's block logs..."
    if [[ ! $(command -v pixz) ]]; then
        echo "PIXZ not found. Attempting to install..."
        sudo apt update
        sudo apt install -y pixz 
    fi
    wget https://gtg.steem.house/get/blockchain.xz/block_log.xz -O $DATADIR/witness_node_data_dir/blockchain/block_log.xz
    echo "Decompressing block log... this may take a while..."
    pixz -d $DATADIR/witness_node_data_dir/blockchain/block_log.xz $DATADIR/witness_node_data_dir/blockchain/block_log
    echo "FINISHED. Blockchain downloaded and decompressed"
    echo "Remember to resize your /dev/shm, and run with replay!"
    echo "$ ./run.sh shm_size SIZE (e.g. 8G)"
    echo "$ ./run.sh replay"
}

install_docker() {
    sudo apt update
    sudo apt install curl git
    curl https://get.docker.com | sh
    if [ "$EUID" -ne 0 ]; then 
        echo "Adding user $(whoami) to docker group"
        sudo usermod -aG docker $(whoami)
        echo "IMPORTANT: Please re-login (or close and re-connect SSH) for docker to function correctly"
    fi
}

install() {
    if (( $# == 1 )); then
	DK_TAG=$1
    fi
    echo $BLUE"NOTE: You are installing image $DK_TAG. Please make sure this is correct."$RESET
    sleep 2
    docker pull $DK_TAG 
    echo "Tagging as steem"
    docker tag $DK_TAG steem
    echo "Installation completed. You may now configure or run the server"
}

install_full() {
    echo "Loading image from someguy123/steem"
    docker pull $DK_TAG_FULL 
    echo "Tagging as steem"
    docker tag $DK_TAG_FULL steem
    echo "Installation completed. You may now configure or run the server"
}
seed_exists() {
    seedcount=$(docker ps -a -f name="^/"$DOCKER_NAME"$" | wc -l)
    if [[ $seedcount -eq 2 ]]; then
        return 0
    else
        return -1
    fi
}

seed_running() {
    seedcount=$(docker ps -f 'status=running' -f name=$DOCKER_NAME | wc -l)
    if [[ $seedcount -eq 2 ]]; then
        return 0
    else
        return -1
    fi
}

start() {
    echo $GREEN"Starting container..."$RESET
    seed_exists
    if [[ $? == 0 ]]; then
        docker start $DOCKER_NAME
    else
        docker run ${DPORTS[@]} -v "$SHM_DIR":/shm -v "$DATADIR":/steem -d --name $DOCKER_NAME -t steem steemd --data-dir=/steem/witness_node_data_dir
    fi
}

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
    echo "Removing old container"
    docker rm $DOCKER_NAME
    echo "Running steem with replay..."
    docker run ${DPORTS[@]} -v "$SHM_DIR":/shm -v "$DATADIR":/steem -d --name $DOCKER_NAME -t steem steemd --data-dir=/steem/witness_node_data_dir --replay
    echo "Started."
}

shm_size() {
    if (( $# != 1 )); then
	echo $RED"Please specify a size, such as ./run.sh shm_size 64G"
    fi
    echo "Setting SHM to $1"
    mount -o remount,size=$1 /dev/shm
}

stop() {
    echo $RED"Stopping container..."$RESET
    docker stop $DOCKER_NAME
    echo $RED"Removing old container..."$RESET
    docker rm $DOCKER_NAME
}

enter() {
    docker exec -it $DOCKER_NAME bash
}

wallet() {
    docker exec -it $DOCKER_NAME cli_wallet -s ws://127.0.0.1:8090
}

remote_wallet() {
    if (( $# == 1 )); then
	REMOTE_WS=$1
    fi
    docker run -v "$DATADIR":/steem --rm -it steem cli_wallet -s "$REMOTE_WS"
}

logs() {
    echo $BLUE"DOCKER LOGS: (press ctrl-c to exit) "$RESET
    docker logs -f --tail=30 $DOCKER_NAME
    #echo $RED"INFO AND DEBUG LOGS: "$RESET
    #tail -n 30 $DATADIR/{info.log,debug.log}
}

pclogs() {
    if [[ ! $(command -v jq) ]]; then
        echo $RED"jq not found. Attempting to install..."$RESET
        sleep 3
        sudo apt update
        sudo apt install -y jq
    fi
    local LOG_PATH=$(docker inspect $DOCKER_NAME | jq -r .[0].LogPath)
    local pipe=/tmp/dkpipepc.fifo
    trap "rm -f $pipe" EXIT
    if [[ ! -p $pipe ]]; then
        mkfifo $pipe
    fi
    # the sleep is a dirty hack to keep the pipe open

    sleep 10000 < $pipe &
    tail -n 5000 -f "$LOG_PATH" &> $pipe &
    while true
    do
        if read -r line <$pipe; then
            # first grep the data for "M free" to avoid
            # needlessly processing the data
            L=$(grep --colour=never "M free" <<< "$line")
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

tslogs() {
    if [[ ! $(command -v jq) ]]; then
        echo $RED"jq not found. Attempting to install..."$RESET
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
    git log --pretty=format:"$commit_format" $args
}

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
    if grep -q "up-to-date" <<< "$git_update"; then
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
        echo "${RED}WARNING: We could not find the currently installed image (steem:lateset)${RESET}"
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

if [ "$#" -lt 1 ]; then
    help
fi

case $1 in
    build)
        echo "You may want to use '$0 install' for a binary image instead, it's faster."
        build "${@:2}"
        ;;
    build_full)
        echo "You may want to use '$0 install_full' for a binary image instead, it's faster."
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
    shm_size)
        shm_size $2
        ;;
    stop)
        stop
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
    optimize)
        echo "Applying recommended dirty write settings..."
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
        dlblocks 
        ;;
    enter)
        enter
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
    ver)
        ver
        ;;
    *)
        echo "Invalid cmd"
        help
        ;;
esac

