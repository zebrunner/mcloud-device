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

export WEBSOCKIFY_CMD="/opt/websockify/run ${STF_PROVIDER_MAX_PORT} :5900"
export SOCKET_PROTOCOL=ws
export WEB_PROTOCOL=http

if [ -f /opt/nginx/ssl/ssl.crt ] && [ /opt/nginx/ssl/ssl.key ]; then
    export WEBSOCKIFY_CMD="/opt/websockify/run ${STF_PROVIDER_MAX_PORT} :5900 --ssl-only --cert /opt/nginx/ssl/ssl.crt --key /opt/nginx/ssl/ssl.key"
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
adb uninstall io.appium.uiautomator2.server.test > /dev/null 2>&1
adb uninstall io.appium.uiautomator2.server > /dev/null 2>&1
adb uninstall io.appium.settings > /dev/null 2>&1
adb uninstall io.appium.unlock > /dev/null 2>&1
echo "io.appium.* apps uninstalled."

# Note: STF_PROVIDER_... is not a good choice for env variable as STF tries to resolve and provide ... as cmd argument to its service!
if [ -z "${STF_HOST_PROVIDER}" ]; then
      #STF_HOST_PROVIDER is empty
      STF_HOST_PROVIDER=${STF_PROVIDER_PUBLIC_IP}
fi

if [ ! -f /usr/bin/java ]; then
  ln -s /usr/lib/jvm/java-8-openjdk-amd64/bin/java /usr/bin/java
fi

${WEBSOCKIFY_CMD} &

which node

npm link --force node@10
sleep 3
node --version
node ${APPIUM_HOME} -p ${STF_PROVIDER_APPIUM_PORT} --log-timestamp --session-override --udid ${DEVICE_UDID} ${APPIUM_RELAXED_SECURITY} \
           --nodeconfig /opt/nodeconfig.json --automation-name ${AUTOMATION_NAME} --log-level ${APPIUM_LOG_LEVEL} &

sleep 5

npm link --force node@8
sleep 3
node --version

stf provider --name "${DEVICE_UDID}" \
        --connect-url-pattern "${STF_HOST_PROVIDER}:<%= publicPort %>" \
        --storage-url ${WEB_PROTOCOL}://${STF_PROVIDER_PUBLIC_IP}/ \
	--screen-ws-url-pattern "${SOCKET_PROTOCOL}://${STF_PROVIDER_PUBLIC_IP}/d/${STF_HOST_PROVIDER}/<%= serial %>/<%= publicPort %>/" &

echo "---------------------------------------------------------"
#show existing processes
ps -ef
echo "---------------------------------------------------------"

# wait until backgroud processes exists for adb, websockify (python) and node (appium, stf)
node_pids=`pidof node`
python_pids=`pidof python`
adb_pids=`pidof adb`

echo wait -n $node_pids $python_pids $adb_pids
wait -n $node_pids $python_pids $adb_pids


echo "Exit status: $?"
echo "---------------------------------------------------------"
ps -ef
echo "---------------------------------------------------------"

