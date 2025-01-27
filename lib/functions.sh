#!/bin/bash
# vim: set filetype=sh ts=4 sw=4 et

# functions.sh - common functions and variables

# Copyright (c) 2015-2017 moocowmoo
# Copyright (c) 2017 dasource

# variables are for putting things in ----------------------------------------

C_RED="\e[31m"
C_YELLOW="\e[33m"
C_GREEN="\e[32m"
C_PURPLE="\e[35m"
C_CYAN="\e[36m"
C_NORM="\e[0m"

LC_NUMERIC="en_US.UTF-8"

PARTYD_RUNNING=0
PARTYD_RESPONDING=0
PARTYMAN_VERSION=$(cat "$PARTYMAN_GITDIR/VERSION")
DATA_DIR="$HOME/.rhombus"
DOWNLOAD_PAGE="https://github.com/rhombus/rhombus-core/releases"
#PARTYMAN_CHECKOUT=$(GIT_DIR=$PARTYMAN_GITDIR/.git GIT_WORK_TREE=$PARTYMAN_GITDIR git describe --dirty | sed -e "s/^.*-\([0-9]\+-g\)/\1/" )
#if [ "$PARTYMAN_CHECKOUT" == "v"$PARTYMAN_VERSION ]; then
#    PARTYMAN_CHECKOUT=""
#else
#    PARTYMAN_CHECKOUT=" ("$PARTYMAN_CHECKOUT")"
#fi

curl_cmd="timeout 7 curl -4 -s -L -A rhomtools/$PARTYMAN_VERSION"
wget_cmd='wget -4 --no-check-certificate -q'


# (mostly) functioning functions -- lots of refactoring to do ----------------

pending(){ [[ $QUIET ]] || ( echo -en "$C_YELLOW$1$C_NORM" && tput el ); }

ok(){ [[ $QUIET ]] || echo -e "$C_GREEN$1$C_NORM" ; }

warn() { [[ $QUIET ]] || echo -e "$C_YELLOW$1$C_NORM" ; }
highlight() { [[ $QUIET ]] || echo -e "$C_PURPLE$1$C_NORM" ; }

err() { [[ $QUIET ]] || echo -e "$C_RED$1$C_NORM" ; }
die() { [[ $QUIET ]] || echo -e "$C_RED$1$C_NORM" ; exit 1 ; }

quit(){ [[ $QUIET ]] || echo -e "$C_GREEN${1:-${messages["exiting"]}}$C_NORM" ; echo ; exit 0 ; }

confirm() { read -r -p "$(echo -e "${1:-${messages["prompt_are_you_sure"]} [y/N]}")" ; [[ ${REPLY:0:1} = [Yy] ]]; }


up()     { echo -e "\e[${1:-1}A"; }
clear_n_lines(){ for n in $(seq "${1:-1}") ; do tput cuu 1; tput el; done ; }


usage(){
    cat<<EOF



    ${messages["usage"]}: ${0##*/} [command]

        ${messages["usage_title"]}

    ${messages["commands"]}

        install

            ${messages["usage_install_description"]}

        update

            ${messages["usage_update_description"]}

        reinstall

            ${messages["usage_reinstall_description"]}

        restart [now]

            ${messages["usage_restart_description"]}
                banlist.dat
                peers.dat

            ${messages["usage_restart_description_now"]}

        stakingnode [init, new, info, stats, rewardaddress, smsgfeeratetarget]

            ${messages["usage_stakingnode_description"]}
            ${messages["usage_stakingnode_init_description"]}
            ${messages["usage_stakingnode_new_description"]}
            ${messages["usage_stakingnode_info_description"]}
            ${messages["usage_stakingnode_stats_description"]}
            ${messages["usage_stakingnode_rewardaddress_description"]}
            ${messages["usage_stakingnode_smsgfeeratetarget_description"]}

        status

            ${messages["usage_status_description"]}

        firewall [reset]

            ${messages["usage_firewall_description"]}
            ${messages["usage_firewall_reset"]}

        version

            ${messages["usage_version_description"]}

EOF
}

_check_dependencies() {

    INSTALL=install
    PYTHON=$( (type -P python 2>/dev/null) || (type -P python3 2>/dev/null))

    if [ -n "$PYTHON" ]; then
        DISTRO=$(/usr/bin/env "$PYTHON" -mplatform | sed -e 's/.*with-//g')
        if [[ $DISTRO == *"Ubuntu"* ]] || [[ $DISTRO == *"debian"* ]]; then
            PKG_MANAGER=apt-get
        elif [[ $DISTRO == *"centos"* ]]; then
            PKG_MANAGER=yum
        elif [[ $DISTRO == *"arch"* ]]; then
            PKG_MANAGER=pacman
        elif [[ $DISTRO == *"gentoo"* ]]; then
            PKG_MANAGER=emerge
            INSTALL=
        fi
    else
        echo -e "${C_RED}warning ${messages["no_python_fallback"]}$C_NORM"
        PKG_MANAGER=$( (type -P apt-get 2>/dev/null) \
                      || (type -P yum 2>/dev/null) \
                      || (type -P pacman 2>/dev/null) \
                      || (type -P emerge 2>/dev/null))
    fi

    if [[ $PKG_MANAGER == *"pacman" ]]; then
        INSTALL=-S
    elif [[ $PKG_MANAGER == *"emerge" ]]; then
        INSTALL=
    fi


    (type -P curl 2>&1) >/dev/null || MISSING_DEPENDENCIES="${MISSING_DEPENDENCIES}curl "
    (type -P perl 2>&1) >/dev/null || MISSING_DEPENDENCIES="${MISSING_DEPENDENCIES}perl "
    (type -P git  2>&1) >/dev/null || MISSING_DEPENDENCIES="${MISSING_DEPENDENCIES}git "
    (type -P jq   2>&1) >/dev/null || MISSING_DEPENDENCIES="${MISSING_DEPENDENCIES}jq "
    (type -P dig  2>&1) >/dev/null || MISSING_DEPENDENCIES="${MISSING_DEPENDENCIES}dnsutils "
    (type -P wget 2>&1) >/dev/null || MISSING_DEPENDENCIES="${MISSING_DEPENDENCIES}wget "

    if [ "$1" == "install" ]; then
        # only require unzip for install
        (type -P unzip 2>&1) >/dev/null || MISSING_DEPENDENCIES="${MISSING_DEPENDENCIES}unzip "
        (type -P pv   2>&1) >/dev/null || MISSING_DEPENDENCIES="${MISSING_DEPENDENCIES}pv "
    fi

    if [ "$1" == "firewall" ]; then
        # only require for firewall
        (type -P ufw  2>&1) >/dev/null || MISSING_DEPENDENCIES="${MISSING_DEPENDENCIES}ufw "
        FIREWALL_CLI="sudo ufw"
    fi

    # make sure we have the right netcat version (-4,-6 flags)
    if [ -n "$(type -P nc)" ]; then

        if ! (nc -z -4 8.8.8.8 53 2>&1) >/dev/null
        then
            MISSING_DEPENDENCIES="${MISSING_DEPENDENCIES}netcat6 "
        fi
    else
        MISSING_DEPENDENCIES="${MISSING_DEPENDENCIES}netcat "
    fi

    if [ -n "$MISSING_DEPENDENCIES" ]; then
        err "${messages["err_missing_dependency"]} $MISSING_DEPENDENCIES\n"
        if [ -z "$PKG_MANAGER" ]; then
            die "${messages["err_no_pkg_mgr"]}"
        fi
        # shellcheck disable=SC2086
        if ! sudo "$PKG_MANAGER" "$INSTALL" $MISSING_DEPENDENCIES; then
            die "${messages["err_no_pkg_mgr_install_failed"]}"
        fi
    fi
}

# attempt to locate rhombus-cli executable.
# search current dir, ~/.rhombus, `which rhombus-cli` ($PATH), finally recursive
_find_rhombus_directory() {

    INSTALL_DIR=''

    # rhombus-cli in PATH

    if [ -n "$(type -P rhombus-cli 2>/dev/null)" ] ; then
        INSTALL_DIR=$(readlink -f "$(type -P rhombus-cli)")
        INSTALL_DIR=${INSTALL_DIR%%/rhombus-cli*};

        #TODO prompt for single-user or multi-user install

        # if copied to /usr/*
        if [[ $INSTALL_DIR =~ \/usr.* ]]; then
            LINK_TO_SYSTEM_DIR=$INSTALL_DIR

            # if not run as root
            if [ $EUID -ne 0 ] ; then
                die "\n${messages["exec_found_in_system_dir"]} $INSTALL_DIR${messages["run_rhomtools_as_root"]} ${messages["exiting"]}"
            fi
        fi

    # rhombus-cli not in PATH

        # check current directory
    elif [ -e ./rhombus-cli ] ; then
        INSTALL_DIR='.' ;

        # check ~/.rhombus directory
    elif [ -e "$HOME/.rhombus/rhombus-cli" ] ; then
        INSTALL_DIR="$HOME/.rhombus" ;

    elif [ -e "$HOME/rhombuscore/rhombus-cli" ] ; then
        INSTALL_DIR="$HOME/rhombuscore" ;
    fi

    if [ -n "$INSTALL_DIR" ]; then
        INSTALL_DIR=$(readlink -f "$INSTALL_DIR") 2>/dev/null
        if [ ! -e "$INSTALL_DIR" ]; then
            echo -e "${C_RED}${messages["rhombuscli_not_found_in_cwd"]}, ~/rhombuscore, or \$PATH. -- ${messages["exiting"]}$C_NORM"
            exit 1
        fi
    else
        echo -e "${C_RED}${messages["rhombuscli_not_found_in_cwd"]}, ~/rhombuscore, or \$PATH. -- ${messages["exiting"]}$C_NORM"
        exit 1
    fi

    RHOM_CLI="$INSTALL_DIR/rhombus-cli"

    # check INSTALL_DIR has rhombusd and rhombus-cli
    if [ ! -e "$INSTALL_DIR/rhombusd" ]; then
        echo -e "${C_RED}${messages["rhombusd_not_found"]} $INSTALL_DIR -- ${messages["exiting"]}$C_NORM"
        exit 1
    fi

    if [ ! -e "$RHOM_CLI" ]; then
        echo -e "${C_RED}${messages["rhombuscli_not_found"]} $INSTALL_DIR -- ${messages["exiting"]}$C_NORM"
        exit 1
    fi

}


_check_rhomtools_updates() {
    GITHUB_PARTYMAN_VERSION=$( "$curl_cmd" -i https://raw.githubusercontent.com/dasource/rhomtools/master/VERSION 2>/dev/null | head -n 1 | cut -d$' ' -f2 )
    if [ "$GITHUB_PARTYMAN_VERSION" == 200 ]; then # check to make sure github is returning the data
        GITHUB_PARTYMAN_VERSION=$( $curl_cmd https://raw.githubusercontent.com/dasource/rhomtools/master/VERSION 2>/dev/null )
        if [ -n "$GITHUB_PARTYMAN_VERSION" ] && [ "$PARTYMAN_VERSION" != "$GITHUB_PARTYMAN_VERSION" ]; then
            echo -e "\n"
            echo -e "${C_RED}${0##*/} ${messages["requires_updating"]} $C_GREEN$GITHUB_PARTYMAN_VERSION$C_RED\n${messages["requires_sync"]}$C_NORM\n"

            die "${messages["exiting"]}"
        fi
    else
        GITHUB_PARTYMAN_VERSION=$PARTYMAN_VERSION # force to local version during github issues
    fi
}

_get_platform_info() {
    PLATFORM=$(uname -m)
    case "$PLATFORM" in
        i[3-6]86)
            BITS=32
            ARM=0
            ARCH='i686-pc-linux-gnu'
            QRCODE_ARCH='386'
            ;;
        x86_64)
            BITS=64
            ARM=0
            ARCH='x86_64-linux-gnu'
            QRCODE_ARCH='amd64'
            ;;
        armv7l)
            BITS=32
            ARM=1
            BIGARM=$(grep -Ec "(BCM2709|Freescale i\\.MX6)" /proc/cpuinfo)
            ARCH='arm-linux-gnueabihf'
            QRCODE_ARCH='arm'
            ;;
        aarch64)
            BITS=64
            ARM=1
            BIGARM=$(grep -Ec "(BCM2709|Freescale i\\.MX6)" /proc/cpuinfo)
            ARCH='aarch64-linux-gnu'
            QRCODE_ARCH='arm'
            ;;
        *)
            err "${messages["err_unknown_platform"]} $PLATFORM"
            err "${messages["err_rhomtools_supports"]}"
            die "${messages["exiting"]}"
            ;;
    esac
}

