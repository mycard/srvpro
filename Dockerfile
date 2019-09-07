# Dockerfile for SRVPro
FROM node:12-stretch-slim

RUN npm install -g pm2

# apt
RUN apt update && \
    env DEBIAN_FRONTEND=noninteractive apt install -y wget git build-essential libevent-dev libsqlite3-dev mono-complete p7zip-full redis-server && \
    rm -rf /var/lib/apt/lists/*

# srvpro
COPY . /ygopro-server
WORKDIR /ygopro-server
RUN npm ci && \
    mkdir config decks replays logs /redis

# ygopro
RUN git clone --branch=server --recursive --depth=1 https://github.com/moecube/ygopro && \
    cd ygopro && \
    git submodule foreach git checkout master && \
    wget -O - https://github.com/premake/premake-core/releases/download/v5.0.0-alpha13/premake-5.0.0-alpha13-linux.tar.gz | tar zfx - && \
    ./premake5 gmake && \
    cd build && \
    make config=release && \
    cd .. && \
    mv ./bin/release/ygopro . && \
    strip ygopro && \
    mkdir replay expansions && \
    rm -rf .git* bin obj build ocgcore cmake lua premake* sound textures .travis.yml *.txt appveyor.yml LICENSE README.md *.lua strings.conf system.conf && \
    ls gframe | sed '/game.cpp/d' | xargs -I {} rm -rf gframe/{}

# windbot
RUN git clone --depth=1 https://github.com/moecube/windbot /tmp/windbot && \
    cd /tmp/windbot && \
    xbuild /property:Configuration=Release /property:TargetFrameworkVersion="v4.5" && \
    mv /tmp/windbot/bin/Release /ygopro-server/windbot && \
    cp -rf /ygopro-server/ygopro/cards.cdb /ygopro-server/windbot/ && \
    rm -rf /tmp/windbot

# infos
WORKDIR /ygopro-server
EXPOSE 7911 7922 7933
# VOLUME [ /ygopro-server/config, /ygopro-server/decks, /ygopro-server/replays, /redis ]

CMD [ "pm2-docker", "start", "/ygopro-server/data/pm2-docker.json" ]
