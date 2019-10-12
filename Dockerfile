FROM ubuntu:16.04

ENV ANDROID_HOME /opt/android-sdk-linux
ENV PATH ${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/tools:$PATH
ENV PORT 4723
ENV HUB_PORT 4444
ENV DEVICEUDID qwert
ENV DEVICENAME qwert
ENV ADB_PORT 5037
ENV MIN_PORT 7400
ENV MAX_PORT 7410
ENV PROXY_PORT 9000
ENV HEARTBEAT_INTERVAL 60
ENV APPIUM_LOG_LEVEL debug
ENV APPIUM_RELAXED_SECURITY --relaxed-security


##################### STF ##################
# Sneak the stf executable into $PATH.
ENV PATH /app/bin:$PATH
# Work in app dir by default.
WORKDIR /app

# Export default app port, not enough for all processes but it should do for now.
#EXPOSE 3000
############################################
#RUN mkdir -p /opt/stf

COPY files/configgen.sh /opt/configgen.sh
COPY files/adbkey.pub /root/.android/adbkey.pub
COPY files/adbkey /root/.android/adbkey

# Copy recursively files content including app source.
COPY files /opt/

RUN mkdir -p /opt/apk
RUN mkdir -p /var/lib/jenkins/workspace
RUN mkdir -p /app

RUN export DEBIAN_FRONTEND=noninteractive && \
    useradd --system \
      --create-home \
      --shell /usr/sbin/nologin \
      stf-build && \
    useradd --system \
      --create-home \
      --shell /usr/sbin/nologin \
      stf && \
    dpkg --add-architecture i386 && \
    sed -i'' 's@http://archive.ubuntu.com/ubuntu/@mirror://mirrors.ubuntu.com/mirrors.txt@' /etc/apt/sources.list && \
    apt-get update && apt-get install -y \
    curl \
    gettext-base \
    lib32ncurses5 \
    lib32stdc++6 \
    lib32z1 \
    unzip \
    wget \
    python build-essential  \
    libgtk2.0-0:i386 \
    libnss3-dev \
    libgconf-2-4 \
    dnsutils \
    telnet \
    net-tools \


# Install 8.x node and npm (6.x)
    && curl -sL https://deb.nodesource.com/setup_8.x | bash - \
    && apt-get -qqy install nodejs \

## Install nodejs
#    && cd /tmp \
#    && wget --progress=dot:mega \
#      https://nodejs.org/dist/v8.11.2/node-v8.11.2-linux-x64.tar.xz \
#    && tar -xJf node-v*.tar.xz --strip-components 1 -C /usr/local \
#    && rm node-v*.tar.xz  \

# Install STF dependencies
    && su stf-build -s /bin/bash -c '/usr/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js install' \
    && apt-get -qqy update \
    && apt-get -qqy install libzmq3-dev libprotobuf-dev git graphicsmagick yasm \
    && apt-get clean \
    && rm -rf /var/cache/apt/* /var/lib/apt/lists/* \

# Reload cache after add location of graphic libraries
    && ldconfig -v \
    && chmod +x /opt/configgen.sh

# Install add-apt-repository and ffmpeg
RUN apt-get -qqy update \
    && apt-get -qqy install software-properties-common \
    && add-apt-repository ppa:jonathonf/ffmpeg-4 \
    && apt-get -qqy update \
    && apt-get -qqy install ffmpeg

# Clone STF
RUN git clone https://github.com/qaprosoft/stf.git /opt/stf

# Give permissions to our build user.
RUN chown -R stf-build:stf-build /opt /app /usr/lib/node_modules/npm /var/lib/apt

# Switch over to the build user.
USER stf-build

# Run the build.
RUN set -x && \
    cd /opt/stf && \
    export PATH=$PWD/node_modules/.bin:$PATH && \
    npm install --loglevel http && \
    npm pack && \
    tar xzf stf-*.tgz --strip-components 1 -C /app && \
    bower cache clean && \
    npm prune --production && \
    mv node_modules /app && \
#    npm cache clean && \
    rm -rf /var/lib/apt/lists/* ~/.node-gyp /tmp/* /var/tmp/* && \
    cd /app

# Install websockify
RUN git clone https://github.com/novnc/websockify.git /opt/websockify && \
    cd /opt/websockify && make

## Switch to the app user.
##USER stf

USER root


CMD bash /opt/start_all.sh
