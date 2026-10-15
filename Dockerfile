# check=skip=SecretsUsedInArgOrEnv
# STF_STORAGE_TOKEN is declared empty as documentation of the supported env vars; the real value is passed at runtime

# The tools of the image do not depend on the STF base image, which drops them (zebrunner/stf#1052).
# go-ios of mcloud-ios-connector is built from its sources without cgo: a static binary, the release binaries need
# glibc 2.34 and the stf:2.7 base image (Ubuntu 20.04) has 2.31. websocat is the static musl build.
# The stage runs on the platform of the builder, the binaries are linux/amd64
FROM --platform=${BUILDPLATFORM} golang:1.26.5-alpine@sha256:0178a641fbb4858c5f1b48e34bdaabe0350a330a1b1149aabd498d0699ff5fb2 AS tools

WORKDIR /go-ios
RUN wget -q -O /tmp/go-ios.tar.gz https://github.com/danielpaulus/go-ios/archive/refs/tags/v1.3.2.tar.gz && \
    echo "ee5283359650cd7040f785d0eb8c6376b09bca3255cb20bcbfc4e8769f4a25bb  /tmp/go-ios.tar.gz" > /tmp/go-ios.sha256 && \
    sha256sum -c /tmp/go-ios.sha256 && \
    tar -xzf /tmp/go-ios.tar.gz --strip-components 1 && \
    rm -f /tmp/go-ios.tar.gz /tmp/go-ios.sha256 && \
    # the version of the release build, `ios --version` prints it
    sed -i 's/^const version = "local-build"$/const version = "1.3.2"/' main.go && \
    grep -q '^const version = "1.3.2"$' main.go && \
    env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GOTOOLCHAIN=local go build -trimpath -ldflags="-s -w" -o /out/ios && \
    wget -q -O /out/websocat https://github.com/vi/websocat/releases/download/v1.13.0/websocat_max.x86_64-unknown-linux-musl && \
    echo "c3a63a2a77d1abf5baef5bbf7474690ac2896e2dabd60498e56361a2fd131d8f  /out/websocat" > /tmp/websocat.sha256 && \
    sha256sum -c /tmp/websocat.sha256 && \
    chmod 755 /out/websocat

FROM public.ecr.aws/zebrunner/stf:2.7@sha256:4b1fed9604c11318c622eda624bf50037fa02f8ac73a98ee92f03e5479622a68

# The base image is linux/amd64 only (its STF build), so are go-ios and websocat: another platform would build
# an image with amd64 binaries, so the build stops
ARG TARGETARCH
RUN if [ -n "${TARGETARCH}" ] && [ "${TARGETARCH}" != "amd64" ]; then \
      echo "[error] the image is linux/amd64 only: the base image is amd64 only, got ${TARGETARCH}" >&2; \
      exit 1; \
    fi

USER root

# socat: the reachability checks and the usbmuxd forwarding, curl: WebDriverAgent, procps: pgrep of the healthcheck.
# The usbmuxd socket forwarded by entrypoint.sh is in a dir of stf (/var/run is root only), the restart counter of the
# unreachable STF services is in /tmp/zebrunner
RUN apt-get update && \
    env DEBIAN_FRONTEND=noninteractive apt-get -y install --no-install-recommends \
        socat curl procps && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /tmp/usbmuxd /tmp/zebrunner && \
    chown stf:stf /tmp/usbmuxd /tmp/zebrunner && \
    rm -f /var/run/usbmuxd && \
    ln -s /tmp/usbmuxd/usbmuxd /var/run/usbmuxd

# go-ios: the iOS commands of STF (install, launch, reboot), it replaces the one of the base image;
# websocat: the screen broadcast of BROADCAST_PORT
COPY --from=tools /out/ios /out/websocat /usr/local/bin/
RUN ios --version && \
    websocat --version

