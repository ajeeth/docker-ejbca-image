#
# Shared functions and variables for WildFly server
#

# Setup shared variables
export APPSRV_HOME="/opt/jboss/wildfly"
export WILDFLY_DATADIR="/var/lib/ejbca/wildfly"
export WILDFLY_LOG="/var/log/wildfly.log"
export WILDFLY_LOG_COUNT=10
export PATH=$PATH:${APPSRV_HOME}/bin

#
# wildfly_check_perms()
#   Checks and sets permissions on WildFly folders
#
wildfly_check_perms() {
  chown -hR wildfly:wildfly "${WILDFLY_DATADIR}"
  chmod 0750 "${WILDFLY_DATADIR}"
  return 0
}

#
# wildfly_create_config($is_temp)
#   Creates the standalone.xml file from the standard template
#
wildfly_create_config() {
  is_temp="false"
  if [ "$1" == "true" ]; then
    is_temp="true"
  fi

  # Start from a fresh copy of the template
  echo "Creating WildFly standalone.xml configuration file..."
  cat "${APPSRV_HOME}/standalone/configuration/standalone.xml.tpl" >"${WILDFLY_DATADIR}/standalone.xml"
  config="${WILDFLY_DATADIR}/standalone.xml"

  # Replace MySQL settings
  sed -i -e "s|%mysql.connection_url%|${MYSQL_CONNECTION_URL}|g" "${config}"
  sed -i -e "s|%mysql.username%|${MYSQL_USERNAME}|g" "${config}"
  sed -i -e "s|%mysql.password%|${MYSQL_PASSWORD}|g" "${config}"

  # Replace WildFly server settings
  if [ "${is_temp}" == "true" ]; then
    sed -i -e "s|%wildfly.storepass%|changeit|g" "${config}"
    sed -i -e "s|%wildfly.truststorepass%|changeit|g" "${config}"
  else
    sed -i -e "s|%wildfly.storepass%|${WILDFLY_STOREPASS}|g" "${config}"
    sed -i -e "s|%wildfly.truststorepass%|${WILDFLY_TRUSTSTOREPASS}|g" "${config}"
  fi

  # Replace SMTP server settings
  if [ "${SMTPSERVER_ENABLED}" == "true" ]; then
    sed -i -e 's|<!--%smtpserver.enabled%||g' "${config}"
    sed -i -e 's|%smtpserver.enabled%-->||g' "${config}"
    sed -i -e "s|%smtpserver.from%|${SMTPSERVER_FROM}|g" "${config}"
    sed -i -e "s|%smtpserver.use_tls%|${SMTPSERVER_USE_TLS}|g" "${config}"
    sed -i -e "s|%smtpserver.host%|${SMTPSERVER_HOST}|g" "${config}"
    sed -i -e "s|%smtpserver.port%|${SMTPSERVER_PORT}|g" "${config}"
    if [ "${SMTPSERVER_AUTH_REQUIRED}" == "true" ]; then
      sed -i -e "s|%smtpserver.username%|username=\"${SMTPSERVER_USERNAME}\"|g" "${config}"
      sed -i -e "s|%smtpserver.password%|password=\"${SMTPSERVER_PASSWORD}\"|g" "${config}"
    else
      sed -i -e "s|%smtpserver.username%||g" "${config}"
      sed -i -e "s|%smtpserver.password%||g" "${config}"
    fi
  fi
  return 0
}

