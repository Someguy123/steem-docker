# How to upgrade or install new a "STEEM-in-a-box" witness server

## Introduction

This document shows you how to:
* Install and run a STEEM Witness Server  
* Upgrade a STEEM witness server

The approach is called "STEEM-in-a-box" because all of the required executables and dependencies are prepackaged in a docker image. This makes it easier for novices to run a STEEM witness server.

To learn more about witnesses and what they do, check out someguy123's article: https://steemit.com/witness-category/@someguy123/seriously-what-is-a-witness-why-should-i-care-how-do-i-become-one-answer

## About the contributors

The primary contributor of "STEEM-in-a-box" and author this content is someguy123, a well-known third-party developer for STEEM, and Litecoin. For more information, see https://steemit.com/@someguy123. His witness server is among the top ranking servers: https://steemit.com/~witnesses. 

The other contributors to this repo are:
* https://steemit.com/@someguy123
* https://steemit.com/@oropeso

Please take a minute to show your support by:
* Following each contributor
* Voting for each contributor to be a witness

## New features in this release of "STEEM-in-a-box"
* `dlblocks` downloads blocks from [@gtg's](https://steemit.com/@gtg) server and decompresses them in the appropriate folder.
* `install_docker` downloads and installs docker. If you're not running it as root, it automatically adds your current user to the docker group.
* `remote_wallet` runs `cli_wallet` against steemd.steemit.com

## How to upgrade your STEEM-in-a-box to the current release

The following instructions show you to upgrade from version HF18 to version HF19, the current release.

[//]: # Are these instructions restricted to HF18 or do they work for any version?

1. Update the steem-in-a-box scripts. Using a terminal/command line, `cd` to the directory that contains the previous installation and enter the following command:
```
git pull
```

[//]: # Do I have to fork the repo first? 

1. Disable your witness, or change it to your backup key.
```
./run.sh wallet

locked>> unlock "your-super-secure-password"
unlocked>> update_witness "your-username" "your-url" "STMyour-super-secure-password" {"account_creation_fee":"0.200 STEEM","maximum_block_size":131072,"sbd_interest_rate":0} true
```

1. Stop the witness server.
```
./run.sh stop
```

1. Delete the `./dev/shm` files, which are not compatible with HF19 and need to be rebuilt.
```
rm -rf /dev/shm/*
```

1. Update your STEEM image, then start it with replay.
```
./run.sh install
./run.sh replay
```

1. Check the logs by entering `./run.sh logs`. Verify that the witness server is rescanning the blockchain. 

[//]: # What should the users look for? The same information about logs shown later on? 

1. After the server has replayed the blockchain, re-broadcast your witness. Replace the username, URL, and password placeholders with your own information.

```
update_witness "your-steem-username" "your-url" "STMyour-ultra-secret-password" {"account_creation_fee":"0.200 STEEM","maximum_block_size":131072,"sbd_interest_rate":0} true
```

[//]: # Are all of the values show good defaults? 

## Installing a NEW witness server

The following instructions show you how to install (not upgrade) a "STEEM-in-a-box" witness server, version HF19.

### Hardware requirements
* 8GB of RAM minimum (12GB recommended)
* 100GB disk
* a fast, reliable network

### Advice on choosing a VPS service to host your witness server

someguy123: 

"I am the CEO of [@privex](https://steemit.com/@privex) - A VPS provider that accepts STEEM, is affordable, and [sells servers with a Zero Block Miss SLA](https://steemit.com/introduceyourself/@privex/we-are-privex-inc-we-accept-steem-protecting-your-privacy-in-the-cloud).

I use @privex for my own witness. As a proof of their quality, I haven't missed a block since moving to them TBD, and I get almost 60 blocks per day. (As of May 2017)

You'll find plenty of people here on STEEM unaffiliated with us, praising our servers and network."

You're free to use any other server provider. I don't recommend running a witness server on your home internet; it is unlikely to be reliable enough for that purpose.

Be aware that certain server providers have poor networks or hardware that may cause missed blocks. So, you may need to try a few before you find one that's reliable enough for a witness node. 

To learn more about witnesses and what they do, check out my article: https://steemit.com/witness-category/@someguy123/seriously-what-is-a-witness-why-should-i-care-how-do-i-become-one-answer
"

### Secure your server

Instructions on securing your server are outside the scope of this document; too many details depend on the platform you choose. 

We recommend securing your server and network before proceeding. You should research topics on "securing your VPS" and "securing your docker server".

[//]: # This is a great place to provide links to relevant topics online.

### Install the witness server

1. Install some basic dependencies. The following commands assume you're on Ubuntu. 
```
sudo apt update
sudo apt install git curl wget
```

1. Download the steem-in-a-box repo.
```
git clone https://github.com/Someguy123/steem-docker.git
cd steem-docker
```

1. Install Docker.
```
./run.sh install_docker
```

1. If you are not logged in as root:
    a. Wait for the previous command to finish installing Docker. 
    b. Log out and back in again. 
    c. Enter `cd steem-docker`.

1. Download the pre-compiled STEEM image from DockerHub:
```
./run.sh install
```


1. ***A new feature in the HF19 Steem-in-a-box automatically downloads blocks from @gtg's server, extracts them, and puts them in the right folder. This process takes a while, but dramatically shortens your setup time.***

To use this feature, enter:
```
./run.sh dlblocks
```

1. If you are a witness and you want to run a seed, don't touch the config! Open the wallet using a public server with the following command:
```
./run.sh remote_wallet
```

[//]: # Do I want to run a seed? Guide me.

1. Create a key pair for your witness.
```
suggest_brain_key
```

This command returns the something similar to this:
```
"wif_priv_key": "5xxxxxxxxxxxxxxxxxxx",
"pub_key": "STMxxxxxxxxxxxxxxxxx"
```

1. Copy and paste these keys into notepad or something similar so you don't lose them.

1. Press **CTRL-D** to exit the wallet.

1. Decide how much "shared memory" to give the server.  **8GB** is the bare minimum. However **12GB** is recommended. 

***Warning: DO NOT GIVE MORE SHARED MEMORY THAN THE AMOUNT OF AVAILABLE RAM. For example, if you have an 8GB VPS, only use 8G for your shared memory.***

1. Set the amount of shared memory. For example:
```
sudo ./run.sh shm_size 12G
```

1. Open the config file in your favourite text editor. This example shows how to do it using Nano, an editor that is good for beginners.
```
nano data/witness_node_data_dir/config.ini
```

1. If you are a witness, do not run a seed: Disable it by using `#` to commenting-out the following line, as shown here:
```
# p2p-endpoint = 0.0.0.0:2001
```

[//]: # So I SHOULDN'T run a seed? Does this negate any of the steps I did earlier? Guide me.


1. Use a blank line to add your witness name and private key.
```
witness = "YOUR STEEM NAME GOES HERE WITHOUT THE @ SIGN"
private-key = 5xxxxxxxxxxxxx
```

Note:
* Put quotes around your witness name.
* Do not include the @ sign before your steem name.
* Do not put quotes around your private key.
* Get the private key you previously copied from `wif_priv_key` to notepad.

1. Set the value of `shared-file-size` to the same amount of shared memory you set earlier when you used `sudo ./run.sh shm_size`. For example:

```
shared-file-size = 12G
```

1. Save and close the configuration file. (With nano, press **CTRL-X** and choose **yes**.)

1. Adjust the steem-in-a-box settings so it is named correctly, and disable port forwarding for seeds. 
    
    a. First, create a `.env` file to hold the settings.
```
nano .env
```

    b. The file will be blank. In the file put the following:
```
PORTS=
DOCKER_NAME=witness
```

1. Save and close the file with **CTRL-X**.

1. Start the witness server.
```
./run.sh replay
```

### Verify that your witness server is running correctly

1. Check the logs with this command:
```
./run.sh logs
```

You should see something similar to this:
```
344773ms th_a       application.cpp:297           startup              ] Replaying blockchain on user request.
344774ms th_a       database.cpp:151              reindex              ] Reindexing Blockchain
344823ms th_a       block_log.cpp:130             open                 ] Log is nonempty
344823ms th_a       block_log.cpp:139             open                 ] Index is nonempty
344823ms th_a       database.cpp:159              reindex              ] Replaying blocks...
344834ms th_a       database.cpp:2571             show_free_memory     ] Free memory is now 11G
   0.77369%   100000 of 12925066   (12282M free)
```

If you see lots of red error messages, something went wrong. You can ask for help debugging it in the witness channel on [STEEMIT.CHAT](https://steemit.chat/channel/witness).

If it appears to be working, leave it for an hour or so. Check the logs every 10 minutes until you see something like this:
```
1299055ms th_a       application.cpp:507           handle_block         ] Got 14 transactions on block 12928269 by pharesim -- latency: 55 ms
1302427ms th_a       application.cpp:507           handle_block         ] Got 18 transactions on block 12928270 by xeldal -- latency: 426 ms
1305291ms th_a       application.cpp:507           handle_block         ] Got 26 transactions on block 12928271 by arhag -- latency: 291 ms
1308045ms th_a       application.cpp:507           handle_block         ] Got 20 transactions on block 12928272 by pfunk -- latency: 45 ms
1311092ms th_a       application.cpp:507           handle_block         ] Got 23 transactions on block 12928273 by bhuz -- latency: 92 ms
```

This means your witness is now fully synced.

### Connect your Steemit account to your witness server

On steemit.com:

1. Go to your profile on Steemit, click **Wallet > Permissions**. 

1. In Permissions, find **Active Key**, click **Login to show**, and log in.

1. Click **Show private key**. Verify that it begins with a "5".

1. Copy the private key.

On the command line session with your server:

1. Open the wallet.
```
./run.sh wallet
```

1. Set a password and use it to unlock the wallet.

1. Import your ACTIVE private key from steemit (NOT the one in notepad):
```
set_password "mysupersecurepass"
unlock "mysupersecurepass"
import_key 5zzzzzzzzzzzz
```

1. Update/create the witness on the network. 

1. Replace the STMxxxx key with the public key you saved earlier in notepad, and replace YOURNAME with your witness name on Steemit.
```
update_witness "YOURNAME" "https://steemit.com/witness-category/@YOURNAME/my-witness-thread" "STMxxxxxxx" {"account_creation_fee":"0.200 STEEM","maximum_block_size":131072,"sbd_interest_rate":0} true
```

1. Assuming there are no big red messages, you're now a witness! :)

### Follow up actions
* Go ahead, [vote for yourself](https://steemit.com/~witnesses) 
* How do you know what rank you are? Check SteemDB: https://steemdb.com/witnesses or steemd: https://steemd.com/witnesses
* What about a price feed? As a witness, you're expected to run a price feed. I recommend [Steemfeed-JS](https://steemit.com/witness-category/@someguy123/steemfeed-js-a-nodejs-price-feed-for-witneses), as it goes nicely with the docker set up.

### If you appreciated this tutorial

Please follow and vote for these contributors to be witnesses:
* https://steemit.com/@someguy123
* https://steemit.com/@oropeso
* TBD

- every vote and every follow counts!
