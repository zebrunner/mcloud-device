FROM ubuntu:16.04

ENV ANDROID_HOME /opt/mcloud/android-sdk-linux
ENV PATH ${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/build-tools:$PATH

ENV PORT 4723
ENV SELENIUM_HUB_HOST selenium-hub
ENV SELENIUM_HUB_PORT 4444
ENV DEVICEUDID qwert
ENV DEVICENAME qwert
ENV ADB_PORT 5037
ENV MIN_PORT 7400
ENV MAX_PORT 7410
ENV PROXY_PORT 9000
ENV APPIUM_LOG_LEVEL debug
ENV APPIUM_RELAXED_SECURITY --relaxed-security


##################### STF ##################
# Sneak the stf executable into $PATH.
ENV PATH /app/bin:$PATH
# Work in app dir by default.
WORKDIR /app

COPY files/configgen.sh /opt/configgen.sh
COPY files/adbkey.pub /root/.android/adbkey.pub
COPY files/adbkey /root/.android/adbkey

COPY files/healthcheck /usr/local/bin/

COPY files/configgen.sh /opt/
COPY files/start_all.sh /opt/

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
    openjdk-8-jdk \
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
    nano \

# Install 8.x and 10.x node and npm (6.x)
    && curl -sL https://deb.nodesource.com/setup_8.x | bash - \
    && apt-get -qqy install nodejs \
    && curl -sL https://deb.nodesource.com/setup_10.x | bash - \
    && apt-get install -y nodejs

#===============
# Set JAVA_HOME
#===============
ENV JAVA_HOME="/usr/lib/jvm/java-8-openjdk-amd64/jre"

# Install STF dependencies
RUN npm link --force node@8 \
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
RUN git clone --single-branch --branch master https://github.com/qaprosoft/stf.git /opt/stf

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
    mv node_modules/* /app/node_modules/ && \
#    npm cache clean && \
    rm -rf /var/lib/apt/lists/* ~/.node-gyp && \
    cd /app

# Install websockify
RUN git clone https://github.com/novnc/websockify.git /opt/websockify && \
    cd /opt/websockify && make

# Unable to use stf user as device can not be detected by adb!
## Switch to the app user.
#USER stf

USER root
RUN rm -rf /tmp/* /var/tmp/*

CMD bash /opt/start_all.sh

HEALTHCHECK CMD ["healthcheck"]
