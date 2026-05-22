ARG BASE_IMAGE=git-registry.moenext.com/mycard/srvpro:lite
ARG GIT_IMAGE=alpine/git:v2.52.0
ARG MONO_IMAGE=mono:6.12
ARG WINDBOT_REPO=https://code.moenext.com/mycard/windbot
ARG WINDBOT_BRANCH=master
ARG WINDBOT_TARGET_FRAMEWORK=v4.8

FROM ${GIT_IMAGE} AS windbot-source
ARG WINDBOT_REPO
ARG WINDBOT_BRANCH
WORKDIR /usr/src
RUN git clone --branch="${WINDBOT_BRANCH}" --depth=1 "${WINDBOT_REPO}" windbot-src

FROM ${MONO_IMAGE} AS windbot-builder
ARG WINDBOT_TARGET_FRAMEWORK
COPY --from=windbot-source /usr/src/windbot-src /usr/src/windbot
WORKDIR /usr/src/windbot
RUN xbuild /property:Configuration=Release /property:TargetFrameworkVersion="${WINDBOT_TARGET_FRAMEWORK}"

FROM ${BASE_IMAGE}
LABEL Author="Nanahira <nanahira@momobako.com>"

RUN apk add --no-cache mono && \
    npm install -g pm2 && \
    npm cache clean --force

# windbot
COPY --from=windbot-builder /usr/src/windbot/bin/Release /ygopro-server/windbot
RUN ln -s /ygopro-server/ygopro/cards.cdb /ygopro-server/windbot/cards.cdb

CMD [ "pm2-docker", "start", "/ygopro-server/data/pm2-docker.json" ]
