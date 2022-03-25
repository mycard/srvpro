ARG BASE_IMAGE=git-registry.mycard.moe/mycard/srvpro:lite
FROM $BASE_IMAGE
LABEL Author="Nanahira <nanahira@momobako.com>"

RUN apt update && \
    apt -y install mono-complete && \
    npm install -g pm2 && \
    rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/* /var/log/*

# windbot
RUN git clone --depth=1 https://code.mycard.moe/mycard/windbot /tmp/windbot && \
    cd /tmp/windbot && \
    xbuild /property:Configuration=Release /property:TargetFrameworkVersion="v4.5" && \
    mv /tmp/windbot/bin/Release /ygopro-server/windbot && \
    cp -rf /ygopro-server/ygopro/cards.cdb /ygopro-server/windbot/ && \
    rm -rf /tmp/windbot

CMD [ "pm2-docker", "start", "/ygopro-server/data/pm2-docker.json" ]
