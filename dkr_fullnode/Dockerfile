
# cd ~/dkr && docker build -t steem .
# docker run -p 0.0.0.0:2001:2001 -v $PWD/data:/steem -d -t steem

FROM ubuntu:xenial
RUN apt-get update && \
	apt-get install -y gcc-4.9 g++-4.9 cmake make libbz2-dev libdb++-dev libdb-dev && \
	apt-get install -y libssl-dev openssl libreadline-dev autoconf libtool git gdb liblz4-tool wget jq virtualenv libgflags-dev libsnappy-dev zlib1g-dev libbz2-dev liblz4-dev libzstd-dev && \
	apt-get install -y autotools-dev build-essential g++ libbz2-dev libicu-dev python-dev wget doxygen python3 python3-dev python3-pip libboost-all-dev curl && \
        apt-get clean -qy && \
        pip3 install jinja2

# P2P (seed) port
EXPOSE 2001
# RPC ports
EXPOSE 8091
EXPOSE 8090

ARG steemd_version=stable
ARG STEEM_STATIC_BUILD=ON
ENV STEEM_STATIC_BUILD ${STEEM_STATIC_BUILD}

RUN cd ~ && \
	git clone https://github.com/steemit/steem.git && \
	cd steem && \
	git checkout ${steemd_version} && \
	git submodule update --init --recursive && \
        cd ~/steem && \
	cmake -DCMAKE_BUILD_TYPE=Release . \
            -DCLEAR_VOTES=OFF \
            -DLOW_MEMORY_NODE=OFF \
            -DSTEEM_STATIC_BUILD=${STEEM_STATIC_BUILD} \
            -DSKIP_BY_TX_ID=OFF && \
	make -j$(nproc) && make install && rm -rf ~/steem
VOLUME /steem
WORKDIR /steem

RUN echo "Please configure me! You need to mount a data directory onto /steem of this container to it to function correctly. (if you're using Steem-in-a-box most of this is handled automatically)"
CMD ["sh", "-c", "/usr/bin/steemd"]
