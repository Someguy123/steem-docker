
# cd ~/dkr && docker build -t steem .
# docker run -p 0.0.0.0:2001:2001 -v $PWD/data:/steem -d -t steem

FROM ubuntu:xenial
RUN apt-get update && \
	apt-get install -y gcc-4.9 g++-4.9 cmake make libbz2-dev libdb++-dev libdb-dev && \
	apt-get install -y libssl-dev openssl libreadline-dev autoconf libtool git && \
	apt-get install -y autotools-dev build-essential g++ libbz2-dev libicu-dev python-dev wget doxygen python3 python3-dev libboost-all-dev curl

ARG steemd_version=0.13.0-rc3

RUN cd ~ && \
	git clone https://github.com/steemit/steem.git && \
	cd steem && \
	git checkout ${steemd_version} && \
	git submodule update --init --recursive
#RUN cd ~/steem && export BOOST_ROOT=$HOME/opt/boost_1_60_0 && \
RUN cd ~/steem && \
#	cmake -DBOOST_ROOT="$BOOST_ROOT" -DCMAKE_BUILD_TYPE=Release .
	cmake -DCMAKE_BUILD_TYPE=Release . && \
	make -j3 && make install

WORKDIR /steem

CMD ["sh", "/steem/run.sh"]
