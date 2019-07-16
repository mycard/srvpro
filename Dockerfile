# Dockerfile for SRVPro
FROM node:12-stretch-slim

# apt
RUN apt update && \
    env DEBIAN_FRONTEND=noninteractive apt install -y wget git build-essential libevent-dev libsqlite3-dev mono-complete p7zip-full redis-server

RUN npm install -g pm2

# srvpro
COPY . /ygopro-server
WORKDIR /ygopro-server
RUN npm ci && \
    mkdir config decks replays logs /redis

# ygopro
RUN git clone --branch=server --recursive --depth=1 https://github.com/moecube/ygopro /ygopro-server/ygopro
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
RUN git clone --depth=1 https://github.com/moecube/windbot /ygopro-server/windbot
WORKDIR /ygopro-server/windbot
RUN xbuild /property:Configuration=Release /property:TargetFrameworkVersion="v4.5" && \
    ln -s ./bin/Release/WindBot.exe . && \
    ln -s /ygopro-server/ygopro/cards.cdb .

# infos
WORKDIR /ygopro-server
EXPOSE 7911 7922 7933
# VOLUME [ /ygopro-server/config, /ygopro-server/decks, /ygopro-server/replays, /redis ]

CMD [ "pm2-docker", "start", "/ygopro-server/data/pm2-docker.json" ]