_get_versions() {
    _get_platform_info

    if [ -z "$RHOM_CLI" ]; then RHOM_CLI='echo'; fi
    CURRENT_VERSION=$( $RHOM_CLI --version | grep -m1 Rhombus | sed 's/\Rhombus Core RPC client version v//g' | sed 's/\.[^.]*$//' 2>/dev/null ) 2>/dev/null

    unset LATEST_VERSION
    LVCOUNTER=0
    RELEASES=$( $curl_cmd https://api.github.com/repos/rhombus/rhombus-core/releases )
    while [ -z "$LATEST_VERSION" ] && [ $LVCOUNTER -lt 5 ]; do
        RELEASE=$( echo "$RELEASES" | jq -r .[$LVCOUNTER] 2>/dev/null )
        PR=$( echo "$RELEASE" | jq .prerelease)
        if [ "$PR" == "false" ] || [ "$PRER" == 1 ]; then
            LATEST_VERSION=$( echo "$RELEASE" | jq -r .tag_name | sed 's/v//g')
        else
            (( LVCOUNTER=LVCOUNTER+1 ))
        fi
    done

    if [ -z "$LATEST_VERSION" ] && [ "$COMMAND" == "install" ]; then
        die "\n${messages["err_could_not_get_version"]} $DOWNLOAD_PAGE -- ${messages["exiting"]}"
    fi

    DOWNLOAD_URL="https://github.com/rhombus/rhombus-core/releases/download/v${LATEST_VERSION}/rhombus-${LATEST_VERSION}-${ARCH}.tar.gz"
    DOWNLOAD_FILE="rhombus-${LATEST_VERSION}-${ARCH}.tar.gz"

}

_check_rhombusd_state() {
    _get_rhombusd_proc_status
    PARTYD_RUNNING=0
    PARTYD_RESPONDING=0
    if [ "$PARTYD_HASPID" -gt 0 ] && [ "$PARTYD_PID" -gt 0 ]; then
        PARTYD_RUNNING=1
    fi
    if [ "$( $RHOM_CLI help 2>/dev/null | wc -l )" -gt 0 ]; then
        PARTYD_RESPONDING=1
        PARTYD_WALLETSTATUS=$( "$RHOM_CLI" getwalletinfo | jq -r .encryptionstatus )
        PARTYD_WALLET=$( "$RHOM_CLI" getwalletinfo | jq -r .hdmasterkeyid )
        if [ "$PARTYD_WALLET"  == "null" ]; then
            PARTYD_WALLET=$( "$RHOM_CLI" getwalletinfo | jq -r .hdseedid )
        fi
        PARTYD_TBALANCE=$( "$RHOM_CLI" getwalletinfo | jq -r .total_balance )
    fi
}

restart_rhombusd(){

    if [ "$PARTYD_RUNNING" == 1 ]; then
        pending " --> ${messages["stopping"]} rhombusd. ${messages["please_wait"]}"
        $RHOM_CLI stop > /dev/null 2>&1
        sleep 15
        killall -9 rhombusd rhombus-shutoff 2>/dev/null
        ok "${messages["done"]}"
        PARTYD_RUNNING=0
    fi

    pending " --> ${messages["deleting_cache_files"]} $DATA_DIR/ "

    cd "$INSTALL_DIR" || exit

    #rm -rf \
    #    "$DATA_DIR"/banlist.dat \
    #    "$DATA_DIR"/peers.dat
    ok "${messages["done"]}"

    pending " --> ${messages["starting_rhombusd"]}"
    "$INSTALL_DIR/rhombusd" -daemon > /dev/null 2>&1
    PARTYD_RUNNING=1
    PARTYD_RESPONDING=0
    ok "${messages["done"]}"

    pending " --> ${messages["waiting_for_rhombusd_to_respond"]}"
    echo -en "${C_YELLOW}"
    while [ $PARTYD_RUNNING == 1 ] && [ $PARTYD_RESPONDING == 0 ]; do
        echo -n "."
        _check_rhombusd_state
        sleep 5
    done
    if [ $PARTYD_RUNNING == 0 ]; then
        die "\n - rhombusd unexpectedly quit. ${messages["exiting"]}"
    fi
    ok "${messages["done"]}"
    pending " --> rhombus-cli getinfo"
    echo
    $RHOM_CLI -getinfo
    echo

}

install_rhombusd(){

    INSTALL_DIR=$HOME/rhombuscore
    RHOM_CLI="$INSTALL_DIR/rhombus-cli"

    if [ -e "$INSTALL_DIR" ] ; then
        die "\n - ${messages["preexisting_dir"]} $INSTALL_DIR ${messages["found"]} ${messages["run_reinstall"]} ${messages["exiting"]}"
    fi

    if [ -z "$UNATTENDED" ] ; then
        if [ "$USER" != "rhombus" ]; then
            echo
            warn "We strongly advise you run this installer under user \"rhombus\" with sudo access. Are you sure you wish to continue as $USER?"
            if ! confirm " [${C_GREEN}y${C_NORM}/${C_RED}N${C_NORM}] $C_CYAN"; then
                echo -e "${C_RED}${messages["exiting"]}$C_NORM"
                echo ""
                exit 0
            fi
        fi
        pending "${messages["download"]} $DOWNLOAD_URL\n${messages["and_install_to"]} $INSTALL_DIR?"
    else
        echo -e "$C_GREEN*** UNATTENDED MODE ***$C_NORM"
    fi

    if [ -z "$UNATTENDED" ] ; then
        if ! confirm " [${C_GREEN}y${C_NORM}/${C_RED}N${C_NORM}] $C_CYAN"; then
            echo -e "${C_RED}${messages["exiting"]}$C_NORM"
            echo ""
            exit 0
        fi
    fi

    get_public_ips
    echo ""

    # prep it ----------------------------------------------------------------

    mkdir -p "$INSTALL_DIR"
    mkdir -p "$DATA_DIR"

    if [ ! -e "$DATA_DIR/rhombus.conf" ] ; then
        pending " --> ${messages["creating"]} $DATA_DIR/rhombus.conf... "

        while read -r; do
            eval echo "$REPLY"
        done < "$PARTYMAN_GITDIR/rhombus.conf.template" > "$DATA_DIR/rhombus.conf"
        ok "${messages["done"]}"
    fi

    # push it ----------------------------------------------------------------

    cd "$INSTALL_DIR" || exit

    # pull it ----------------------------------------------------------------

    pending " --> ${messages["downloading"]} ${DOWNLOAD_URL}... "
    tput sc
    echo -e "$C_CYAN"
    $wget_cmd -O - "$DOWNLOAD_URL" | pv -trep -s27M -w80 -N wallet > "$DOWNLOAD_FILE"
    $wget_cmd -O - "https://raw.githubusercontent.com/rhombus/gitian.sigs/master/${LATEST_VERSION}-linux/tecnovert/rhombus-linux-${LATEST_VERSION}-build.assert" | pv -trep -w80 -N checksums > "${DOWNLOAD_FILE}.DIGESTS.txt"
    echo -ne "$C_NORM"
    clear_n_lines 2
    tput rc
    clear_n_lines 3
    if [ ! -e "$DOWNLOAD_FILE" ] ; then
        echo -e "${C_RED}error ${messages["downloading"]} file"
        echo -e "tried to get $DOWNLOAD_URL$C_NORM"
        exit 1
    else
        ok "${messages["done"]}"
    fi

    # prove it ---------------------------------------------------------------

    pending " --> ${messages["checksumming"]} ${DOWNLOAD_FILE}... "
    SHA256SUM=$( sha256sum "$DOWNLOAD_FILE" )
    SHA256PASS=$( grep -c "$SHA256SUM" "${DOWNLOAD_FILE}.DIGESTS.txt" )
    if [ "$SHA256PASS" -lt 1 ] ; then
        $wget_cmd -O - https://api.github.com/repos/rhombus/rhombus-core/releases | jq -r .[$LVCOUNTER] | jq .body > "${DOWNLOAD_FILE}.DIGESTS2.txt"
        SHA256DLPASS=$( grep -c "$SHA256SUM" "${DOWNLOAD_FILE}.DIGESTS2.txt" )
        if [ "$SHA256DLPASS" -lt 1 ] ; then
            echo -e " ${C_RED} SHA256 ${messages["checksum"]} ${messages["FAILED"]} ${messages["try_again_later"]} ${messages["exiting"]}$C_NORM"
            exit 1
        fi
    fi
    ok "${messages["done"]}"

    # produce it -------------------------------------------------------------

    pending " --> ${messages["unpacking"]} ${DOWNLOAD_FILE}... " && \
    tar zxf "$DOWNLOAD_FILE" && \
    ok "${messages["done"]}"

    # pummel it --------------------------------------------------------------

    if [ $PARTYD_RUNNING == 1 ]; then
        pending " --> ${messages["stopping"]} partcld. ${messages["please_wait"]}"
        $RHOM_CLI stop >/dev/null 2>&1
        sleep 15
        killall -9 rhombusd rhombus-shutoff >/dev/null 2>&1
        ok "${messages["done"]}"
    fi

    # place it ---------------------------------------------------------------

    mv "rhombus-$LATEST_VERSION/bin/rhombusd" "rhombusd-$LATEST_VERSION"
    mv "rhombus-$LATEST_VERSION/bin/rhombus-cli" "rhombus-cli-$LATEST_VERSION"
    if [ $ARM != 1 ];then
        mv "rhombus-$LATEST_VERSION/bin/rhombus-qt" "rhombus-qt-$LATEST_VERSION"
    fi
    ln -s "rhombusd-$LATEST_VERSION" rhombusd
    ln -s "rhombus-cli-$LATEST_VERSION" rhombus-cli
    if [ $ARM != 1 ];then
        ln -s "rhombus-qt-$LATEST_VERSION" rhombus-qt
    fi

    # permission it ----------------------------------------------------------

    if [ -n "$SUDO_USER" ]; then
        chown -h "$USER":"$USER" {"$DOWNLOAD_FILE","${DOWNLOAD_FILE}.DIGESTS.txt",rhombus-cli,rhombusd,rhombus-qt,rhombus*"$LATEST_VERSION"}
    fi

    # purge it ---------------------------------------------------------------

    rm -rf "rhombus-$LATEST_VERSION"

    # path it ----------------------------------------------------------------

    pending " --> adding $INSTALL_DIR PATH to ~/.bash_aliases ... "
    if [ ! -f ~/.bash_aliases ]; then touch ~/.bash_aliases ; fi
    sed -i.bak -e '/rhomtools_env/d' ~/.bash_aliases
    echo "export PATH=$INSTALL_DIR:\$PATH; # rhomtools_env" >> ~/.bash_aliases
    ok "${messages["done"]}"

    # autoboot it ------------------------------------------------------------

    INIT=$(ps --no-headers -o comm 1)
    if [ "$INIT" == "systemd" ] && [ "$USER" == "rhombus" ] && [ -n "$SUDO_USER" ]; then
        pending " --> detecting $INIT for auto boot ($USER) ... "
        ok "${messages["done"]}"
        DOWNLOAD_SERVICE="https://raw.githubusercontent.com/rhombus/rhombus-core/master/contrib/init/rhombusd.service"
        pending " --> [systemd] ${messages["downloading"]} ${DOWNLOAD_SERVICE}... "
        $wget_cmd -O - $DOWNLOAD_SERVICE | pv -trep -w80 -N service > rhombusd.service
        if [ ! -e rhombusd.service ] ; then
           echo -e "${C_RED}error ${messages["downloading"]} file"
           echo -e "tried to get rhombusd.service$C_NORM"
        else
           ok "${messages["done"]}"
        pending " --> [systemd] installing service ... "
        if sudo cp -rf rhombusd.service /etc/systemd/system/; then
            ok "${messages["done"]}"
        fi
           pending " --> [systemd] reloading systemd service ... "
        if sudo systemctl daemon-reload; then
            ok "${messages["done"]}"
        fi
           pending " --> [systemd] enable rhombusd system startup ... "
        if sudo systemctl enable rhombusd; then
               ok "${messages["done"]}"
           fi
        fi
    fi

    # poll it ----------------------------------------------------------------

    _get_versions

    # pass or punt -----------------------------------------------------------

    if [ "$LATEST_VERSION" == "$CURRENT_VERSION" ]; then
        echo -e ""
        echo -e "${C_GREEN}Rhombus ${LATEST_VERSION} ${messages["successfully_installed"]}$C_NORM"

        echo -e ""
        echo -e "${C_GREEN}${messages["installed_in"]} ${INSTALL_DIR}$C_NORM"
        echo -e ""
        ls -l --color {"$DOWNLOAD_FILE","${DOWNLOAD_FILE}.DIGESTS.txt",rhombus-cli,rhombusd,rhombus-qt,rhombus*"$LATEST_VERSION"}
        echo -e ""

        if [ -n "$SUDO_USER" ]; then
            echo -e "${C_GREEN}Symlinked to: ${LINK_TO_SYSTEM_DIR}$C_NORM"
            echo -e ""
            ls -l --color "$LINK_TO_SYSTEM_DIR"/{rhombusd,rhombus-cli}
            echo -e ""
        fi

    else
        echo -e "${C_RED}${messages["rhombus_version"]} $CURRENT_VERSION ${messages["is_not_uptodate"]} ($LATEST_VERSION) ${messages["exiting"]}$C_NORM"
        exit 1
    fi
}

update_rhombusd(){

    if [ "$LATEST_VERSION" != "$CURRENT_VERSION" ] || [ -n "$REINSTALL" ] ; then

        if [ -n "$REINSTALL" ];then
            echo -e ""
            echo -e "$C_GREEN*** ${messages["rhombus_version"]} $CURRENT_VERSION is up-to-date. ***$C_NORM"
            echo -e "${messages["latest_version"]} $C_GREEN$LATEST_VERSION$C_NORM"
            echo -e ""
            echo -en

            pending "${messages["reinstall_to"]} $INSTALL_DIR$C_NORM?"
        else
            echo -e ""
            echo -e "$C_RED*** ${messages["newer_rhombus_available"]} ***$C_NORM"
            echo -e ""
            echo -e "${messages["currnt_version"]} $C_RED$CURRENT_VERSION$C_NORM"
            echo -e "${messages["latest_version"]} $C_GREEN$LATEST_VERSION$C_NORM"
            echo -e ""
            if [ -z "$UNATTENDED" ] ; then
                pending "${messages["download"]} $DOWNLOAD_URL\n${messages["and_install_to"]} $INSTALL_DIR?"
            else
                echo -e "$C_GREEN*** UNATTENDED MODE ***$C_NORM"
            fi
        fi


        if [ -z "$UNATTENDED" ] ; then
            if ! confirm " [${C_GREEN}y${C_NORM}/${C_RED}N${C_NORM}] $C_CYAN"; then
                echo -e "${C_RED}${messages["exiting"]}$C_NORM"
                echo ""
                exit 0
            fi
        fi

        # push it ----------------------------------------------------------------

        cd "$INSTALL_DIR" || exit

        # pull it ----------------------------------------------------------------

        pending " --> ${messages["downloading"]} ${DOWNLOAD_URL}... "
        tput sc
        echo -e "$C_CYAN"
        $wget_cmd -O - "$DOWNLOAD_URL" | pv -trep -s27M -w80 -N wallet > "$DOWNLOAD_FILE"
        $wget_cmd -O - "https://raw.githubusercontent.com/rhombus/gitian.sigs/master/$LATEST_VERSION.0-linux/tecnovert/rhombus-linux-$LATEST_VERSION-build.assert" | pv -trep -w80 -N checksums > "${DOWNLOAD_FILE}.DIGESTS.txt"
        echo -ne "$C_NORM"
        clear_n_lines 2
        tput rc
        clear_n_lines 3
        if [ ! -e "$DOWNLOAD_FILE" ] ; then
            echo -e "${C_RED}error ${messages["downloading"]} file"
            echo -e "tried to get $DOWNLOAD_URL$C_NORM"
            exit 1
        else
            ok "${messages["done"]}"
        fi

        # prove it ---------------------------------------------------------------

        pending " --> ${messages["checksumming"]} ${DOWNLOAD_FILE}... "
        SHA256SUM=$( sha256sum "$DOWNLOAD_FILE" )
        SHA256PASS=$( grep -c "$SHA256SUM" "${DOWNLOAD_FILE}.DIGESTS.txt" )
        if [ "$SHA256PASS" -lt 1 ] ; then
            $wget_cmd -O - https://api.github.com/repos/rhombus/rhombus-core/releases | jq -r .[$LVCOUNTER] | jq .body > "${DOWNLOAD_FILE}.DIGESTS2.txt"
            SHA256DLPASS=$( grep -c "$SHA256SUM" "${DOWNLOAD_FILE}.DIGESTS2.txt")
            if [ "$SHA256DLPASS" -lt 1 ] ; then
                echo -e " ${C_RED} SHA256 ${messages["checksum"]} ${messages["FAILED"]} ${messages["try_again_later"]} ${messages["exiting"]}$C_NORM"
                exit 1
            fi
        fi
        ok "${messages["done"]}"

        # produce it -------------------------------------------------------------

        pending " --> ${messages["unpacking"]} ${DOWNLOAD_FILE}... " && \
        tar zxf "$DOWNLOAD_FILE" && \
        ok "${messages["done"]}"

        # pummel it --------------------------------------------------------------

        if [ $PARTYD_RUNNING == 1 ]; then
            pending " --> ${messages["stopping"]} partcld. ${messages["please_wait"]}"
            $RHOM_CLI stop >/dev/null 2>&1
            sleep 15
            killall -9 rhombusd rhombus-shutoff >/dev/null 2>&1
            ok "${messages["done"]}"
        fi

        # prune it ---------------------------------------------------------------

        pending " --> ${messages["removing_old_version"]}"
        rm -rf \
            rhombusd \
            "rhombusd-$CURRENT_VERSION" \
            rhombus-qt \
            "rhombus-qt-$CURRENT_VERSION" \
            rhombus-cli \
            "rhombus-cli-$CURRENT_VERSION"
        #rm -rf \
        #    "$DATA_DIR"/banlist.dat \
        #    "$DATA_DIR"/peers.dat
        ok "${messages["done"]}"

        # place it ---------------------------------------------------------------

        mv "rhombus-$LATEST_VERSION/bin/rhombusd" "rhombusd-$LATEST_VERSION"
        mv "rhombus-$LATEST_VERSION/bin/rhombus-cli" "rhombus-cli-$LATEST_VERSION"
        if [ $ARM != 1 ];then
            mv "rhombus-$LATEST_VERSION/bin/rhombus-qt" "rhombus-qt-$LATEST_VERSION"
        fi
        ln -s "rhombusd-$LATEST_VERSION" rhombusd
        ln -s "rhombus-cli-$LATEST_VERSION" rhombus-cli
        if [ $ARM != 1 ];then
            ln -s "rhombus-qt-$LATEST_VERSION" rhombus-qt
        fi

        # permission it ----------------------------------------------------------

        if [ -n "$SUDO_USER" ]; then
            chown -h "$USER":"$USER" {"$DOWNLOAD_FILE","${DOWNLOAD_FILE}.DIGESTS.txt",rhombus-cli,rhombusd,rhombus-qt,rhombus*"$LATEST_VERSION"}
        fi

        # purge it ---------------------------------------------------------------

        rm -rf "rhombus-${LATEST_VERSION}"

        # punch it ---------------------------------------------------------------

        pending " --> ${messages["launching"]} rhombusd... "
        "$INSTALL_DIR/rhombusd" -daemon > /dev/null 2>&1
        ok "${messages["done"]}"

        # probe it ---------------------------------------------------------------

        pending " --> ${messages["waiting_for_rhombusd_to_respond"]}"
        echo -en "${C_YELLOW}"
        PARTYD_RUNNING=1
        while [ $PARTYD_RUNNING == 1 ] && [ $PARTYD_RESPONDING == 0 ]; do
            echo -n "."
            _check_rhombusd_state
            sleep 5
        done
        if [ $PARTYD_RUNNING == 0 ]; then
            die "\n - rhombusd unexpectedly quit. ${messages["exiting"]}"
        fi
        ok "${messages["done"]}"

        # poll it ----------------------------------------------------------------

        _get_versions

        # pass or punt -----------------------------------------------------------

        if [ "$LATEST_VERSION" == "$CURRENT_VERSION" ]; then
            echo -e ""
            echo -e "${C_GREEN}${messages["successfully_upgraded"]} ${LATEST_VERSION}$C_NORM"

            echo -e ""
            echo -e "${C_GREEN}${messages["installed_in"]} ${INSTALL_DIR}$C_NORM"
            echo -e ""
            ls -l --color {"$DOWNLOAD_FILE","${DOWNLOAD_FILE}.DIGESTS.txt",rhombus-cli,rhombusd,rhombus-qt,rhombus*"$LATEST_VERSION"}
            echo -e ""

            quit ""
        else
            echo -e "${C_RED}${messages["rhombus_version"]} $CURRENT_VERSION ${messages["is_not_uptodate"]} ($LATEST_VERSION) ${messages["exiting"]}$C_NORM"
        fi
    else
        echo -e ""
        echo -e "${C_GREEN}${messages["rhombus_version"]} $CURRENT_VERSION ${messages["is_uptodate"]} ($LATEST_VERSION) ${messages["exiting"]}$C_NORM"
    fi
    exit 0
}

stakingnode_walletinit(){

    echo "$PARTYD_WALLET"
    if [ $PARTYD_RUNNING == 1 ] && [ "$PARTYD_WALLETSTATUS" != "Locked" ]; then
        pending " --> ${messages["stakingnode_init_walletcheck"]}"
        if [ ! "$PARTYD_WALLET"  == "null" ]; then
            die "\n - wallet already exists - 'rhomtools stakingnode' to view list of current staking node public keys or 'rhomtools stakingnode new' to create a new staking node public key. ${messages["exiting"]}"
        else
            ok "${messages["done"]}"
        fi

        echo
        pending " --> ${messages["stakingnode_init_walletgenerate"]}"
        MNEMONIC=$( $RHOM_CLI mnemonic new | grep mnemonic | cut -f2 -d":" | sed 's/\ "//g' | sed 's/\",//g' )
        MNEMONIC_COUNT=$(echo "$MNEMONIC" | wc -w)
        if [ "$MNEMONIC_COUNT" == 24 ]; then
            highlight "$MNEMONIC"
        else
            exit 1
        fi

        echo
        warn "Have you written down your recovery phrase?"
        if ! confirm " [${C_GREEN}y${C_NORM}/${C_RED}N${C_NORM}] $C_CYAN"; then
            echo -e "${C_RED}${messages["exiting"]}$C_NORM"
            echo ""
            exit 0
        fi

        pending " --> ${messages["stakingnode_init_walletcreate"]}"
        if $RHOM_CLI extkeyimportmaster "$MNEMONIC" >/dev/null 2>&1; then
            ok "${messages["done"]}"
        else
            die "\n - failed to create new wallet ${messages["exiting"]}"
        fi
    else
        die "\n - wallet is locked! Please unlock first. ${messages["exiting"]}"
    fi

    echo
    echo -e "    ${C_YELLOW}rhomtools stakingnode info$C_NORM"
    echo

}

stakingnode_newpublickey(){

    if [ $PARTYD_RUNNING == 1 ] && [ "$PARTYD_WALLETSTATUS" != "Locked" ]; then
        pending " --> ${messages["stakingnode_init_walletcheck"]}"
        if [ ! "$PARTYD_WALLET"  == "null" ]; then
            ok "${messages["done"]}"
        else
            die "\n - no wallet exists, please type 'rhomtools stakingnode init' ${messages["exiting"]}"
        fi
        if [ "$PARTYD_TBALANCE" -gt 0 ]; then
            die "\n - WOAH holdup! you cannot setup coldstaking on a hotstaking wallet! ${messages["exiting"]}"
        fi

        echo

        pending "Create new staking node public key?"
        if ! confirm " [${C_GREEN}y${C_NORM}/${C_RED}N${C_NORM}] $C_CYAN"; then
            echo -e "${C_RED}${messages["exiting"]}$C_NORM"
            echo ""
            exit 0
        fi

        pending "Label for new key : "
        read -r pubkeylabel

        echo
        pending " --> ${messages["stakingnode_new_publickey"]}"
        if $RHOM_CLI getnewextaddress "stakingnode_$pubkeylabel"; then
            ok ""
        else
            die "\n - error creating new staking node public key! ' ${messages["exiting"]}"
        fi
    else
        die "\n - wallet is locked! Please unlock first. ${messages["exiting"]}"
    fi


}

stakingnode_rewardaddress(){

    if [ $PARTYD_RUNNING == 1 ] && [ "$PARTYD_WALLETSTATUS" != "Locked" ]; then
        pending " --> ${messages["stakingnode_init_walletcheck"]}"
        if [ ! "$PARTYD_WALLET"  == "null" ]; then
            ok "${messages["done"]}"
        else
            die "\n - no wallet exists, please type 'rhomtools stakingnode init' ${messages["exiting"]}"
        fi
        if [ "$PARTYD_TBALANCE" -gt 0 ]; then
            die "\n -  WOAH holdup! you cannot setup coldstaking on a hotstaking wallet! ${messages["exiting"]}"
        fi
        echo

        pending " --> ${messages["stakingnode_reward_check"]}"
        STAKE_OPTS=$($RHOM_CLI walletsettings stakingoptions | jq .stakingoptions)
        if [ "$STAKE_OPTS" == "\"default\"" ]; then
            STAKE_OPTS="{}"
        fi
        REWARD_ADDRESS=$(echo "$STAKE_OPTS" | jq -r .rewardaddress)
        if [ -n "$REWARD_ADDRESS" ] && [ "$REWARD_ADDRESS" != "null" ] ; then
            REWARD_ADDRESS_DATE=$(echo "$STAKE_OPTS" | jq -r .time)
            REWARD_ADDRESS_DATEFORMATTED=$(stamp2date "$REWARD_ADDRESS_DATE")
            ok "${messages["done"]}"
            pending " --> ${messages["stakingnode_reward_found"]}"
            highlight "$REWARD_ADDRESS (Set on $REWARD_ADDRESS_DATEFORMATTED)"
        else
            ok "${messages["done"]}"
            pending " --> ${messages["stakingnode_reward_found"]}"
            highlight "default mode"
            echo -e "** Your wallet is configured in default mode - it will send the staking rewards back to the staking address."
        fi

        echo
        pending "Configure a new reward address?"
        if ! confirm " [${C_GREEN}y${C_NORM}/${C_RED}N${C_NORM}] $C_CYAN"; then
            echo -e "${C_RED}${messages["exiting"]}$C_NORM"
            echo ""
            exit 0
        fi

        pending "Rhombus Address to send all rewards to : "
        read -r rewardAddress

        echo
        pending " --> ${messages["stakingnode_reward_address"]}"

        STAKE_OPTS=$(echo "$STAKE_OPTS" | jq 'del(.time)')
        if [ -z "$rewardAddress" ]
        then
            STAKE_OPTS=$(echo "$STAKE_OPTS" | jq 'del(.rewardaddress)')
        else
            STAKE_OPTS=$(echo "$STAKE_OPTS" | jq ".rewardaddress = \"${rewardAddress}\"")
        fi

        echo
        if "$RHOM_CLI" walletsettings stakingoptions "$STAKE_OPTS"; then
            ok ""
        else
            die "\n - error setting the reward address! ' ${messages["exiting"]}"
        fi
    else
        die "\n - wallet is locked! Please unlock first. ${messages["exiting"]}"
    fi


}

stakingnode_smsgfeeratetarget(){

    if [ $PARTYD_RUNNING == 1 ] && [ "$PARTYD_WALLETSTATUS" != "Locked" ]; then
        pending " --> ${messages["stakingnode_init_walletcheck"]}"
        if [ ! "$PARTYD_WALLET"  == "null" ]; then
            ok "${messages["done"]}"
        else
            die "\n - no wallet exists, please type 'rhomtools stakingnode init' ${messages["exiting"]}"
        fi
        if [ "$PARTYD_TBALANCE" -gt 0 ]; then
            die "\n -  WOAH holdup! you cannot setup coldstaking on a hotstaking wallet! ${messages["exiting"]}"
        fi
        echo

        pending " --> ${messages["stakingnode_smsgfeerate_check"]}"
        STAKE_OPTS=$($RHOM_CLI walletsettings stakingoptions | jq .stakingoptions)
        if [ "$STAKE_OPTS" == "\"default\"" ]; then
            STAKE_OPTS="{}"
        fi
        SMSG_FEE_RATE_TARGET=$(echo "$STAKE_OPTS" | jq -r .smsgfeeratetarget)
        if [ -n "$SMSG_FEE_RATE_TARGET" ] && [ "$SMSG_FEE_RATE_TARGET" != "null" ] ; then
            SMSG_FEE_RATE_TARGET_DATE=$(echo "$STAKE_OPTS" | jq -r .time)
            SMSG_FEE_RATE_TARGET_DATEFORMATTED=$(stamp2date "$SMSG_FEE_RATE_TARGET_DATE")
            ok "${messages["done"]}"
            pending " --> ${messages["stakingnode_smsgfeerate_found"]}"
            highlight "$SMSG_FEE_RATE_TARGET (Set on $SMSG_FEE_RATE_TARGET_DATEFORMATTED)"
        else
            ok "${messages["done"]}"
            pending " --> ${messages["stakingnode_smsgfeerate_found"]}"
            highlight "default mode"
            echo -e "** Your wallet is configured in default mode - it will not attempt to adjust the smsg fee rate."
        fi

        echo
        pending "Configure a new smsg fee rate target?"
        if ! confirm " [${C_GREEN}y${C_NORM}/${C_RED}N${C_NORM}] $C_CYAN"; then
            echo -e "${C_RED}${messages["exiting"]}$C_NORM"
            echo ""
            exit 0
        fi

        echo ""
        pending "** rhomtools recommends a smsg fee rate of : "
        highlight "0.00020000"
        echo ""
        pending "Amount to adjust the smsg fee rate towards : "
        read -r feeRateTarget

        echo
        pending " --> ${messages["stakingnode_smsgfeerate_address"]}"

        STAKE_OPTS=$(echo "$STAKE_OPTS" | jq 'del(.time)')
        if [ -z "$feeRateTarget" ]
        then
            STAKE_OPTS=$(echo "$STAKE_OPTS" | jq 'del(.smsgfeeratetarget)')
        else
            STAKE_OPTS=$(echo "$STAKE_OPTS" | jq ".smsgfeeratetarget = \"${feeRateTarget}\"")
        fi

        echo
        if "$RHOM_CLI" walletsettings stakingoptions "$STAKE_OPTS"; then
            ok ""
        else
            die "\n - error setting the smsg fee rate target! ' ${messages["exiting"]}"
        fi
    else
        die "\n - wallet is locked! Please unlock first. ${messages["exiting"]}"
    fi


}

stakingnode_info(){
    _check_qrcode

    if [ $PARTYD_RUNNING == 1 ] && [ "$PARTYD_WALLETSTATUS" != "Locked" ]; then
        pending " --> ${messages["stakingnode_init_walletcheck"]}"
        if [ ! "$PARTYD_WALLET"  == "null" ]; then
            ok "${messages["done"]}"
        else
            die "\n - no wallet exists, please type 'rhomtools stakingnode init' ${messages["exiting"]}"
        fi

        ACCOUNTID=$( $RHOM_CLI extkey account | grep "\"id"\" | cut -f2 -d":" | sed 's/\ "//g' | sed 's/\",//g' )

        echo
        FOUNDSTAKINGNODEKEY=0
        for ID in $ACCOUNTID;
        do
            IDINFO=$($RHOM_CLI extkey key "$ID" true 2>&-)
            IDINFO_LABEL=$( echo "$IDINFO" | jq -r .label)
            if echo "$IDINFO_LABEL" | grep -q "stakingnode"; then
                IDINFO_PUBKEY=$( echo "$IDINFO" | jq -r .epkey)
                pending " --> Staking Node Label : "
                ok "$IDINFO_LABEL"
                pending " --> Staking Node Public Key : "
                ok "$IDINFO_PUBKEY"
                if [ -e "$INSTALL_DIR/qrcode" ] ; then
                    "$INSTALL_DIR/qrcode" "$IDINFO_PUBKEY"
                fi
                echo
                FOUNDSTAKINGNODEKEY=1
            fi
        done

        if [ $FOUNDSTAKINGNODEKEY == 0 ] || [ -z $FOUNDSTAKINGNODEKEY ]; then
            die " - no staking node public keys found, please type 'rhomtools stakingnode new' to create one. ${messages["exiting"]}"
        fi
    else
        die "\n - wallet is locked! Please unlock first. ${messages["exiting"]}"
    fi

}

_check_qrcode() {
    if [ ! -e "$INSTALL_DIR/qrcode" ] ; then
        QRCODE_DOWNLOAD_URL="https://github.com/spazzymoto/qrcode/releases/download/v1.0.0/qrcode_linux_$QRCODE_ARCH"
        pending " --> ${messages["downloading"]} ${QRCODE_DOWNLOAD_URL}... "
        tput sc
        echo -e "$C_CYAN"
        $wget_cmd -O - $QRCODE_DOWNLOAD_URL | pv -trep -s27M -w80 -N qrcode > "$INSTALL_DIR/qrcode"
        echo -ne "$C_NORM"
        clear_n_lines 2
        tput rc
        clear_n_lines 3
        if [ ! -e "$INSTALL_DIR/qrcode" ] ; then
            echo -e "${C_RED}error ${messages["downloading"]} file"
            echo -e "tried to get $QRCODE_DOWNLOAD_URL$C_NORM"
            exit 1
        else
            chmod +x "$INSTALL_DIR/qrcode"
            ok "${messages["done"]}"
        fi
    fi
}

stakingnode_stats(){

    if [ $PARTYD_RUNNING == 1 ] && [ "$PARTYD_WALLETSTATUS" != "Locked" ]; then
        pending " --> ${messages["stakingnode_init_walletcheck"]}"
        if [ ! "$PARTYD_WALLET"  == "null" ]; then
            ok "${messages["done"]}"
        else
            die "\n - no wallet exists, please type 'rhomtools stakingnode init' ${messages["exiting"]}"
        fi
        if [ ! "$LATEST_VERSION" == "$CURRENT_VERSION" ]; then
            die "\n - please upgrade to the latest version! ${messages["exiting"]}"
        fi

        DAY=$(date -u +%d)
        MONTH=$(date -u +%m)
        YEAR=$(date -u +%Y)

        COUNTER=1

        pending " --> ${messages["stakingnode_stats_daily"]}"
        ok "${messages["done"]}"
        echo
        printf '%-4s %-15s %-30s %-12s\n' \
        "${messages["stakingnode_stats_indent"]}" "DAY" "# STAKES" "TOTAL STAKED"

        until [ $COUNTER -gt "$DAY" ]; do
            NUMBER_OF_STAKES=$( $RHOM_CLI filtertransactions "{\"from\":\"$YEAR-$MONTH-$COUNTER\", \"to\":\"$YEAR-$MONTH-$COUNTER\",\"count\":100000,\"category\":\"stake\",\"collate\":true,\"include_watchonly\":true,\"with_reward\":true}" | jq .collated.records)
            STAKE_AMOUNT=$( $RHOM_CLI filtertransactions "{\"from\":\"$YEAR-$MONTH-$COUNTER\", \"to\":\"$YEAR-$MONTH-$COUNTER\",\"count\":100000,\"category\":\"stake\",\"collate\":true,\"include_watchonly\":true,\"with_reward\":true}" | jq .collated.total_reward)

            printf '%-4s %-15s %-30s %-12s\n' \
            "${messages["stakingnode_stats_indent"]}" "$COUNTER" "$NUMBER_OF_STAKES" "$STAKE_AMOUNT"
            COUNTER=$((COUNTER+1))
        done

        echo
        pending " --> ${messages["stakingnode_stats_monthly"]}"
        ok "${messages["done"]}"
        echo
        printf '%-4s %-15s %-30s %-12s\n' \
        "${messages["stakingnode_stats_indent"]}" "MONTH" "# STAKES" "TOTAL STAKED"

        COUNTER=12
        until [ $COUNTER == 0 ]; do
            NUMBER_OF_STAKES=$( $RHOM_CLI filtertransactions "{\"from\":\"$YEAR-$COUNTER\", \"to\":\"$YEAR-$COUNTER\",\"count\":100000,\"category\":\"stake\",\"collate\":true,\"include_watchonly\":true,\"with_reward\":true}" | jq .collated.records)
            STAKE_AMOUNT=$( $RHOM_CLI filtertransactions "{\"from\":\"$YEAR-$COUNTER\", \"to\":\"$YEAR-$COUNTER\",\"count\":100000,\"category\":\"stake\",\"collate\":true,\"include_watchonly\":true,\"with_reward\":true}" | jq .collated.total_reward)
            if [[ $NUMBER_OF_STAKES != 0 ]] && [[ $STAKE_AMOUNT != 0 ]]; then
                printf '%-4s %-15s %-30s %-12s\n' \
                "${messages["stakingnode_stats_indent"]}" "$COUNTER ($YEAR)" "$NUMBER_OF_STAKES" "$STAKE_AMOUNT"
            fi
            COUNTER=$((COUNTER-1))
        done

        YEAR=$((YEAR-1))
        until [ $YEAR == 2016 ]; do
		echo
        	COUNTER=12
        	until [ $COUNTER == 0 ]; do
        	    NUMBER_OF_STAKES=$( $RHOM_CLI filtertransactions "{\"from\":\"$YEAR-$COUNTER\", \"to\":\"$YEAR-$COUNTER\",\"count\":100000,\"category\":\"stake\",\"collate\":true,\"include_watchonly\":true,\"with_reward\":true}" | jq .collated.records)
            	STAKE_AMOUNT=$( $RHOM_CLI filtertransactions "{\"from\":\"$YEAR-$COUNTER\", \"to\":\"$YEAR-$COUNTER\",\"count\":100000,\"category\":\"stake\",\"collate\":true,\"include_watchonly\":true,\"with_reward\":true}" | jq .collated.total_reward)
            	if [[ $NUMBER_OF_STAKES != 0 ]] && [[ $STAKE_AMOUNT != 0 ]]; then
                	printf '%-4s %-15s %-30s %-12s\n' \
                	"${messages["stakingnode_stats_indent"]}" "$COUNTER ($YEAR)" "$NUMBER_OF_STAKES" "$STAKE_AMOUNT"
            	fi
            	COUNTER=$((COUNTER-1))
        	done
		YEAR=$((YEAR-1))
	done

    else
        die "\n - wallet is locked! Please unlock first. ${messages["exiting"]}"
    fi

}

stakingnode_proposallist(){

    if [ $PARTYD_RUNNING == 1 ] && [ "$PARTYD_WALLETSTATUS" != "Locked" ]; then
        pending " --> ${messages["stakingnode_init_walletcheck"]}"
        if [ ! "$PARTYD_WALLET"  == "null" ]; then
            ok "${messages["done"]}"
        else
            die "\n - no wallet exists, please type 'rhomtools stakingnode init' ${messages["exiting"]}"
        fi

        PROPOSAL_DOWNLOAD_URL="https://raw.githubusercontent.com/rhombuscommunity/rhombus-proposals/master/testnet/metadata.txt"
        echo

        pending " --> ${messages["proposal_get_active"]}"
        $wget_cmd -O - $PROPOSAL_DOWNLOAD_URL | pv -trep -s27M -w80 -N proposal > "proposal"
        if [ ! -e "proposal" ] ; then
            echo -e "${C_RED}error ${messages["downloading"]} file"
            echo -e "tried to get $PROPOSAL_DOWNLOAD_URL$C_NORM"
            exit 1
        else
        ok "${messages["done"]}"
        fi

        pending " --> ${messages["proposal_reading"]}"
        PROPOSALLIST=$( cat proposal | jq -r .);

        if [ -z "$PROPOSALLIST" ]; then
           rm -rf proposal
           die "\n - failed to get proposal list ${messages["exiting"]}"
        fi
        ok "${messages["done"]}"

        pending " --> ${messages["proposal_process"]}"
        ok "${messages["done"]}"

        echo
        #PROCESSPROPOSALLIST=$( echo $PROPOSALLIST | jq -r '. | "\(.proposalid)\t\(.name)\t\(.blockheight_start)\t\(.blockheight_end)\t\(.link)"');
        #PROCESSPROPOSALLIST=$( echo $PROPOSALLIST | jq -r '(.[0] |keys_unsorted | @tsv), (.[]|.|map(.) |@tsv)' | column -t);
        printf '%s\n' "$PROPOSALLIST"

    else
        die "\n - wallet is locked! Please unlock first. ${messages["exiting"]}"
    fi

}

stakingnode_proposalvote(){

    if [ $PARTYD_RUNNING == 1 ] && [ "$PARTYD_WALLETSTATUS" != "Locked" ]; then
        pending " --> ${messages["stakingnode_init_walletcheck"]}"
        if [ ! "$PARTYD_WALLET"  == "null" ]; then
            ok "${messages["done"]}"
        else
            die "\n - no wallet exists, please type 'rhomtools stakingnode init' ${messages["exiting"]}"
        fi

        if [ ! -e "proposal" ] ; then
            die "\n - no proposal data exists, please type 'rhomtools proposal list' ${messages["exiting"]}"
        fi

        echo
        highlight "Setting a new vote will clear all previous settings. You can only vote on one proposal at a time."
        echo
        pending "Continue to set a new vote?"
        if ! confirm " [${C_GREEN}y${C_NORM}/${C_RED}N${C_NORM}] $C_CYAN"; then
            echo -e "${C_RED}${messages["exiting"]}$C_NORM"
            echo ""
            exit 0
        fi

        echo
        pending "Proposal ID : "
        read -r proposalid

        pending "checking if valid proposal ... "
        PROPOSAL_HEIGHT_START=$( cat proposal | jq ".[] | select(.proposalid == ${proposalid} ) | .blockheight_start" )
        PROPOSAL_HEIGHT_END=$( cat proposal | jq ".[] | select(.proposalid == ${proposalid} ) | .blockheight_end" )

        if [ -z "$PROPOSAL_HEIGHT_START" ]; then
            die "\n - not a valid proposal id! ' ${messages["exiting"]}"
        fi

        PARTYD_CURRENT_BLOCK=$("$RHOM_CLI" getblockcount 2>/dev/null)
        if [ -z "$PARTYD_CURRENT_BLOCK" ] ; then PARTYD_CURRENT_BLOCK=0 ; fi

        if [ "$PARTYD_CURRENT_BLOCK" -gt "$PROPOSAL_HEIGHT_END" ]; then
            die "\n - proposal voting has finished! ' ${messages["exiting"]}"
        fi

        ok "${messages["done"]}"

        PROPOSALDETAILS=$( cat proposal | jq ".[] | select(.proposalid == ${proposalid} ) | ." )
        printf '%s\n' "$PROPOSALDETAILS"

        echo
        pending "Abstain (0), Vote For (1) or Vote Against (2) [default=0]: "
        read -r proposaloption

        if [ -z "$proposaloption" ]; then
            proposaloption=0
        fi

        if [ "$proposaloption" == 0 ]; then
            proposalid=0
        fi

        if "$RHOM_CLI" setvote "$proposalid" "$proposaloption" "$PROPOSAL_HEIGHT_START" "$PROPOSAL_HEIGHT_END"; then
            ok ""
        else
            die "\n - error setting vote! ' ${messages["exiting"]}"
	fi

    else
        die "\n - wallet is locked! Please unlock first. ${messages["exiting"]}"
    fi

}

stakingnode_proposaltally(){

    if [ $PARTYD_RUNNING == 1 ] && [ "$PARTYD_WALLETSTATUS" != "Locked" ]; then
        pending " --> ${messages["stakingnode_init_walletcheck"]}"
        if [ ! "$PARTYD_WALLET"  == "null" ]; then
            ok "${messages["done"]}"
        else
            die "\n - no wallet exists, please type 'rhomtools stakingnode init' ${messages["exiting"]}"
        fi

        if [ ! -e "proposal" ] ; then
            die "\n - no proposal data exists, please type 'rhomtools proposal list' ${messages["exiting"]}"
        fi

        echo
        pending "Proposal ID : "
        read -r proposalid

        pending "checking if valid proposal ... "
        PROPOSAL_HEIGHT_START=$( cat proposal | jq ".[] | select(.proposalid == ${proposalid} ) | .blockheight_start" )
        PROPOSAL_HEIGHT_END=$( cat proposal | jq ".[] | select(.proposalid == ${proposalid} ) | .blockheight_end" )

        if [ -z "$PROPOSAL_HEIGHT_START" ]; then
            die "\n - not a valid proposal id! ' ${messages["exiting"]}"
        fi

        ok "${messages["done"]}"
        PROPOSALDETAILS=$( cat proposal | jq ".[] | select(.proposalid == ${proposalid} ) | ." )
        printf '%s\n' "$PROPOSALDETAILS"


        pending "checking blockchain for voting data ... "
        echo
        if "$RHOM_CLI" tallyvotes "$proposalid" "$PROPOSAL_HEIGHT_START" "$PROPOSAL_HEIGHT_END"; then
            ok ""
        else
            die "\n - error getting vote details! ' ${messages["exiting"]}"
        fi

    else
        die "\n - wallet is locked! Please unlock first. ${messages["exiting"]}"
    fi

}
configure_firewall(){

    UFW_STATUS=$(sudo ufw status | head -n 1 | cut -d' ' -f2)
    pending " --> ${messages["firewall_status"]}"
    ok " $UFW_STATUS"

    if [ "$UFW_STATUS" == "inactive" ]; then
        echo
        pending "Configure default firewall?"
        if ! confirm " [${C_GREEN}y${C_NORM}/${C_RED}N${C_NORM}] $C_CYAN"; then
            echo -e "${C_RED}${messages["exiting"]}$C_NORM"
            echo ""
            exit 0
        fi

        pending " --> ${messages["firewall_configure"]}"
        echo
        SSH_PORT=${SSH_CLIENT##* }
        if [ -z "$SSH_PORT" ] ; then SSH_PORT=22 ; fi

        # creates a minimal set of firewall rules that allows INBOUND masternode p2p & SSH ports */
        # disallow everything except ssh, 8080 (webserver) and inbound ports 51738 and 51938
        $FIREWALL_CLI default deny
        $FIREWALL_CLI logging on
        $FIREWALL_CLI allow $SSH_PORT/tcp
        $FIREWALL_CLI allow 8080/tcp comment 'rhomtools webserver'
        $FIREWALL_CLI allow 51738/tcp comment 'rhombus p2p mainnet'
        $FIREWALL_CLI allow 51938/tcp comment 'rhombus p2p testnet'

        # This will only allow 6 connections every 30 seconds from the same IP address.
        $FIREWALL_CLI limit OpenSSH
        $FIREWALL_CLI --force enable
        ok "${messages["done"]}"
    fi

        pending " --> ${messages["firewall_report"]}"
        echo
        $FIREWALL_CLI status
}

firewall_reset(){

    UFW_STATUS=$(sudo ufw status | head -n 1 | cut -d' ' -f2)
    pending " --> ${messages["firewall_status"]}"
    ok " $UFW_STATUS"

    if [ "$UFW_STATUS" == "active" ]; then
        echo
        pending "Reset and disable firewall?"
        if ! confirm " [${C_GREEN}y${C_NORM}/${C_RED}N${C_NORM}] $C_CYAN"; then
            echo -e "${C_RED}${messages["exiting"]}$C_NORM"
            echo ""
            exit 0
        fi

        ok ""
        echo "y" | $FIREWALL_CLI reset
        UFW_STATUS=$(sudo ufw status | head -n 1 | cut -d' ' -f2)
        pending " --> ${messages["firewall_status"]}"
        ok " $UFW_STATUS"
    fi
}

_get_rhombusd_proc_status(){
    PARTYD_HASPID=0
    if [ -e "$INSTALL_DIR/rhombus.pid" ] ; then
        PARTYD_HASPID=$(ps --no-header "$(cat "$INSTALL_DIR/rhombus.pid" 2>/dev/null)" | wc -l);
    else
        if ! PARTYD_HASPID=$(pidof "$INSTALL_DIR/rhombusd"); then
            PARTYD_HASPID=0
        fi
    fi
    PARTYD_PID=$(pidof "$INSTALL_DIR/rhombusd")
}

get_rhombusd_status(){

    _get_rhombusd_proc_status

    PARTYD_UPTIME=$($RHOM_CLI uptime 2>/dev/null)
    if [ -z "$PARTYD_UPTIME" ] ; then PARTYD_UPTIME=0 ; fi

    PARTYD_LISTENING=$(netstat -nat | grep LIST | grep -c 51738);
    PARTYD_CONNECTIONS=$(netstat -nat | grep ESTA | grep -c 51738);
    PARTYD_CURRENT_BLOCK=$("$RHOM_CLI" getblockcount 2>/dev/null)
    if [ -z "$PARTYD_CURRENT_BLOCK" ] ; then PARTYD_CURRENT_BLOCK=0 ; fi


    WEB_BLOCK_COUNT_CHAINZ=$($curl_cmd https://chainz.cryptoid.info/part/api.dws?q=getblockcount 2>/dev/null | jq -r .);
    if [ -z "$WEB_BLOCK_COUNT_CHAINZ" ]; then
        WEB_BLOCK_COUNT_CHAINZ=0
    fi

    WEB_BLOCK_COUNT_PART=$($curl_cmd https://explorer.rhombus.io/rhombus-insight-api/sync 2>/dev/null | jq -r .blockChainHeight)
    if [ -z "$WEB_BLOCK_COUNT_PART" ]; then
        WEB_BLOCK_COUNT_PART=0
    fi

    PARTYD_SYNCED=0
    if [ $PARTYD_RUNNING == 1 ]; then
        if [ $PARTYD_CURRENT_BLOCK == $WEB_BLOCK_COUNT_CHAINZ ] || [ $PARTYD_CURRENT_BLOCK == $WEB_BLOCK_COUNT_PART ] || [ $PARTYD_CURRENT_BLOCK -ge $((WEB_BLOCK_COUNT_CHAINZ -5)) ] || [ $PARTYD_CURRENT_BLOCK -ge $((WEB_BLOCK_COUNT_PART -5)) ]; then
            PARTYD_SYNCED=1
        fi
    fi

    PARTYD_CONNECTED=0
    if [ "$PARTYD_CONNECTIONS" -gt 0 ]; then PARTYD_CONNECTED=1 ; fi

    PARTYD_UP_TO_DATE=0
    if [ -z "$LATEST_VERSION" ]; then
        PARTYD_UP_TO_DATE_STATUS="UNKNOWN"
    else
        PARTYD_UP_TO_DATE_STATUS="NO"
        if [ "$LATEST_VERSION" == "$CURRENT_VERSION" ]; then
            PARTYD_UP_TO_DATE=1
        fi
    fi

    get_public_ips

    PUBLIC_PORT_CLOSED=$( timeout 2 nc -4 -z "$PUBLIC_IPV4" 51738 > /dev/null 2>&1; echo $? )

    #staking info
    if [ $PARTYD_RUNNING == 1 ]; then
        PARTYD_GETSTAKINGINFO=$($RHOM_CLI getstakinginfo 2>/dev/null);
        STAKING_ENABLED=$(echo "$PARTYD_GETSTAKINGINFO" | grep enabled | awk '{print $2}' | sed -e 's/[",]//g')
        if [ "$STAKING_ENABLED" == "true" ]; then STAKING_ENABLED=1; elif [ $STAKING_ENABLED == "false" ]; then STAKING_ENABLED=0; fi
        STAKING_CURRENT=$(echo "$PARTYD_GETSTAKINGINFO" | grep staking | awk '{print $2}' | sed -e 's/[",]//g')
        if [ "$STAKING_CURRENT" == "true" ]; then STAKING_CURRENT=1; elif [ $STAKING_CURRENT == "false" ]; then STAKING_CURRENT=0; fi
        STAKING_STATUS=$(echo "$PARTYD_GETSTAKINGINFO" | grep cause | awk '{print $2}' | sed -e 's/[",]//g')
        STAKING_PERCENTAGE=$(echo "$PARTYD_GETSTAKINGINFO" | grep percentyearreward | awk '{print $2}' | sed -e 's/[",]//g')
        STAKING_DIFF=$(echo "$PARTYD_GETSTAKINGINFO" | grep difficulty | awk '{print $2}' | sed -e 's/[",]//g')
        PARTYD_STAKEWEIGHT=$(echo "$PARTYD_GETSTAKINGINFO" | grep "\"weight"\" | awk '{print $2}' | sed -e 's/[",]//g')
        PARTYD_NETSTAKEWEIGHT=$(echo "$PARTYD_GETSTAKINGINFO" | grep netstakeweight | awk '{print $2}' | sed -e 's/[",]//g')

        PARTYD_NETSTAKEWEIGHT=$((PARTYD_NETSTAKEWEIGHT / 100000000))
        PARTYD_STAKEWEIGHT=$((PARTYD_STAKEWEIGHT / 100000000))

        #Hack for floating point arithmetic
        STAKEWEIGHTPERCENTAGE=$( awk "BEGIN {printf \"%.3f%%\", $PARTYD_STAKEWEIGHT/$PARTYD_NETSTAKEWEIGHT*100}" )
        T_PARTYD_STAKEWEIGHT=$(printf "%'.0f" $PARTYD_STAKEWEIGHT)
        PARTYD_STAKEWEIGHTLINE="$T_PARTYD_STAKEWEIGHT ($STAKEWEIGHTPERCENTAGE)"

        PARTYD_GETCOLDSTAKINGINFO=$($RHOM_CLI getcoldstakinginfo 2>/dev/null);
        CSTAKING_ENABLED=$(echo "$PARTYD_GETCOLDSTAKINGINFO" | grep enabled | awk '{print $2}' | sed -e 's/[",]//g')
        CSTAKING_CURRENT=$(echo "$PARTYD_GETCOLDSTAKINGINFO" | grep currently_staking | awk '{print $2}' | sed -e 's/[",]//g')
        CSTAKING_BALANCE=$(echo "$PARTYD_GETCOLDSTAKINGINFO" | grep coin_in_coldstakeable_script | awk '{print $2}' | sed -e 's/[",]//g')
    fi
}

date2stamp () {
    date --utc --date "$1" +%s
}

stamp2date (){
    date --utc --date "1970-01-01 $1 sec" "+%Y-%m-%d %T"
}

dateDiff (){
    case $1 in
        -s)   sec=1;      shift;;
        -m)   sec=60;     shift;;
        -h)   sec=3600;   shift;;
        -d)   sec=86400;  shift;;
        *)    sec=86400;;
    esac
    dte1=$(date2stamp "$1")
    dte2=$(date2stamp "$2")
    diffSec=$((dte2-dte1))
    if ((diffSec < 0)); then abs=-1; else abs=1; fi
    echo $((diffSec*abs/sec))
}

