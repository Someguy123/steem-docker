#!/bin/bash
#
# Steem node manager
# Released under GNU AGPL by Someguy123
#

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOCKER_DIR="$DIR/dkr"
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



help() {
    echo "Usage: $0 COMMAND [DATA]"
    echo
    echo "Commands: "
    echo "    start - starts seed"
    echo "    stop - stops seed"
    echo "    status - show status of seed container"
    echo "    restart - restarts seed"
    echo "    rebuild - builds seed, and then restarts it"
    echo "    build - only builds seed"
    echo "    logs - show all logs inc. docker logs, and steem logs"
    echo "    wallet - open cli_wallet in the container"
    echo "    enter - enter a bash session in the container"
    echo
    exit
}

build() {
    echo $GREEN"Building docker container"$RESET
    cd $DOCKER_DIR
    docker build -t steem .
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
        docker run -p 0.0.0.0:2001:2001 -v "$DATADIR":/steem -d --name $DOCKER_NAME -t steem
    fi
}

stop() {
    echo $RED"Stopping container..."$RESET
    docker stop seed
}

enter() {
    docker exec -it $DOCKER_NAME bash
}

wallet() {
    docker exec -it $DOCKER_NAME cli_wallet
}

logs() {
    echo $BLUE"DOCKER LOGS: "$RESET
    docker logs --tail=20 $DOCKER_NAME
    echo $RED"INFO AND DEBUG LOGS: "$RESET
    tail -n 30 $DATADIR/{info.log,debug.log}
}

status() {
    
    seed_exists
    if [[ $? == 0 ]]; then
        echo "Container exists?: "$GREEN"YES"$RESET
    else
        echo "Container exists?: "$RED"NO (!)"$RESET 
        echo "Container doesn't exist, thus it is NOT running. Run $0 build && $0 start"$RESET
        return
    fi

    seed_running
    if [[ $? == 0 ]]; then
        echo "Container running?: "$GREEN"YES"$RESET
    else
        echo "Container running?: "$RED"NO (!)"$RESET
        echo "Container isn't running. Start it with $0 start"$RESET
        return
    fi

}

if [ "$#" -ne 1 ]; then
    help
fi

case $1 in
    build)
        build
        ;;
    start)
        start
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
    status)
        status
        ;;
    wallet)
        wallet
        ;;
    enter)
        enter
        ;;
    logs)
        logs
        ;;
    *)
        echo "Invalid cmd"
        help
        ;;
esac
