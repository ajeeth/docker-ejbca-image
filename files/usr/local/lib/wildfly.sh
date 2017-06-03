#
# Shared functions and variables for Wildfly server
#

# Setup shared variables
export PATH=$PATH:/opt/wildfly/bin
export APPSRV_HOME="/opt/wildfly"
export WILDFLY_LOG="/var/log/wildfly.log"

#
# wildfly_start()
#   Starts the Wildfly JBOSS server
#
wildfly_start() {
  # Start the server
  echo "Starting Wildfly server..."
  su-exec wildfly "${APPSRV_HOME}/bin/standalone.sh" --debug -b 0.0.0.0 >"${WILDFLY_LOG}" 2>&1 &
  wildfly_wait 60 ":read-attribute(name=server-state)" "running"
  echo "  --> Wildfly server started. Check the '${WILDFLY_LOG}' file for details."

  # Make sure EJBCA is initialized and deployed
  ejbca_init

  # Wait for processes to exit
  wait
  return 0
}

#
# wildfly_wait(num_sec, command, result)
#   Waits up to 'num_sec' seconds for Wildfly 'command' to return a string containing 'result'
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
    echo "[${total_wait}/${max_wait}s elapsed] Waiting for Wildfly server..."
    sleep $delay
    let total_wait=$total_wait+$delay
  done
  if [ $total_wait -gt $max_wait ]; then
    return 1
  else
    return 0
  fi
}
