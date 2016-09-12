
# cd ~/dkr && docker build -t steem .
# docker run -p 0.0.0.0:2001:2001 -v $PWD/data:/steem -d -t steem

FROM ubuntu:xenial
RUN apt-get update && \
	apt-get install -y gcc-4.9 g++-4.9 cmake make libbz2-dev libdb++-dev libdb-dev && \
	apt-get install -y libssl-dev openssl libreadline-dev autoconf libtool git && \
	apt-get install -y autotools-dev build-essential g++ libbz2-dev libicu-dev python-dev wget doxygen python3 python3-dev libboost-all-dev curl
# P2P (seed) port
EXPOSE 2001
# RPC port
EXPOSE 5000

ARG steemd_version=0.13.0-rc3

RUN cd ~ && \
	git clone https://github.com/steemit/steem.git && \
	cd steem && \
	git checkout ${steemd_version} && \
	git submodule update --init --recursive
#RUN cd ~/steem && export BOOST_ROOT=$HOME/opt/boost_1_60_0 && \
# don't worry about this, only needed for cherry pick
RUN git config --global user.email "you@example.com" && git config --global user.name "Your Name"
RUN cd ~/steem && \
# These cherry picks are required for 0.13 follow API to work
        git cherry-pick 2096e96eb97e4c85c0c9445ff8f0156c5ac2a620 && \
	git cherry-pick a8f34fe0e85aba4613037d895b02f3a108229b11 && \
#	cmake -DBOOST_ROOT="$BOOST_ROOT" -DCMAKE_BUILD_TYPE=Release .
	cmake -DCMAKE_BUILD_TYPE=Release . && \
	make -j3 && make install
VOLUME /steem
WORKDIR /steem

RUN echo "Please configure me! You need to mount a data directory onto /steem of this container to it to function correctly. (if you're using Steem-in-a-box most of this is handled automatically)"
CMD ["sh", "-c", "/usr/local/bin/steemd --replay-blockchain"]
