FROM public.ecr.aws/zebrunner/stf:2.6.5

# https://github.com/zebrunner/android-device/issues/70
#    gray screen on android after 48 hours without restart
# https://github.com/openstf/stf/issues/100
ENV ZMQ_TCP_KEEPALIVE=1
ENV ZMQ_TCP_KEEPALIVE_IDLE=600
#ENV ZMQ_IPV6=

ENV STF_PROVIDER_ADB_HOST=appium
ENV STF_PROVIDER_ADB_PORT=5037

ENV STF_PROVIDER_PUBLIC_IP=localhost
ENV PUBLIC_IP_PORT=80
ENV PUBLIC_IP_PROTOCOL=http

ENV PLATFORM_NAME=android
ENV STF_PROVIDER_DEVICE_NAME=

ENV STF_PROVIDER_HOST=
ENV STF_PROVIDER_CONNECT_SUB=
ENV STF_PROVIDER_CONNECT_PUSH=

# make sure to keep commented to be able to start android stf-provider correctly
#ENV STF_PROVIDER_CONNECT_APP_DEALER=
#ENV STF_PROVIDER_CONNECT_DEV_DEALER=

ENV STF_PROVIDER_BOOT_COMPLETE_TIMEOUT=60000
ENV STF_PROVIDER_CLEANUP=false
ENV STF_PROVIDER_GROUP_TIMEOUT=3600
ENV STF_PROVIDER_HEARTBEAT_INTERVAL=10000
ENV STF_PROVIDER_LOCK_ROTATION=false
ENV STF_PROVIDER_MIN_PORT=7404
ENV STF_PROVIDER_MAX_PORT=7410
ENV STF_PROVIDER_MUTE_MASTER=never
ENV STF_PROVIDER_SCREEN_JPEG_QUALITY=30
ENV STF_PROVIDER_SCREEN_PING_INTERVAL=30000
# disable screen reset by default to not hide applications and corrupt automated runs
ENV STF_PROVIDER_SCREEN_RESET=false
ENV STF_PROVIDER_VNC_INITIAL_SIZE=600x800
ENV STF_PROVIDER_VNC_PORT=5900

# #56 disable ssl verification by stf provider slave (fix screenshots generation over ssl)
ENV NODE_TLS_REJECT_UNAUTHORIZED=0

# WebDriverAgent vars
ENV WDA_HOST=appium
ENV WDA_PORT=8100
ENV MJPEG_PORT=8101
ENV WDA_WAIT_TIMEOUT=30

# Usbmuxd vars
ENV USBMUXD_SOCKET_ADDRESS=appium:22
ENV USBMUXD_SOCKET_TIMEOUT=60
ENV USBMUXD_SOCKET_PERIOD=5

# Debug mode vars
ENV DEBUG=false
ENV DEBUG_TIMEOUT=3600
ENV VERBOSE=false

# Need root user to clear existing /var/run/usbmuxd socket if any
USER root

COPY files/debug.sh /opt/
COPY files/healthcheck /usr/local/bin/
COPY files/start_all.sh /opt/
CMD bash /opt/start_all.sh

RUN apt-get -y update && \
    apt-get -y install netcat && \
    rm -rf /var/lib/apt/lists/*

HEALTHCHECK CMD ["healthcheck"]