#
# wildfly_init()
#   Performs initial setup of WildFly to be used when initializing EJBCA for the first time
#
wildfly_init() {
  # Make sure the keystore folder exists
  mkdir -p "${WILDFLY_DATADIR}/keystore"
  wildfly_check_perms

  # Generate a temporary SSL key pair to start up WildFly
  echo "Creating temporary SSL key pair for WildFly server..."
  keytool -genkey -keyalg RSA -alias wildfly -keystore "${WILDFLY_DATADIR}/keystore/keystore.jks" -storepass changeit \
    -keypass changeit -validity 30 -keysize 2048 -dname "CN=localhost"
  keytool -export -rfc -alias wildfly -file "${WILDFLY_DATADIR}/keystore/ca.crt" \
    -keystore "${WILDFLY_DATADIR}/keystore/keystore.jks" -storepass changeit
  keytool -import -noprompt -trustcacerts -alias ca -file "${WILDFLY_DATADIR}/keystore/ca.crt" \
    -keystore "${WILDFLY_DATADIR}/keystore/truststore.jks" -storepass changeit

  # Generate a temporary WildFly configuration file
  wildfly_create_config "true"
  return 0
}

#
# wildfly_rotate_log()
#   Rotates old log files so the total never exceeds WILDFLY_LOG_COUNT
#
wildfly_rotate_log() {
  rm -f "${WILDFLY_LOG}.${WILDFLY_LOG_COUNT}"
  for ((i=$WILDFLY_LOG_COUNT - 1; i > 0; i--)); do
    if [ -f "${WILDFLY_LOG}.$i" ]; then
      j=$(expr $i=$i+1)
      mv "${WILDFLY_LOG}.$i" "${WILDFLY_LOG}.$j"
    fi
  done
  if [ -f "${WILDFLY_LOG}" ]; then
    mv "${WILDFLY_LOG}" "${WILDFLY_LOG}.1"
  fi
  return 0
}

#
# wildfly_start()
#   Starts the WildFly JBOSS server replacing the current process
#
wildfly_start() {
  echo "Starting WildFly server..."
  wildfly_rotate_log
  exec su-exec wildfly "${APPSRV_HOME}/bin/standalone.sh" -b 0.0.0.0 >"${WILDFLY_LOG}" 2>&1
  return 0
}

#
# wildfly_start_bg()
#   Starts the WildFly JBOSS server in the background and wait for it to be ready
#
wildfly_start_bg() {
  echo "Starting WildFly server in the background..."
  wildfly_rotate_log
  su-exec wildfly "${APPSRV_HOME}/bin/standalone.sh" -b 0.0.0.0 >"${WILDFLY_LOG}" 2>&1 &
  wildfly_wait 60 ":read-attribute(name=server-state)" "running"
  return 0
}

#
# wildfly_startup_check()
#   Ensures folders and files required to start WildFly exist and have the correct permissions
#
wildfly_startup_check() {
  # Make sure the WildFly config files exist
  for file in standalone.xml keystore/keystore.jks keystore/truststore.jks; do
    if [ ! -f "${WILDFLY_DATADIR}/${file}" ]; then
      echo "EJBCA has not been initialized.  Please run the 'ejbca-init' command first."
      exit 1
    fi
  done

  # Make sure permissions are correct
  wildfly_check_perms
  return 0
}

#
# wildfly_stop()
#   Stops the WildFly JBOSS server
#
wildfly_stop() {
  echo "Stopping WildFly server..."
  pid=$(pgrep -f "${APPSRV_HOME}/bin/standalone.sh")
  if [ "${pid}" != "" ]; then
    kill -TERM $pid
    while [[ $(pgrep -f "${APPSRV_HOME}/bin/standalone.sh") ]]; do
      echo "  Waiting 1s for WildFly server to stop"
      sleep 1
    done
  fi
  return 0
}

#
# wildfly_wait(num_sec, command, result)
#   Waits up to 'num_sec' seconds for WildFly 'command' to return a string containing 'result'
#
wildfly_wait() {
  max_wait=$1
  command=$2
  result=$3

  delay=1
  total_wait=0
  until [ $total_wait -gt $max_wait ]; do
    if "${APPSRV_HOME}/bin/jboss-cli.sh" -c --command="${command}" | grep -q "${result}"; then
      break
    fi
    echo "[${total_wait}/${max_wait}s elapsed] Waiting for WildFly server..."
    sleep $delay
    let total_wait=$total_wait+$delay
  done
  if [ $total_wait -gt $max_wait ]; then
    return 1
  else
    return 0
  fi
}
