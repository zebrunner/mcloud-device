#!/bin/bash


# wait until device is connected and authorized
unauthorized=0
available=0

#TODO: for unauthorized device wait 60 sec and exit
while [[ "$unauthorized" -eq 0 && "$available" -eq 0 ]]
do
    sleep 3
    unauthorized=`adb devices | grep -c unauthorized`
    echo "unauthorized: $unauthorized"
    available=`adb devices | grep -c -w device`
    echo "available: $available"
done

info=""
while [[ "$info" == "" ]]
do
    info=`adb shell dumpsys display | grep -A 20 DisplayDeviceInfo`
    echo "info: ${info}"
    sleep 3
done

export WEBSOCKIFY_CMD="/opt/websockify/run ${MAX_PORT} :5900"
export SOCKET_PROTOCOL=ws
export WEB_PROTOCOL=http

if [ -f /opt/nginx/ssl/ssl.crt ] && [ /opt/nginx/ssl/ssl.key ]; then
    export WEBSOCKIFY_CMD="/opt/websockify/run ${MAX_PORT} :5900 --ssl-only --cert /opt/nginx/ssl/ssl.crt --key /opt/nginx/ssl/ssl.key"
    export SOCKET_PROTOCOL=wss
    export WEB_PROTOCOL=https
fi

#execute to print info in stdout
. /opt/configgen.sh
# generate json file
/opt/configgen.sh > /opt/nodeconfig.json

APPIUM_HOME=/opt/mcloud/appium/node_modules/appium

# uninstall appium specific
echo "uninstalling io.appium.* apps..."
adb uninstall io.appium.uiautomator2.server.test
adb uninstall io.appium.uiautomator2.server
adb uninstall io.appium.settings
adb uninstall io.appium.unlock
echo "io.appium.* apps uninstalled."

# Note: STF_PROVIDER_... is not a good choice for env variable as STF tries to resolve and provide ... as cmd argument to its service!
if [ -z "${STF_HOST_PROVIDER}" ]; then
      #STF_HOST_PROVIDER is empty
      STF_HOST_PROVIDER=${STF_PUBLIC_HOST}
fi

if [ ! -f /usr/bin/java ]; then
  ln -s /usr/lib/jvm/java-8-openjdk-amd64/bin/java /usr/bin/java
fi

${WEBSOCKIFY_CMD} &

which node

npm link --force node@10
sleep 3
node --version
node ${APPIUM_HOME} -p ${PORT} --log-timestamp --session-override --udid ${DEVICEUDID} ${APPIUM_RELAXED_SECURITY} \
           --nodeconfig /opt/nodeconfig.json --automation-name ${AUTOMATION_NAME} --log-level ${APPIUM_LOG_LEVEL} & >&1 & 2>&1

sleep 5

npm link --force node@8
sleep 3
node --version
stf provider --name "${DEVICEUDID}" --device-name "${DEVICENAME}" --min-port=${MIN_PORT} --max-port=${MAX_PORT} \
        --connect-sub tcp://${STF_PRIVATE_HOST}:${STF_TCP_SUB_PORT} --connect-push tcp://${STF_PRIVATE_HOST}:${STF_TCP_PUB_PORT} \
        --group-timeout 3600 --public-ip ${STF_PUBLIC_HOST} --storage-url ${WEB_PROTOCOL}://${STF_PUBLIC_HOST}/ --screen-jpeg-quality 40 --screen-reset false \
	--appium-host ${STF_PRIVATE_HOST} --appium-port ${PORT} \
        --heartbeat-interval 10000 --vnc-initial-size 600x800 --vnc-port 5900 --no-cleanup --screen-ws-url-pattern "${SOCKET_PROTOCOL}://${STF_PUBLIC_HOST}/d/${STF_HOST_PROVIDER}/<%= serial %>/<%= publicPort %>/" & >&1 & 2>&1

echo y > $HOME/.healthy
# healthcheck script could remove this file in case of the failure
while [[ -f $HOME/.healthy ]]
do
  sleep 5
done

echo returing non zero exit code...
exit 1