function displaytime()
{
    local t=$1

    local d=$((t/60/60/24))
    local h=$((t/60/60%24))
    local m=$((t/60%60))
    local s=$((t%60))

    if [[ $d -gt 0 ]]; then
            [[ $d = 1 ]] && echo -n "$d day " || echo -n "$d days "
    fi
    if [[ $h -gt 0 ]]; then
            [[ $h = 1 ]] && echo -n "$h hour " || echo -n "$h hours "
    fi
    if [[ $m -gt 0 ]]; then
            [[ $m = 1 ]] && echo -n "$m minute " || echo -n "$m minutes "
    fi
    if [[ $d = 0 && $h = 0 && $m = 0 ]]; then
            [[ $s = 1 ]] && echo -n "$s second" || echo -n "$s seconds"
    fi
    echo
}

get_host_status(){
    HOST_LOAD_AVERAGE=$(< /proc/loadavg awk '{print $1" "$2" "$3}')
    uptime=$(</proc/uptime)
    uptime=${uptime%%.*}
    HOST_UPTIME_DAYS=$(( uptime/60/60/24 ))
    HOSTNAME=$(hostname -f)
}


print_getinfo() {

    if [ $PARTYD_RUNNING == 1 ]; then
        $RHOM_CLI -getinfo
        $RHOM_CLI getwalletinfo
    fi
}

