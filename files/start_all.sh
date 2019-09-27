#!/bin/bash

#execute to print info in stdout
. /opt/configgen.sh
# generate json file
/opt/configgen.sh > /opt/nodeconfig.json

WEBSOCKIFY_CMD="/opt/websockify/run ${MAX_PORT} :5900"
SOCKET_PROTOCOL=ws
WEB_PROTOCOL=http

# uninstall appium specific
adb uninstall io.appium.uiautomator2.server.test
adb uninstall io.appium.uiautomator2.server
adb uninstall io.appium.settings
adb uninstall io.appium.unlock

if [ -f /opt/nginx/ssl/ssl.crt ] && [ /opt/nginx/ssl/ssl.key ]; then
    WEBSOCKIFY_CMD="/opt/websockify/run ${MAX_PORT} :5900 --ssl-only --cert /opt/nginx/ssl/ssl.crt --key /opt/nginx/ssl/ssl.key"
    SOCKET_PROTOCOL=wss
    WEB_PROTOCOL=https
fi

ln -s -f /usr/lib/jvm/java-8-openjdk-amd64/bin/java /usr/bin/java \
    & $WEBSOCKIFY_CMD \
    & node /opt/appium/ -p $PORT --log-timestamp --session-override --udid $DEVICEUDID $APPIUM_RELAXED_SECURITY \
           --nodeconfig /opt/nodeconfig.json --automation-name $AUTOMATION_NAME --log-level $APPIUM_LOG_LEVEL \
    & stf provider --name "$DEVICEUDID" --min-port=$MIN_PORT --max-port=$MAX_PORT \
        --connect-sub tcp://$STF_PRIVATE_HOST:$STF_TCP_SUB_PORT --connect-push tcp://$STF_PRIVATE_HOST:$STF_TCP_PUB_PORT \
        --group-timeout 3600 --public-ip $STF_PUBLIC_HOST --storage-url $WEB_PROTOCOL://$STF_PUBLIC_HOST/ --screen-jpeg-quality 40 \
        --heartbeat-interval 10000 --vnc-initial-size 600x800 --vnc-port 5900 --no-cleanup --screen-ws-url-pattern "${SOCKET_PROTOCOL}://${STF_PUBLIC_HOST}/d/${STF_PRIVATE_HOST}/<%= serial %>/<%= publicPort %>/" &

while true
  do
    counter=$HEARTBEAT_INTERVAL
    #make sleep shorter to be able to react onto disconnected device asap
    while ((counter--));
    do
        sleep 1
        #echo "sleep 1; counter: " + $counter
    done

#    sleep $HEARTBEAT_INTERVAL
    ADB_STATUS=$(adb devices | grep -c ${DEVICEUDID})
    if [ ! "$ADB_STATUS" -eq "1" ]; then
        echo adb server is dead. restarting container...
        exit -1
    fi

    STFPROVIDER_STATUS=$(ps -ef | grep -v "grep" | grep -c "stf provider")
    if [ ! "$STFPROVIDER_STATUS" -eq "1" ]; then
      echo "stf provider is dead. reastarting container...
      exit -1
    fi


    APPIUM_STATUS=$(ps -ef | grep -v "grep" | grep -c "appium")
    if [ ! "$APPIUM_STATUS" -eq "1" ]; then
      echo "appium provider is dead. reastarting container...
      exit -1
    fi
  done
