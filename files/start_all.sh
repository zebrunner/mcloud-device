#!/bin/bash

# Note: STF_PROVIDER_... is not a good choice for env variable as STF tries to resolve and provide ... as cmd argument to its service!
if [ -z "${STF_PROVIDER_HOST}" ]; then
      # when STF_PROVIDER_HOST is empty
      STF_PROVIDER_HOST=${STF_PROVIDER_PUBLIC_IP}
fi

SOCKET_PROTOCOL=ws
if [ "${PUBLIC_IP_PROTOCOL}" = "http" ]; then
      SOCKET_PROTOCOL=wss
fi


#TODO: split startup command onto the android/ios versions
# stf provider for Android
stf provider --allow-remote \
        --connect-url-pattern "${STF_PROVIDER_HOST}:<%= publicPort %>" \
        --storage-url ${PUBLIC_IP_PROTOCOL}://${STF_PROVIDER_PUBLIC_IP}:${PUBLIC_IP_PORT}/ \
	--screen-ws-url-pattern "${SOCKET_PROTOCOL}://${STF_PROVIDER_PUBLIC_IP}/d/${STF_PROVIDER_HOST}/<%= serial %>/<%= publicPort %>/" &

echo "---------------------------------------------------------"
echo "processes RIGHT AFTER START:"
ps -ef
echo "---------------------------------------------------------"

# wait until backgroud processes exists for websockify (python) and node (stf)
node_pids=`pidof node`
#python_pids=`pidof python`
#wait -n $python_pids $node_pids
wait -n $node_pids


echo "Exit status: $?"
echo "---------------------------------------------------------"
echo "processes BEFORE EXIT:"
ps -ef
echo "---------------------------------------------------------"