print_status() {

    pending "${messages["status_hostnam"]}" ; ok "$HOSTNAME"
    pending "${messages["status_uptimeh"]}" ; ok "$HOST_UPTIME_DAYS ${messages["days"]}, $HOST_LOAD_AVERAGE"
    pending "${messages["status_rhombusdip"]}" ; if [ "$PUBLIC_IPV4" != "none" ] ; then ok "$PUBLIC_IPV4" ; else err "$PUBLIC_IPV4" ; fi
    pending "${messages["status_rhombusdve"]}" ; ok "$CURRENT_VERSION"
    pending "${messages["status_uptodat"]}" ; if [ "$PARTYD_UP_TO_DATE"      -gt 0 ] ; then ok "${messages["YES"]}" ; else err "$PARTYD_UP_TO_DATE_STATUS ($LATEST_VERSION)" ; fi
    pending "${messages["status_running"]}" ; if [ "$PARTYD_HASPID"          -gt 0 ] ; then ok "${messages["YES"]}" ; else err "${messages["NO"]}" ; fi
    pending "${messages["status_uptimed"]}" ; if [ "$PARTYD_UPTIME"          -gt 0 ] ; then ok "$(displaytime $PARTYD_UPTIME)" ; else err "${messages["NO"]}" ; fi
    pending "${messages["status_drespon"]}" ; if [ "$PARTYD_RUNNING"         -gt 0 ] ; then ok "${messages["YES"]}" ; else err "${messages["NO"]}" ; fi
    pending "${messages["status_dlisten"]}" ; if [ "$PARTYD_LISTENING"       -gt 0 ] ; then ok "${messages["YES"]}" ; else err "${messages["NO"]}" ; fi
    pending "${messages["status_dportop"]}" ; if [ "$PUBLIC_PORT_CLOSED"     -lt 1 ] ; then ok "${messages["YES"]}" ; else highlight "${messages["NO"]}*" ; fi
    pending "${messages["status_dconnec"]}" ; if [ "$PARTYD_CONNECTED"       -gt 0 ] ; then ok "${messages["YES"]}" ; else err "${messages["NO"]}" ; fi
    pending "${messages["status_dconcnt"]}" ; if [ "$PARTYD_CONNECTIONS"     -gt 0 ] ; then ok "$PARTYD_CONNECTIONS" ; else err "$PARTYD_CONNECTIONS" ; fi
    pending "${messages["status_dblsync"]}" ; if [ "$PARTYD_SYNCED"          -gt 0 ] ; then ok "${messages["YES"]}" ; else err "${messages["NO"]}" ; fi
    pending "${messages["status_dbllast"]}" ; if [ "$PARTYD_SYNCED"          -gt 0 ] ; then ok "$PARTYD_CURRENT_BLOCK" ; else err "$PARTYD_CURRENT_BLOCK" ; fi
    pending "${messages["status_webpart"]}" ; if [ "$WEB_BLOCK_COUNT_PART"   -gt 0 ] ; then ok "$WEB_BLOCK_COUNT_PART" ; else err "$WEB_BLOCK_COUNT_PART" ; fi
    pending "${messages["status_webchai"]}" ; if [ "$WEB_BLOCK_COUNT_CHAINZ" -gt 0 ] ; then ok "$WEB_BLOCK_COUNT_CHAINZ" || err "$WEB_BLOCK_COUNT_CHAINZ" ; fi
    if [ $PARTYD_RUNNING == 1 ]; then
        pending "${messages["breakline"]}" ; ok ""
        pending "${messages["status_stakeen"]}" ; if [ $STAKING_ENABLED -gt 0 ] ; then ok "${messages["YES"]} - $STAKING_PERCENTAGE%" ; else err "${messages["NO"]}" ; fi
        pending "${messages["status_stakedi"]}" ; ok "$(printf "%'.0f" "$STAKING_DIFF")"
        pending "${messages["status_stakenw"]}" ; ok "$(printf "%'.0f" "$PARTYD_NETSTAKEWEIGHT")"
        pending "${messages["breakline"]}" ; ok ""
        pending "${messages["status_stakecu"]}" ; if [ $STAKING_CURRENT -gt 0 ] ; then ok "${messages["YES"]}" ; else err "${messages["NO"]} - $STAKING_STATUS" ; fi
        pending "${messages["status_stakeww"]}" ; ok "$PARTYD_STAKEWEIGHTLINE"
        pending "${messages["status_stakebl"]}" ; ok "$(printf "%'.0f" "$CSTAKING_BALANCE")"
    fi

    if [ "$PUBLIC_PORT_CLOSED"  -gt 0 ]; then
       echo
       highlight "* Inbound P2P Port is not open - this is okay and will not affect the function of this staking node."
       highlight "  However by opening port 51738/tcp you can provide full resources to the Rhombus Network by acting as a 'full node'."
       highlight "  A 'full staking node' will increase the number of other nodes you connect to beyond the 16 limit."
    fi
}

show_message_configure() {
    echo
    ok "${messages["to_start_rhombus"]}"
    echo
    echo -e "    ${C_YELLOW}rhomtools restart now$C_NORM"
    echo
}

get_public_ips() {
    PUBLIC_IPV4=$(dig -4 +short myip.opendns.com @resolver1.opendns.com)
}
