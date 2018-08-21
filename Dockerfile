FROM node:stretch

RUN ssh-keygen -A
RUN apt update
RUN apt install -y openssh-server locales curl git vim build-essential premake4 libevent-dev libsqlite3-dev liblua5.3-dev mono-complete sqlite3 p7zip-full
RUN ln -s /usr/lib/x86_64-linux-gnu/liblua5.3.so /usr/lib/liblua.so
RUN npm install pm2 -g

# 系统源
#RUN sed -i 's/deb.debian.org/ftp.cn.debian.org/g' /etc/apt/sources.list
#RUN apt update

# ssh
RUN mkdir -p /var/run/sshd
RUN mkdir /root/.ssh
RUN echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config

# locale
RUN echo "zh_CN.UTF-8 UTF-8" > /etc/locale.gen && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    locale-gen && \
    dpkg-reconfigure -f noninteractive locales tzdata && \
    /usr/sbin/update-locale LANG=zh_CN.UTF-8
ENV LANG=zh_CN.UTF-8

# declarations
EXPOSE 22
EXPOSE 7911
EXPOSE 7922
VOLUME /root

WORKDIR /root
COPY data/entrypoint.sh /entrypoint.sh
CMD [ "/entrypoint.sh" ]
