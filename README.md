# Zebrunner MCloud Device

The STF provider of one Android or iOS device of [Zebrunner MCloud](https://github.com/zebrunner/mcloud): the `device-<udid>-stf` container that [mcloud-agent](https://github.com/zebrunner/mcloud-agent) starts next to the connector, appium and uploader containers of every device. It waits for the STF services (and for usbmuxd and WebDriverAgent of an iOS device), then runs the provider of [STF](https://github.com/zebrunner/stf) for the device: `stf provider` for Android, `stf ios-device` for iOS.

The image is based on the STF image `public.ecr.aws/zebrunner/stf` (Ubuntu 20.04) and runs on `linux/amd64` only, as its base image.

> Follow the installation and configuration guide in [MCloud](https://github.com/zebrunner/mcloud) to reuse this image effectively.

## Image contents

| Component | Version |
| --- | --- |
| Base image | `public.ecr.aws/zebrunner/stf:2.7` (pinned by digest) |
| [go-ios](https://github.com/danielpaulus/go-ios) | 1.3.2, the version of [mcloud-ios-connector](https://github.com/zebrunner/mcloud-ios-connector); it replaces the go-ios of the base image |
| [websocat](https://github.com/vi/websocat) | 1.13.0 |

STF runs the go-ios commands `ios install`, `ios launch` and `ios reboot` for an iOS device. The release binaries of go-ios need glibc 2.34 and the base image has 2.31, so go-ios is built from its sources (checked by SHA-256) without cgo by `golang:1.26.5-alpine`: a static binary of the same version.

Everything the build downloads is pinned: the images by version and digest, go-ios and websocat by version and SHA-256. The image installs no packages of the distribution.

## Build

```bash
docker build --platform linux/amd64 --build-arg VERSION=3.1 --tag public.ecr.aws/zebrunner/mcloud-device:3.1 .
```

## Run

mcloud-agent creates the container (`roles/devices/templates/zebrunner-farm`, `roles/mac-devices/templates/zebrunner-farm`), linked to the connector container of the device as `connector`:

```bash
# Android
docker run -d --name device-<udid>-stf --restart on-failure:50 --link device-<udid>-connector:connector \
  -e PLATFORM_NAME=android -e DEVICE_UDID=<udid> -e STF_PROVIDER_DEVICE_NAME="Pixel 8" \
  -e STF_PROVIDER_NAME=mcloud-linux -e STF_PROVIDER_HOST=agent.example.com \
  -e STF_PROVIDER_MIN_PORT=7404 -e STF_PROVIDER_MAX_PORT=7410 -p 7404-7410:7404-7410 \
  -e STF_PROVIDER_PUBLIC_IP=stf.example.com -e PUBLIC_IP_PORT=443 -e PUBLIC_IP_PROTOCOL=https \
  -e STF_PROVIDER_CONNECT_SUB=tcp://stf.example.com:7250 -e STF_PROVIDER_CONNECT_PUSH=tcp://stf.example.com:7270 \
  -e RETHINKDB_PORT_28015_TCP=tcp://stf.example.com:28015 -e STF_STORAGE_TOKEN=<token> \
  public.ecr.aws/zebrunner/mcloud-device:<version>
# iOS: the same with
#   -e PLATFORM_NAME=ios -e WDA_HOST=connector -e WDA_WAIT_TIMEOUT=60
#   -e STF_PROVIDER_CONNECT_APP_DEALER=tcp://stf.example.com:7160 -e STF_PROVIDER_CONNECT_DEV_DEALER=tcp://stf.example.com:7260
# a wireless tvOS device has no connector: -e WIRELESS=true -e WDA_HOST=<host of its WebDriverAgent> -e WDA_PORT=<port>
```

## Configuration

Every variable has its default in the `Dockerfile`. The entrypoint validates the configuration before anything starts: every invalid variable is logged, then it exits with `0`. The numeric variables of the table must be non-negative integers, `STF_PROVIDER_MIN_PORT` must not be greater than `STF_PROVIDER_MAX_PORT`.

### Device

| Variable | Default | Description |
| --- | --- | --- |
| `PLATFORM_NAME` | `android` | `android` or `ios`, case-insensitive. |
| `DEVICE_UDID` | empty | The UDID of the device, required for iOS (`--serial` of `stf ios-device`). The provider of Android serves the device of the adb server of `STF_PROVIDER_ADB_HOST`. |
| `WIRELESS` | `false` | `true` for an iOS device without a usb path (e.g. an Apple TV reached over a network tunnel of the host): usbmuxd is not forwarded, only WebDriverAgent of `WDA_HOST` is needed. mcloud-agent sets it for the wireless devices. |

### STF services

| Variable | Default | Description |
| --- | --- | --- |
| `STF_PROVIDER_CONNECT_PUSH` | empty | The ZeroMQ PULL endpoint of STF, `tcp://<host>:<port>`, required. |
| `STF_PROVIDER_CONNECT_SUB` | empty | The ZeroMQ PUB endpoint of STF, `tcp://<host>:<port>`, required. |
| `STF_PROVIDER_CONNECT_APP_DEALER` | empty | The app-side ZeroMQ DEALER endpoint, `tcp://<host>:<port>`, required for iOS. It is not an option of the provider of Android, so it is removed from its environment. |
| `STF_PROVIDER_CONNECT_DEV_DEALER` | empty | The device-side ZeroMQ DEALER endpoint, `tcp://<host>:<port>`, required for iOS, removed for Android as above. |
| `RETHINKDB_PORT_28015_TCP` | empty | RethinkDB of STF, `tcp://<host>:<port>`, required. |
| `STF_STORAGE_TOKEN` | empty | The token of the storage of STF (`x-stf-internal-token` of the screenshots and the application installs), passed to STF as `STORAGE_TOKEN`; it must match the one of the STF server. A `STORAGE_TOKEN` set directly is kept when `STF_STORAGE_TOKEN` is empty. |
| `STF_SERVICES_WAIT_TIMEOUT` | `300` | How long in seconds the entrypoint waits for the STF services above (TCP connections) before it asks for a restart. |
| `STF_SERVICES_WAIT_RETRY` | `30` | The delay in seconds between the checks of the unreachable services. |
| `STF_SERVICES_WAIT_RESTARTS` | `2` | How many restarts in a row the entrypoint asks for (exit `1`) when the services stay unreachable, then it exits with `0` and the restarts stop. The counter is kept in `/tmp/zebrunner/stf-services-restarts` (it survives the restarts of the container) and is reset by reachable services or by the end of the restarts. |

### Public address of STF

| Variable | Default | Description |
| --- | --- | --- |
| `STF_PROVIDER_PUBLIC_IP` | `localhost` | The public host of STF: the storage URL and the screen WebSocket URLs, required. |
| `PUBLIC_IP_PORT` | `80` | The public port of STF. |
| `PUBLIC_IP_PROTOCOL` | `http` | `http` or `https`, case-insensitive; `https` makes the screen WebSocket `wss`. |

### STF provider

The provider of Android reads every `STF_PROVIDER_*` variable as its option (`STF_PROVIDER_MIN_PORT` is `--min-port`), an empty one is removed from its environment, so its default applies. For iOS the entrypoint passes them to `stf ios-device` as options.

| Variable | Default | Description |
| --- | --- | --- |
| `STF_PROVIDER_NAME` | empty | The name of the provider in STF, required for iOS; for Android the hostname of the container by default. |
| `STF_PROVIDER_HOST` | `STF_PROVIDER_PUBLIC_IP` | The host of the provider (the farm host): the `adb connect` URL and the screen WebSocket path. |
| `STF_PROVIDER_DEVICE_NAME` | empty | The name of the device in STF. |
| `STF_PROVIDER_ADB_HOST` | `connector` | Android: the adb server of the connector container. |
| `STF_PROVIDER_ADB_PORT` | `5037` | Android: the port of the adb server. |
| `STF_PROVIDER_MIN_PORT` | `7404` | The first port of the device: the screen WebSocket. |
| `STF_PROVIDER_MAX_PORT` | `7410` | The last port of the device. |
| `STF_PROVIDER_BOOT_COMPLETE_TIMEOUT` | `60000` | How long in milliseconds to wait for the boot of the device. |
| `STF_PROVIDER_CLEANUP` | `false` | Android: reset the device between the uses (uninstall the applications, reset the accounts). |
| `STF_PROVIDER_GROUP_TIMEOUT` | `3600` | The timeout in seconds of the automatic release of an inactive device. |
| `STF_PROVIDER_HEARTBEAT_INTERVAL` | `10000` | The interval in milliseconds of the heartbeat messages. |
| `STF_PROVIDER_LOCK_ROTATION` | `false` | Android: lock the rotation while the device is used. |
| `STF_PROVIDER_MUTE_MASTER` | `never` | Mute the master volume: `always`, `inuse` or `never`. |
| `STF_PROVIDER_SCREEN_JPEG_QUALITY` | `30` | The JPEG quality of the screen. |
| `STF_PROVIDER_SCREEN_PING_INTERVAL` | `30000` | The interval in milliseconds of the pings of the screen WebSocket. |
| `STF_PROVIDER_SCREEN_RESET` | `false` | Android: go back to the home screen when the device is released; off not to hide the applications of the automated runs. |
| `STF_PROVIDER_VNC_INITIAL_SIZE` | `600x800` | Android: the initial size of the VNC server. |
| `STF_PROVIDER_VNC_PORT` | `5900` | Android: the port of the VNC server. |
| `BROADCAST_PORT` | `2223` | The TCP port of the screen broadcast (websocat): the screen WebSocket of `STF_PROVIDER_MIN_PORT` for the video recording of the appium container (`BROADCAST_HOST=device`). |
| `ZMQ_TCP_KEEPALIVE` | `1` | The TCP keepalive of ZeroMQ: against the gray screen after 48 hours without a restart ([android-device#70](https://github.com/zebrunner/android-device/issues/70), [openstf/stf#100](https://github.com/openstf/stf/issues/100)). |
| `ZMQ_TCP_KEEPALIVE_IDLE` | `600` | The idle time in seconds of the ZeroMQ keepalive. |
| `NODE_TLS_REJECT_UNAUTHORIZED` | `0` | `0` accepts a self-signed certificate of the STF storage (the screenshots over https, #56), node warns about it at the start of STF (#203). `1` verifies the certificates and removes the warning: with a self-signed certificate mount its CA into the container and point `NODE_EXTRA_CA_CERTS` at it. |

### iOS

| Variable | Default | Description |
| --- | --- | --- |
| `WDA_HOST` | `connector` | The host of WebDriverAgent, the connector container or the host of a wireless device. |
| `WDA_PORT` | `8100` | The port of WebDriverAgent. |
| `MJPEG_PORT` | `8101` | The MJPEG port of WebDriverAgent: the screen of `stf ios-device` (its `--connect-port`). |
| `WDA_WAIT_TIMEOUT` | `30` | How long in seconds the entrypoint waits for `http://${WDA_HOST}:${WDA_PORT}/status`. |
| `USBMUXD_SOCKET_ADDRESS` | `connector:2222` | usbmuxd of the connector container, `<host>:<port>`, required unless `WIRELESS=true`. go-ios reads it itself, the entrypoint also forwards `/var/run/usbmuxd` to it for the tools that don't. |
| `USBMUXD_SOCKET_TIMEOUT` | `60` | How long in seconds the entrypoint waits for usbmuxd. |
| `USBMUXD_SOCKET_PERIOD` | `5` | The delay in seconds between the checks of usbmuxd. |

### Logs and debug

| Variable | Default | Description |
| --- | --- | --- |
| `LOGGER_LEVEL` | `INFO` | The minimum level of the entrypoint logs: `DEBUG`, `INFO`, `WARN` or `ERROR`. |
| `DEBUG` | `false` | `true` keeps the container alive for `DEBUG_TIMEOUT` seconds after the entrypoint exits. |
| `DEBUG_TIMEOUT` | `3600` | The pause of the debug mode in seconds. |
| `VERBOSE` | `false` | `true` traces the commands of the entrypoint (`set -x`). |

## Startup

1. The configuration is validated (see [Configuration](#configuration)).
2. The STF services are awaited: push, sub, RethinkDB and for iOS the dealers. Every unreachable one is checked again every `STF_SERVICES_WAIT_RETRY` seconds, up to `STF_SERVICES_WAIT_TIMEOUT` seconds.
3. iOS: `/var/run/usbmuxd` is forwarded to `USBMUXD_SOCKET_ADDRESS` (socat, skipped with `WIRELESS=true`), then WebDriverAgent is awaited.
4. The screen WebSocket is broadcast to `BROADCAST_PORT`; websocat is started again a second after it exits.
5. STF starts: `stf provider` for Android, `stf ios-device` for iOS. The entrypoint passes `SIGTERM` of `docker stop` to STF, so it stops gracefully, and exits with the exit code of STF. For iOS the status of WebDriverAgent is logged after STF (#184).

The image runs as `stf`, the user of the base image: the forwarded usbmuxd socket is `/tmp/usbmuxd/usbmuxd`, `/var/run/usbmuxd` is a symlink to it.

## Limitations

- The main repository [zebrunner/stf](https://github.com/zebrunner/stf) is being reworked (`sync/upstream-master`): a new base image may change the options of `stf provider` and `stf ios-device`. Dependabot does not update the base image; after a manual update `make docker` starts both commands with the options of the entrypoint and fails on an unknown option.
- `STF_PROVIDER_CONNECT_PUSH`, `STF_PROVIDER_CONNECT_SUB` and the dealers are single endpoints.

## Exit codes and health

- `0`: a problem a restart does not fix: an invalid configuration (every invalid variable is logged), or STF services unreachable after `STF_SERVICES_WAIT_RESTARTS` restarts in a row. Also `0` when STF stops gracefully (e.g. `docker stop`).
- `1`: a restart may fix it: unreachable STF services (up to `STF_SERVICES_WAIT_RESTARTS` times in a row), usbmuxd or WebDriverAgent of an iOS device not available.
- Otherwise the exit code of STF.
- The healthcheck of the image is the STF process (`pgrep -f "stf (provider|ios-device)"`), mcloud-agent shows the health state of the container.
- Set `DEBUG=true` to keep the container alive for `DEBUG_TIMEOUT` seconds after the entrypoint exits, and `LOGGER_LEVEL=DEBUG` or `VERBOSE=true` for more output.

## Development

`make help` lists the targets, `make check` runs all of them as CI does (every step runs, the failed ones fail the target):

| Target | What it checks |
| --- | --- |
| `make lint` | `tests/lint.sh`: yamllint, actionlint, hadolint, pymarkdown, `bash -n`, ShellCheck and shfmt (style of `.editorconfig`), every env var of the `Dockerfile` documented in this README, the versions of the `Dockerfile` in [Image contents](#image-contents), the text file checks of CONVENTIONS.md. The tools are installed into `.venv` from `tests/requirements-lint.txt`; hadolint comes from `brew install hadolint` on macOS. |
| `make test` | The static checks of the repository (`tests/repo_test.sh`: the pins and the env vars of the `Dockerfile`, the Dependabot configuration) and the tests of `util/logger.sh`, `util/debug.sh` and `entrypoint.sh` (`tests/entrypoint_test.sh`): configuration validation, the wait for the STF services and its restarts, usbmuxd, WebDriverAgent, the options and the environment of `stf provider` and `stf ios-device`, the exit codes and `SIGTERM`. The tools are stubs (`stf`, `socat`, `curl`, `websocat`, ...), so no docker, no STF and no device are needed, but bash 4+ is (on macOS `brew install bash`) and python3. |
| `make docker` | `tests/image_test.sh`: builds the image (`linux/amd64`, `IMAGE` overrides its tag, `REBUILD=true` rebuilds it), checks its contents, configuration, configuration validation, the restart of unreachable services, and starts STF of Android and iOS against fake STF services, adb, usbmuxd and WebDriverAgent: health, the broadcast port, usbmuxd as a non-root user, a graceful `docker stop`. |

Every test script prints its checks and writes JUnit XML into `JUNIT_DIR` when it is set.

The GitHub Actions workflow `.github/workflows/ci.yml` runs the same `lint`, `test` and `docker` jobs on pushes and pull requests to `develop`, `main` and `master`.

Dependabot (`.github/dependabot.yml`) opens weekly pull requests for the GitHub Actions. The base image, go-ios and websocat are updated by hand: the version, the digest or the SHA-256 in the `Dockerfile` and the [Image contents](#image-contents).

The conventions of the style, the formatting and the tooling of this repository are in [CONVENTIONS.md](CONVENTIONS.md), the same in all the MCloud repositories.

## Support

Feel free to support the development with a [**donation**](https://www.paypal.com/donate/?hosted_button_id=MNHYYCYHAKUVA) for the next improvements.

<p align="center">
  <a href="https://zebrunner.com/"><img alt="Zebrunner" src="https://github.com/zebrunner/zebrunner/raw/master/docs/img/zebrunner_intro.png"></a>
</p>

- [Zebrunner PRO](https://zebrunner.com)
- [Zebrunner CE](https://zebrunner.github.io/community-edition)
- [Zebrunner Reporting](https://zebrunner.com/documentation)
- [Carina Guide](http://zebrunner.github.io/carina)
- [Demo Project](https://github.com/zebrunner/carina-demo)
- [Telegram Channel](https://t.me/zebrunner)

## License

[Apache License 2.0](LICENSE)
