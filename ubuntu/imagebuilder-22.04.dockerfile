FROM ubuntu:22.04 

LABEL maintainer="Hao Jiang<Hao.Jiang@avnet.com>" 

# Define arguments 
ARG DEFAULT_GID 
ARG DEFAULT_UID 
ARG DEFAULT_USER 
ARG DEFAULT_PASSWD 

# Set up DEBIAN_FRONTEND 
ENV DEBIAN_FRONTEND=noninteractive 

# 更换为阿里云
RUN sed -i "s/security.ubuntu.com/mirrors.aliyun.com/" /etc/apt/sources.list && \
    sed -i "s/archive.ubuntu.com/mirrors.aliyun.com/" /etc/apt/sources.list && \
    sed -i "s/security-cdn.ubuntu.com/mirrors.aliyun.com/" /etc/apt/sources.list
RUN apt-get clean

# update the sources.list 
#RUN sed -i s@/archive.ubuntu.com/@/cn.archive.ubuntu.com/@g /etc/apt/sources.list 
RUN apt-get update -y 

# add daemon process
EXPOSE 22
RUN apt-get install -y openssh-server
# RUN sed -i 's/UsePAM yes/UsePAM no/g' /etc/ssh/sshd-config
RUN mkdir /var/run/sshd
ENTRYPOINT [ "/usr/sbin/sshd", "-D" ]

# install the missing packages 
RUN apt-get install -y apt-utils 

## Install requred packages: 
# http://www.yoctoproject.org/docs/current/ref-manual/ref-manual.html 

# Essentials 
RUN apt-get install -y \ 
    curl gawk wget git git-core diffstat unzip texinfo \ 
    build-essential chrpath socat cpio python2 python3 python3-pip python3-pexpect \ 
    python-is-python3 xz-utils debianutils iputils-ping \ 
    libsdl1.2-dev xterm libncurses5-dev \ 
    parted bc mtools dosfstools libssl-dev openssl device-tree-compiler rsync 

# Documentation
RUN apt-get install -y make xsltproc docbook-utils fop dblatex xmlto

# Extra package for build with NXP's images
RUN apt-get install -y \ 
    make vim-common tofrodos libstring-crc32-perl screen \ 
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu libc6-dev-arm64-cross

# Need lz4c pzstd unzstd zstd
RUN apt-get install liblz4-tool lz4 zstd

# Set the locale, else yocto will complain
RUN apt-get install -y locales 
RUN locale-gen en_US.UTF-8 
RUN dpkg-reconfigure locales 
ENV LANG en_US.UTF-8 
ENV LANGUAGE en_US:en 
ENV LC_ALL en_US.UTF-8

# Add repo script 
RUN apt-get install -y curl 
ENV REPO_URL='https://mirrors.tuna.tsinghua.edu.cn/git/git-repo/' 
RUN curl https://mirrors.tuna.tsinghua.edu.cn/git/git-repo -o /usr/local/bin/repo 
RUN chmod a+x /usr/local/bin/repo

# Add user and group 
RUN apt-get install -y sudo 
RUN groupadd --gid ${DEFAULT_GID} ${DEFAULT_USER} 
RUN adduser --disabled-password --uid ${DEFAULT_UID} --gid ${DEFAULT_GID} --gecos ${DEFAULT_USER} ${DEFAULT_USER} 
# RUN adduser --disabled-login --disabled-password --uid ${DEFAULT_UID} --gid ${DEFAULT_GID} --gecos ${DEFAULT_USER} ${DEFAULT_USER} 
RUN gpasswd -a ${DEFAULT_USER} sudo 
RUN newgrp sudo 
RUN /bin/echo "${DEFAULT_USER}:${DEFAULT_PASSWD}" | chpasswd
