# Dockerfile for SRVPro
FROM node:12-stretch

# apt
RUN apt update && \
    env DEBIAN_FRONTEND=noninteractive apt install -y curl wget vim sudo git build-essential libssl1.0-dev libsqlite3-dev sqlite3 mono-complete p7zip-full redis-server

RUN npm install -g pm2

# libevent
WORKDIR /
RUN wget 'https://github.com/libevent/libevent/releases/download/release-2.0.22-stable/libevent-2.0.22-stable.tar.gz' -O libevent-2.0.22-stable.tar.gz --no-check-certificate && \
    tar xf libevent-2.0.22-stable.tar.gz && \
    cd libevent-2.0.22-stable/ && \
    ./configure && \
    make && \
    make install && \
    cd .. && \
    bash -c 'ln -s /usr/local/lib/libevent-2.0.so.5 /usr/lib/libevent-2.0.so.5;ln -s /usr/local/lib/libevent_pthreads-2.0.so.5 /usr/lib/libevent_pthreads-2.0.so.5;ln -s /usr/local/lib/libevent-2.0.so.5 /usr/lib64/libevent-2.0.so.5;ln -s /usr/local/lib/libevent_pthreads-2.0.so.5 /usr/lib64/libevent_pthreads-2.0.so.5;exit 0'

# srvpro
COPY . /ygopro-server
WORKDIR /ygopro-server
RUN npm ci && \
    mkdir config decks replays logs && \
    cp data/default_config.json config/config.json

# ygopro
RUN git clone --branch=server --recursive https://github.com/moecube/ygopro /ygopro-server/ygopro
WORKDIR /ygopro-server/ygopro
RUN git submodule foreach git checkout master && \
    wget -O - https://github.com/premake/premake-core/releases/download/v5.0.0-alpha12/premake-5.0.0-alpha12-linux.tar.gz | tar zfx - && \
    ./premake5 gmake && \
    cd build && \
    make config=release && \
    cd .. && \
    ln -s ./bin/release/ygopro . && \
    strip ygopro && \
    mkdir replay expansions

# windbot
RUN git clone https://github.com/moecube/windbot /ygopro-server/windbot
WORKDIR /ygopro-server/windbot
RUN xbuild /property:Configuration=Release /property:TargetFrameworkVersion="v4.5" && \
    ln -s ./bin/Release/WindBot.exe . && \
    ln -s /ygopro-server/ygopro/cards.cdb .

# infos
WORKDIR /
RUN mkdir /redis
EXPOSE 7911
EXPOSE 7922
VOLUME /ygopro-server/config
VOLUME /ygopro-server/ygopro/expansions

CMD [ "pm2-docker", "start", "/ygopro-server/data/pm2-docker.json" ]