# The defaults of the configuration, all of them are documented in README.md.
# The provider of Android reads every STF_PROVIDER_* variable as its option (STF_PROVIDER_MIN_PORT is --min-port)
ENV \
    # Device
    PLATFORM_NAME=android \
    DEVICE_UDID="" \
    WIRELESS=false \
    # STF services
    STF_PROVIDER_CONNECT_PUSH="" \
    STF_PROVIDER_CONNECT_SUB="" \
    STF_PROVIDER_CONNECT_APP_DEALER="" \
    STF_PROVIDER_CONNECT_DEV_DEALER="" \
    RETHINKDB_PORT_28015_TCP="" \
    STF_STORAGE_TOKEN="" \
    STF_SERVICES_WAIT_TIMEOUT=300 \
    STF_SERVICES_WAIT_RETRY=30 \
    STF_SERVICES_WAIT_RESTARTS=2 \
    # Public address of STF
    STF_PROVIDER_PUBLIC_IP=localhost \
    PUBLIC_IP_PORT=80 \
    PUBLIC_IP_PROTOCOL=http \
    # STF provider
    STF_PROVIDER_NAME="" \
    STF_PROVIDER_HOST="" \
    STF_PROVIDER_DEVICE_NAME="" \
    STF_PROVIDER_ADB_HOST=connector \
    STF_PROVIDER_ADB_PORT=5037 \
    STF_PROVIDER_MIN_PORT=7404 \
    STF_PROVIDER_MAX_PORT=7410 \
    STF_PROVIDER_BOOT_COMPLETE_TIMEOUT=60000 \
    STF_PROVIDER_CLEANUP=false \
    STF_PROVIDER_GROUP_TIMEOUT=3600 \
    STF_PROVIDER_HEARTBEAT_INTERVAL=10000 \
    STF_PROVIDER_LOCK_ROTATION=false \
    STF_PROVIDER_MUTE_MASTER=never \
    STF_PROVIDER_SCREEN_JPEG_QUALITY=30 \
    STF_PROVIDER_SCREEN_PING_INTERVAL=30000 \
    STF_PROVIDER_SCREEN_RESET=false \
    STF_PROVIDER_VNC_INITIAL_SIZE=600x800 \
    STF_PROVIDER_VNC_PORT=5900 \
    BROADCAST_PORT=2223 \
    # ZeroMQ keepalive against the gray screen after 48 hours (zebrunner/android-device#70, openstf/stf#100)
    ZMQ_TCP_KEEPALIVE=1 \
    ZMQ_TCP_KEEPALIVE_IDLE=600 \
    # #56 the screenshots of the storage behind a self-signed certificate
    NODE_TLS_REJECT_UNAUTHORIZED=0 \
    # iOS: WebDriverAgent
    WDA_HOST=connector \
    WDA_PORT=8100 \
    MJPEG_PORT=8101 \
    WDA_WAIT_TIMEOUT=30 \
    # iOS: usbmuxd "host:port"
    USBMUXD_SOCKET_ADDRESS=connector:2222 \
    USBMUXD_SOCKET_TIMEOUT=60 \
    USBMUXD_SOCKET_PERIOD=5 \
    # Logger
    LOGGER_LEVEL=INFO \
    # Debug mode
    DEBUG=false \
    DEBUG_TIMEOUT=3600 \
    VERBOSE=false

COPY util/ /opt/zebrunner/util/
COPY entrypoint.sh /opt/zebrunner/

USER stf

ARG VERSION=dev
LABEL org.opencontainers.image.title="Zebrunner MCloud Device" \
      org.opencontainers.image.description="STF provider of an Android or iOS device of Zebrunner MCloud" \
      org.opencontainers.image.source="https://github.com/zebrunner/mcloud-device" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="${VERSION}"

ENTRYPOINT ["/opt/zebrunner/entrypoint.sh"]

# STF starts after the STF services, usbmuxd and WebDriverAgent are reachable (iOS), see README.md
HEALTHCHECK --interval=20s --timeout=5s --start-period=120s --start-interval=10s --retries=3 \
    CMD ["pgrep", "-f", "stf (provider|ios-device)"]
