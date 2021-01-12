# rhomtools

Rhombus wallet/daemon management utilities - version 0.11

* This script installs, updates, and manages single-user rhombus daemons and wallets
* This script provides the ability to create a new wallet and manage staking node (cold staking functionality)

# Install/Usage

To install rhomtools do:

    sudo apt-get install python git unzip pv jq dnsutils
    cd ~ && git clone https://github.com/dasource/rhomtools

To get the current status of rhombusd, do:

    rhomtools/rhomtools status

To get the RPC command `getinfo` and `getwalletinfo` from rhombusd, do:

    rhomtools/rhomtools getinfo



To perform a new install of rhombus, do:

    rhomtools/rhomtools install

To update to the latest version of rhombus, do:

    rhomtools/rhomtools update

To overwrite an existing rhombus install, do:

    rhomtools/rhomtools reinstall

To restart (or start) rhombusd, do:

    rhomtools/rhomtools restart



To create a new wallet on this staking node, do:

    rhomtools/rhomtools stakingnode init

To create a new public key on this staking node, do:

    rhomtools/rhomtools stakingnode new

To get a list of public keys on this staking node, do:

    rhomtools/rhomtools stakingnode

To get staking stats for this staking node, do:

    rhomtools/rhomtools stakingnode stats

To configure the reward address for this staking node, do:

    rhomtools/rhomtools stakingnode rewardaddress

To configure the smsg fee rate target for this staking node, do:

    rhomtools/rhomtools stakingnode smsgfeeratetarget



To install an create firewall/ufw rules to restrict access to only PORTS 22, 8080, 51738 and 51938, do:

    rhomtools/rhomtools firewall

To disable the firewall/ufw and reset the rules, do:

    rhomtools/rhomtools firewall reset



# Commands

## install

"rhomtools install" downloads and initializes a fresh rhombus install into ~/.rhombus
unless already present

## reinstall

"rhomtools reinstall" downloads and overwrites existing rhombus executables, even if
already present

## restart

"rhomtools restart [now]" restarts (or starts) rhombusd. Searches for rhombus-cli/rhombusd
the current directory, ~/.rhombus, and $PATH. It will prompt to restart if not
given the optional 'now' argument.

## status

"rhomtools status" interrogates the locally running rhombusd and displays its status

# Dependencies

* bash version 4
* nc (netcat)
* curl
* perl
* pv
* python
* unzip
* jq
* rhombusd, rhombus-cli
* dnsutils
