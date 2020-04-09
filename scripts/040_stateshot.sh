#!/usr/bin/env bash
_XDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${_XDIR}/core.sh"
SIAB_LIB_LOADED[stateshot]=1 # Mark this library script as loaded successfully

siab_load_lib helpers config

: ${STATESHOT_BASE="https://se1.files.privex.io/hive/stateshots"}
: ${STATESHOT_INDEX="${STATESHOT_BASE}/state_index.txt"}
: ${STATESHOT_DEFAULT="hive-witness-seed"}

declare -A STATESHOTS

# stateshot-index (index_url)
# 
#   $ stateshot-index
#   $ stateshot-index https://se1.files.privex.io/hive/stateshots/state_index.txt
# 
stateshot-index() {
    local url="$STATESHOT_INDEX" state_list=() s=""

    (( $# > 0 )) && url="$1"

    _debug "[stateshot-index] loading url into state_list: $url"
    # read -ra state_list <<< "$(curl -fsSL "$url")"
    mapfile -t state_list < <(curl -fsSL "$url")
    for s in "${state_list[@]}"; do
        if [ -n "$s" ]; then
            # ss_out=$(mktemp)
            # curl -fsSL "${STATESHOT_BASE}/${s}" -o "$ss_out" > /dev/null
            # STATESHOTS[$s]="$ss_out"
            _debug "[stateshot-index] s not empty - calling 'stateshot-read $s'"
            stateshot-read "$s" >/dev/null
            echo "$s"
        fi
    done
}


# stateshot-read [statefilename]
# 
#   $ ss_contents="$(stateshot-read hive-witness-seed.sh)"
#   $ stateshot-read hive-witness-seed.sh | grep "DESCRIPTION"
#   Hive v0.23.0 low-memory + MIRA snapshot
#
stateshot-read() {
    local s="$1" ss_out
    set +u
    # If the requested stateshot filename isn't in the associative array, download it into a temp file
    # and map it in STATESHOTS to the temp file
    
    _debug "[stateshot-read] Checking if '$s' is in STATESHOTS"

    if [[ -v "STATESHOTS[$s]" ]]; then
        true
    else
        ss_out=$(add-tmpfile)
        curl -fsSL "${STATESHOT_BASE}/${s}" -o "$ss_out" > /dev/null
        _debug "[stateshot-read] Setting STATESHOTS[\"$s\"] to \"$ss_out\" "
        STATESHOTS+=( ["$s"]="$ss_out" )
    fi
    cat "${STATESHOTS[$s]}"
    set -u
}

# stateshot-has-key [var name] [stateshot filename]
# 
#   if stateshot-has-key "ACC_HIST_RDB" hive-acchist-lowmem; then
#       echo "hive-acchist-lowmem has the config key 'ACC_HIST_RDB'"
#   else
#       echo "hive-acchist-lowmem DOES NOT have the config key 'ACC_HIST_RDB'"
#   fi
#
stateshot-has-key() {
    local varname="$1" vardef="" sfile="$STATESHOT_DEFAULT"
    (( $# > 1 )) && sfile="$2"

    grep -qE "^${varname} ?= ?" "${STATESHOTS[$sfile]}"
}

# _get-stateshot-line [var name] [var default] [stateshot filename]
# 
#   $ _get-stateshot-line DESCRIPTION "no DESCRIPTION value set" hive-witness-seed.sh
#   Hive v0.23.0 low-memory + MIRA snapshot
#   $ _get-stateshot-line LOREMIPSUM "no LOREMIPSUM value set" hive-witness-seed.sh
#   no LOREMIPSUM value set
#
_get-stateshot-line() {
    local varname="$1" vardef="" sfile="$STATESHOT_DEFAULT"
    (( $# > 1 )) && vardef="$2"
    (( $# > 2 )) && sfile="$3"
    stateshot-read "$sfile" > /dev/null
    s_desc="$(extract-var-quoted "$varname" "${STATESHOTS[$sfile]}")"
    if [ -z "$s_desc" ]; then
        s_desc="$(extract-var-unquoted "$varname" "${STATESHOTS[$sfile]}")"
        if [ -z "$s_desc" ]; then
            echo "$vardef"
            return
        fi
    fi

    echo "$s_desc"
}

# get-stateshot-desc [statefilename]
# 
#   $ ss_desc="$(get-stateshot-desc hive-witness-seed.sh)"
#   $ echo "$ss_desc"
#   Hive v0.23.0 low-memory + MIRA snapshot
#
get-stateshot-desc() {
    local sfile="$STATESHOT_DEFAULT"; (( $# > 0 )) && sfile="$1"
    _get-stateshot-line DESCRIPTION " [ $sfile ] No description provided" "$sfile"
}

# get-stateshot-plugins [statefilename]
# 
#   $ ss_plugins="$(get-stateshot-plugins hive-witness-seed.sh)"
#   $ echo "$ss_plugins"
#   witness condenser_api network_broadcast_api rc_api account_by_key database_api
#
get-stateshot-plugins() {
    local sfile="$STATESHOT_DEFAULT"; (( $# > 0 )) && sfile="$1"
    _get-stateshot-line PLUGINS "witness condenser_api network_broadcast_api rc_api" "$sfile"
}

get-stateshot-image() {
    local sfile="$STATESHOT_DEFAULT"; (( $# > 0 )) && sfile="$1"
    _get-stateshot-line DK_IMAGE "someguy123/hive" "$sfile"
}

get-stateshot-blocksrc() {
    local sfile="$STATESHOT_DEFAULT"; (( $# > 0 )) && sfile="$1"
    _get-stateshot-line BLOCKS_SRC "" "$sfile"
}

get-stateshot-blockindex() {
    local sfile="$STATESHOT_DEFAULT"; (( $# > 0 )) && sfile="$1"
    _get-stateshot-line BLOCKS_INDEX "" "$sfile"
}

get-stateshot-blocksize() {
    local sfile="$STATESHOT_DEFAULT"; (( $# > 0 )) && sfile="$1"
    _get-stateshot-line BLOCKS_SIZE "" "$sfile"
}

get-stateshot-shmsrc() {
    local sfile="$STATESHOT_DEFAULT"; (( $# > 0 )) && sfile="$1"
    _get-stateshot-line SHM_SRC "" "$sfile"
}

get-stateshot-mira() {
    local sfile="$STATESHOT_DEFAULT"; (( $# > 0 )) && sfile="$1"
    _get-stateshot-line MIRA "1" "$sfile"
}

get-stateshot-lowmem() {
    local sfile="$STATESHOT_DEFAULT"; (( $# > 0 )) && sfile="$1"
    _get-stateshot-line LOW_MEMORY "1" "$sfile"
}

get-stateshot-acchist-rdb() {
    local sfile="$STATESHOT_DEFAULT"; (( $# > 0 )) && sfile="$1"
    _get-stateshot-line ACC_HIST_RDB "" "$sfile"
}

########
# extract-var-quoted [var] (file)
# Extract a quoted variable from an INI-like file, or stdin
#
#    $ echo 'DESCRIPTION="hello world"' > /tmp/test
#    $ extract-var-quoted DESCRIPTION /tmp/test
#    hello world
#    $ echo -e "ASDF=not quoted\nQWERTY=line two" | extract-var-quoted ASDF
#    $ echo -e "ASDF=\"quoted words\"\nQWERTY=line two" | extract-var-quoted ASDF
#    quoted words
#
extract-var-quoted() {
    if (( $# > 1 )); then
        sed -En "s/^$1 ?= ?\"(.*)\"/\1/p" "$2"
    else
        sed -En "s/^$1 ?= ?\"(.*)\"/\1/p"
    fi
}

########
# extract-var-unquoted [var] (file)
#
#    $ echo 'DESCRIPTION = hello world' > /tmp/test
#    $ extract-var-unquoted DESCRIPTION /tmp/test
#    hello world
#    $ echo -e "ASDF=not quoted\nQWERTY=line two" | extract-var-unquoted ASDF
#    not quoted
#    $ echo -e "ASDF=\"quoted words\"\nQWERTY=line two" | extract-var-unquoted ASDF
#    "quoted words"
#
extract-var-unquoted() {
    if (( $# > 1 )); then
        sed -En "s/^$1 ?= ?(.*)/\1/p" "$2"
    else
        sed -En "s/^$1 ?= ?(.*)/\1/p"
    fi
}

_stateshot_list() {
    local ss
    msg nots yellow "Available stateshots:\n"
    {
        for ss in "${!STATESHOTS[@]}"; do
            [ -z "$ss" ] && continue
            msg nots cyan "${ss} \tDescription: " "$(get-stateshot-desc "$ss")"
        done
    } | column -t -s $'\t'
    msg
    msg nots green "Please enter a stateshot filename to view more details and install it."
}

_stateshot-show() {
    local ss_select="$1"

    ss_desc=$(get-stateshot-desc "$ss_select") ss_image=$(get-stateshot-image "$ss_select")
    ss_plugins=$(get-stateshot-plugins "$ss_select") ss_lowmem=$(get-stateshot-lowmem "$ss_select")
    ss_mira=$(get-stateshot-mira "$ss_select") ss_blocksrc=$(get-stateshot-blocksrc "$ss_select")
    ss_blocksize=$(get-stateshot-blocksize "$ss_select") ss_blockindex=$(get-stateshot-blockindex "$ss_select")
    ss_shmsrc=$(get-stateshot-shmsrc "$ss_select")       ss_hist_rdb="$(get-stateshot-acchist-rdb "$ss_select")"

    msg
    msg cyan "Stateshot: $ss_select \n"
    msg cyan "     Description:               $ss_desc"
    msg cyan "     Docker Image:              $ss_image"
    if (( ss_mira == 1 )); then
        msg cyan "     MIRA:                      ${GREEN}YES"
    else
        msg cyan "     MIRA:                      ${RED}NO"
    fi
    if (( ss_lowmem == 1 )); then
        msg cyan "     Low Memory Mode:           ${GREEN}YES"
    else
        msg cyan "     Low Memory Mode:           ${RED}NO"
    fi
    msg cyan "     Plugins:                   $ss_plugins"
    msg cyan "     Block Log:                 $ss_blocksrc"
    msg cyan "     Block Log Size:            $ss_blocksize"
    msg cyan "     Block Index:               $ss_blockindex"
    msg cyan "     RocksDB/Shared Mem:        $ss_shmsrc"
    if stateshot-has-key "ACC_HIST_RDB" "$ss_select"; then
        msg cyan "     Account Hist (RocksDB):    $ss_hist_rdb"
    fi
}

detect-download-method() {
    if grep -Eq "^(http|https)://" <<< "$1"; then
        echo "http"
    elif grep -Eq "^(rsync://)|([a-z0-9-]+@.*:/.*)" <<< "$1"; then
        echo "rsync"
    else
        raise_error "${BOLD}${RED}Only rsync / http are supported! Could not detect download method for URL '$1'${RESET}" "${BASH_SOURCE[0]}" $LINENO
    fi
}

is_compressed() {
    local filename=$(basename -- "$1") extension
    extension="${filename##*.}"
    [[ "$extension" == "lz4" ]] || [[ "$extension" == "gz" ]] || [[ "$extension" == "bz2" ]]
}

# decompress [original_filename] [destination]
# 
#   curl -fsSL http://example.com/something.zip | decompress something.zip /tmp/something
#
decompress() {
    local orig_filename="$1" dest="$2"

    filename=$(basename -- "$orig_filename")
    extension="${filename##*.}"
    
    if [[ "$extension" == "lz4" ]]; then
        lz4 -v -d - "$dest"
    elif [[ "$extension" == "gz" ]]; then
        gunzip -v -d -c - > "$dest"
    elif [[ "$extension" == "bz2" ]]; then
        bzip2 -v -d -c > "$dest"
    else
        pv | dd of="$dest" oflag=direct
    fi
}

_dlfile() {
    local url="$1" dest="${BC_FOLDER}/block_log" append=0 dl_meth
    (( $# > 1 )) && dest="$2"
    (( $# > 2 )) && append=$(($3))

    msg green " [...] Downloading file from URL: '$url' ..."
    msg green " [...] Outputting to: '$dest' ..."

    dl_meth=$(detect-download-method "$url")

    if [[ "$dl_meth" == "http" ]]; then
        if is_compressed "$url"; then
            msg ts green " [...] Downloading file via HTTP using on-the-fly decompression ..."
            curl -fsSL "$url" | decompress "$url" "$dest"
        else
            msg ts green " [...] Downloading file via HTTP (no compression) ..."
            curl --progress-bar -SL "$url" -o "$dest"
        fi
    elif [[ "$dl_meth" == "rsync" ]]; then
        if (( append == 1 )); then
            msg ts green " [...] Downloading file via Rsync (append mode) ..."
            rsync -Ivh --progress --append "$url" "$dest"
        else
            msg ts green " [...] Downloading file via Rsync (inplace mode) ..."
            rsync -Ivh --progress --inplace "$url" "$dest"
        fi
    fi

}



install-stateshot() {
    MSG_TS_DEFAULT=0
    local ss_index="$STATESHOT_INDEX" ss_select
    (( $# > 0 )) && ss_index="$1"

    msg green " >>> Loading stateshot index from URL: $ss_index \n"

    declare -A STATESHOTS
    stateshot-index "$ss_index" > /dev/null

    while true; do
        _stateshot_list
        msg
        read -p "${MAGENTA}Enter a stateshot filename (e.g. hive-witness-seed.sh)${RESET} > " ss_select
        if [ -z "$ss_select" ] || [ -z ${STATESHOTS[$ss_select]+x} ]; then
            msgerr red "\n !!! Please enter a valid selection from the stateshot list.\n"
        else
            msg green "Selected stateshot: $ss_select"
            break
        fi
    done

    _stateshot-show "$ss_select"

    msg
    if yesno "${MAGENTA}Do you want to install this stateshot?${RESET} (y/n) > "; then
        msg
        msg purple " [...] Adjusting your plugins in config: $CONFIG_FILE"
        config_set "plugin" "$ss_plugins"
        msg
        msg purple " [...] Installing docker image: $ss_image"
        install "$ss_image"
        msg

        local_bl="${BC_FOLDER}/block_log"
        local_bsz=$(local-file-size "$local_bl")

        msg purple " [...] Comparing your local block_log '$local_bl' against the server's copy ...\n"

        if (( local_bsz > ss_blocksize )); then
            msg green " [...] Trimming local block_log down to $ss_blocksize bytes..."
            truncate -s "$ss_blocksize" "$local_bl"
            msg green " [+++] Truncated block_log down to $ss_blocksize bytes."
        elif (( local_bsz < ss_blocksize )); then
            msg bold green " [...] Downloading block_log from '${ss_blocksrc}' into: ${local_bl} ... \n"
            _dlfile "$ss_blocksrc" "$local_bl" 1
            # rsync -Ivh --progress --append "$BC_RSYNC" "$local_bl"
            msg bold green "\n [+++] Finished downloading block_log\n"

            msg purple " [...] Checking if '$local_bl' requires truncation for snapshot usage ...\n"
            local_bsz=$(local-file-size "$local_bl")
            if (( local_bsz > ss_blocksize )); then
                msg green " [...] Trimming local block_log down from $local_bsz to $ss_blocksize bytes...\n"
                truncate -s "$ss_blocksize" "$local_bl"
                msg green "\n [+++] Truncated block_log down to $ss_blocksize bytes.\n"
            else
                msg green " [+++] Local block log is $local_bsz - matches server requested size $ss_blocksize - no truncation needed"
            fi
        else
            msg nots yellow " >> It appears your local block_log is the same size as the remote block_log at $BC_HTTP_RAW \n"
            msg nots yellow " >> Assuming that your block_log is already correct. Moving onto next download."
        fi
        
        msg

        msg bold green " [...] Downloading block_log.index from '${ss_blockindex}' into: ${local_bl}.index ... \n"
        _dlfile "$ss_blockindex" "${local_bl}.index" 0

        msg bold green "\n [...] Downloading chain state files (shared_memory / rocksdb) from '${ss_shmsrc}' into: ${SHM_DIR} ... \n"
        rsync -Irvh --delete --inplace --progress "$ss_shmsrc" "${SHM_DIR}/"

        if stateshot-has-key "ACC_HIST_RDB" "$ss_select"; then
            msg bold green "\n [...] Downloading RocksDB account history from '${ss_hist_rdb}' into: ${BC_FOLDER}/account-history-rocksdb-storage/ ... \n"
            rsync -Irvh --delete --inplace --progress "${ss_hist_rdb}" "${BC_FOLDER}/account-history-rocksdb-storage/"
        fi
        msg
        msg bold green "\n [+++] Finished setting up StateShot '$ss_select' "
        msg bold green "\n [+++] Please make sure to check your config file for any errors at: $CONFIG_FILE "
        msg bold green "\n [+++] Start the Steem/Hive node by running './run.sh start' \n"

    else
        install-stateshot "$@"
        return $?
    fi

}

