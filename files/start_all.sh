#!/bin/bash

export WEBSOCKIFY_CMD="/opt/websockify/run ${STF_PROVIDER_MAX_PORT} :5900"
export SOCKET_PROTOCOL=ws
export WEB_PROTOCOL=http

if [ -f /opt/nginx/ssl/ssl.crt ] && [ /opt/nginx/ssl/ssl.key ]; then
    export WEBSOCKIFY_CMD="/opt/websockify/run ${STF_PROVIDER_MAX_PORT} :5900 --ssl-only --cert /opt/nginx/ssl/ssl.crt --key /opt/nginx/ssl/ssl.key"
    export SOCKET_PROTOCOL=wss
    export WEB_PROTOCOL=https
fi

# Note: STF_PROVIDER_... is not a good choice for env variable as STF tries to resolve and provide ... as cmd argument to its service!
if [ -z "${STF_PROVIDER_HOST}" ]; then
      #STF_PROVIDER_HOST is empty
      STF_PROVIDER_HOST=${STF_PROVIDER_PUBLIC_IP}
fi

if [ ! -f /usr/bin/java ]; then
  ln -s /usr/lib/jvm/java-8-openjdk-amd64/bin/java /usr/bin/java
fi

${WEBSOCKIFY_CMD} &

stf provider --allow-remote \
        --connect-url-pattern "${STF_PROVIDER_HOST}:<%= publicPort %>" \
        --storage-url ${WEB_PROTOCOL}://${STF_PROVIDER_PUBLIC_IP}/ \
	--screen-ws-url-pattern "${SOCKET_PROTOCOL}://${STF_PROVIDER_PUBLIC_IP}/d/${STF_PROVIDER_HOST}/<%= serial %>/<%= publicPort %>/" &

echo "---------------------------------------------------------"
echo "processes RIGHT AFTER START:"
ps -ef
echo "---------------------------------------------------------"

# wait until backgroud processes exists for websockify (python) and node (stf)
node_pids=`pidof node`
python_pids=`pidof python`

wait -n $python_pids $node_pids


echo "Exit status: $?"
echo "---------------------------------------------------------"
echo "processes BEFORE EXIT:"
ps -ef
echo "---------------------------------------------------------"
