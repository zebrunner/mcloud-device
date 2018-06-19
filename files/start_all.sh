#!/bin/bash

. /opt/configgen.sh

ln -s /usr/lib/jvm/java-8-openjdk-amd64/bin/java /usr/bin/java \
    & /opt/configgen.sh > /opt/nodeconfig.json \
    & node /opt/appium/ -p $PORT --log-timestamp --session-override --udid $DEVICEUDID \
           --nodeconfig /opt/nodeconfig.json --automation-name $AUTOMATION_NAME \
    & /opt/websockify/run ${MAX_PORT} :5900 \
    & stf provider --name "$DEVICEUDID" --min-port=$MIN_PORT --max-port=$MAX_PORT \
        --connect-sub tcp://$STF_PRIVATE_HOST:$STF_TCP_SUB_PORT --connect-push tcp://$STF_PRIVATE_HOST:$STF_TCP_PUB_PORT \
        --group-timeout 3600 --public-ip $STF_PUBLIC_HOST --storage-url https://$STF_PUBLIC_HOST/ \
	      --heartbeat-interval 10000 --vnc-initial-size 600x800 --vnc-port 5900 --no-cleanup --screen-ws-url-pattern "wss://${STF_PUBLIC_HOST}/d/${STF_PRIVATE_HOST}/<%= serial %>/<%= publicPort %>/" &

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
    else
        echo adb service is alive.
    fi

    STFPROVIDER_STATUS=$(ps -ef | grep -v "grep" | grep -c "stf provider")
    if [ ! "$STFPROVIDER_STATUS" -eq "1" ]; then
      echo "stf provider is dead. reastarting container...
      exit -1
    else
      echo stf provider is alive.
    fi


    APPIUM_STATUS=$(ps -ef | grep -v "grep" | grep -c "appium")
    if [ ! "$APPIUM_STATUS" -eq "1" ]; then
      echo "appium provider is dead. reastarting container...
      exit -1
    else
      echo appium is alive.
    fi
  done
