#
# Shared functions and variables for EJBCA
#

# Setup shared variables
export PATH=$PATH:/opt/ejbca/bin
export EJBCA_HOME="/opt/ejbca"
export EJBCA_DATADIR="/var/lib/ejbca"
export EJBCA_INITDIR="${EJBCA_HOME}/.init"
export EJBCA_DATA_INITDIR="${EJBCA_DATADIR}/.init"
export EJBCA_VAULTDIR="${EJBCA_DATADIR}/.vault"
export EJBCA_LOG="/var/log/ejbca.log"

#
# ejbca_init()
#   Initializes and deploys EJBCA if it has not been set up already
#
ejbca_init() {
  # Already initialized
  if [ -f "${EJBCA_INITDIR}/ready" ]; then
    return 0
  fi
  echo "Initializing EJBCA server..."

  # Create required data folders
  for d in wildfly/keystore p12 conf/logdevices conf/plugins; do
    if [ ! -d "${EJBCA_DATADIR}/$d" ]; then
      mkdir -p "${EJBCA_DATADIR}/$d"
    fi
  done

  # Copy distribution files (if necessary)
  for f in database.properties ejbca.properties; do
    if [ ! -f "${EJBCA_DATADIR}/conf/$f" ]; then
      cp "/opt/ejbca/conf.dist/$f" "${EJBCA_DATADIR}/conf/"
    fi
  done

  # Update folder permissions
  chown -hR wildfly:wildfly "${EJBCA_DATADIR}"
  chmod 750 "${EJBCA_DATADIR}/conf" "${EJBCA_DATADIR}/p12" "${EJBCA_DATADIR}/wildfly/keystore"

  # Create init dirs
  if [ ! -d "${EJBCA_INITDIR}" ]; then
    mkdir -p "${EJBCA_INITDIR}"
  fi
  chown -hR root:root "${EJBCA_INITDIR}"
  if [ ! -d "${EJBCA_DATA_INITDIR}" ]; then
    mkdir -p "${EJBCA_DATA_INITDIR}"
  fi
  chown -hR root:root "${EJBCA_DATA_INITDIR}"

  # Create vault dir
  if [ ! -d "${EJBCA_VAULTDIR}" ]; then
    mkdir -p "${EJBCA_VAULTDIR}"
  fi
  chown -hR root:root "${EJBCA_VAULTDIR}"
  chmod 750 "${EJBCA_VAULTDIR}"

  # Deploy EJBCA
  ejbca_pre_deploy
  ejbca_deploy
  ejbca_post_deploy

  # Complete
  echo "  --> EJBCA server initialized. Check the '${EJBCA_LOG}' file for details."
  touch "${EJBCA_INITDIR}/ready"
  return 0
}

#
# ejbca_create_ca()
#   Performs creation of the root certificate authority
#
ejbca_create_ca() {
  # Already initialized
  if [ -f "${EJBCA_DATA_INITDIR}/ca" ]; then
    return 0
  fi
  echo "  Creating certificate authority..."

  # Read properties to set up the CA
  ca_properties_file="${EJBCA_VAULTDIR}/ca.properties"
  if [ ! -f "${ca_properties_file}" ]; then
    echo 'ca.name="Root Certificate Authority"' >"${ca_properties_file}"
    echo 'ca.dn="CN=Root Certificate Authority"' >>"${ca_properties_file}"
    echo 'ca.keytype=RSA' >>"${ca_properties_file}"
    echo 'ca.keyspec=2048' >>"${ca_properties_file}"
    echo 'ca.signaturealgorithm=SHA256WithRSA' >>"${ca_properties_file}"
    echo 'ca.validity=7300' >>"${ca_properties_file}"
    echo 'ca.policy=null' >>"${ca_properties_file}"
    echo "ca.tokenpassword=\"$(openssl rand 16 -base64)\"" >>"${ca_properties_file}"
  fi
  java_properties_file="${EJBCA_VAULTDIR}/java.properties"
  if [ ! -f "${java_properties_file}" ]; then
    echo "java.trustpassword=\"$(openssl rand 16 -base64)\"" >"${java_properties_file}"
  fi
  superadmin_properties_file="${EJBCA_VAULTDIR}/superadmin.properties"
  if [ ! -f "${superadmin_properties_file}" ]; then
    echo 'superadmin.cn=admin' >"${superadmin_properties_file}"
    echo 'superadmin.dn="CN=admin"' >>"${superadmin_properties_file}"
    echo "superadmin.password=\"$(openssl rand 16 -base64)\"" >>"${superadmin_properties_file}"
    echo 'superadmin.batch=true' >>"${superadmin_properties_file}"
  fi
  httpsserver_properties_file="${EJBCA_VAULTDIR}/httpsserver.properties"
  if [ ! -f "${httpsserver_properties_file}" ]; then
    echo 'httpsserver.hostname=ejbca' >"${httpsserver_properties_file}"
    echo 'httpsserver.dn="CN=ejbca"' >>"${httpsserver_properties_file}"
    echo "httpsserver.password=\"$(openssl rand 16 -base64)\"" >>"${httpsserver_properties_file}"
  fi
  smtpserver_properties_file="${EJBCA_VAULTDIR}/smtpserver.properties"
  if [ ! -f "${smtpserver_properties_file}" ]; then
    echo 'smtpserver.enabled=false' >"${smtpserver_properties_file}"
    echo 'smtpserver.port=25' >>"${smtpserver_properties_file}"
    echo 'smtpserver.host=localhost' >>"${smtpserver_properties_file}"
    echo 'smtpserver.from=ejbca-noreply@localhost' >>"${smtpserver_properties_file}"
    echo 'smtpserver.user=' >>"${smtpserver_properties_file}"
    echo 'smtpserver.password=' >>"${smtpserver_properties_file}"
    echo 'smtpserver.use_tls=false' >>"${smtpserver_properties_file}"
  fi

  # Run the script to create the CA
  script=$(mktemp)
  chmod a+rx "${script}"
  echo '#!/bin/bash' >"${script}"
  flags=""
  for f in $(find "${EJBCA_VAULTDIR}" -type f -name \*.properties); do
    flags="${flags} $(cat "$f" | awk 'NF {print "-D" $0}')"
  done
  echo -n "ant runinstall " >>"${script}"
  echo $flags >>"${script}"
  su-exec wildfly "${script}" >>"${EJBCA_LOG}" 2>&1
  rm -f "${script}"

  # Deploy the keystore to Wildfly
  echo "  Deploying keystore..."
  su-exec wildfly ant deploy-keystore >>"${EJBCA_LOG}" 2>&1
  echo "    --> Keystore deployed to Wildfly."
  
  # Complete
  echo "    --> Certificate Authority has been configured."
  touch "${EJBCA_DATA_INITDIR}/ca"
  return 0
}

#
# ejbca_deploy()
#   Perform required EJBCA deployment steps
#
ejbca_deploy() {
  # Already initialized
  if [ -f "${EJBCA_INITDIR}/deploy" ]; then
    return 0
  fi

  # Create log file
  touch "${EJBCA_LOG}"
  chown wildfly:wildfly "${EJBCA_LOG}"

  # Deploy EJBCA
  echo "  Deploying EJBCA to Wildfly..."
  pushd "${EJBCA_HOME}" >/dev/null 2>&1
  su-exec wildfly ant deployear >"${EJBCA_LOG}" 2>&1
  sleep 3
  wildfly_wait 60 "deployment-info --name=ejbca.ear" "true    OK"
  echo "    --> EJBCA deployment complete."

  # Create the CA
  ejbca_create_ca

  # Complete
  touch "${EJBCA_INITDIR}/deploy"
  popd >/dev/null 2>&1
  return 0
}

#
# ejbca_get_prop(type, property)
#   Returns the value of the EJBCA 'property' from the 'type'.properties file and stores the value in a variable
#   called 'type'_'property'
#
ejbca_get_prop() {
  type=$1
  property=$2
  value=""

  if [ -f "${EJBCA_VAULTDIR}/${type}.properties" ]; then
    value="$(grep "${type}.${property}" "${EJBCA_VAULTDIR}/${type}.properties" | awk -F"=" '{print $2}')"
  fi
  eval "${type}_${property}=${value}"
  return 0
}

#
# ejbca_post_deploy()
#   Perform required EJBCA post-deployment steps
#
ejbca_post_deploy() {
  # Get properties
  ejbca_get_prop httpsserver password
  ejbca_get_prop httpsserver hostname
  ejbca_get_prop java trustpassword
  ejbca_get_prop smtpserver enabled
  ejbca_get_prop smtpserver port
  ejbca_get_prop smtpserver host
  ejbca_get_prop smtpserver from
  ejbca_get_prop smtpserver user
  ejbca_get_prop smtpserver password
  ejbca_get_prop smtpserver use_tls

  # Configure SMTP credentials
  smtpserver_credentials=""
  if [ "${smtpserver_user}" != "" ]; then
    smtpserver_credentials+=", username=\"${smtpserver.user}\""
  fi
  if [ "${smtpserver_password}" != "" ]; then
    smtpserver_credentials+=", password=\"${smtpserver.password}\""
  fi

  # Run the scripts
  for cli_file in $(find /usr/local/lib/ejbca/postdeploy -type f -name \*.cli | sort); do
    i=$(basename "${cli_file}" .cli)
    init_file="${EJBCA_INITDIR}/postdeploy_$i"
    if [ ! -f "${init_file}" ]; then
      echo "  Running EJBCA post-deployment script #$i..."

      # Replace variables in the script
      script=$(mktemp)
      sed -e "s|%httpsserver.password%|${httpsserver_password}|g" "${cli_file}" > "${script}"
      sed -i -e "s|%httpsserver.hostname%|${httpsserver_hostname}|g" "${script}"
      sed -i -e "s|%java.trustpassword%|${java_trustpassword}|g" "${script}"
      sed -i -e "s|%smtpserver.enabled%|${smtpserver_enabled}|g" "${script}"
      sed -i -e "s|%smtpserver.port%|${smtpserver_port}|g" "${script}"
      sed -i -e "s|%smtpserver.host%|${smtpserver_host}|g" "${script}"
      sed -i -e "s|%smtpserver.from%|${smtpserver_from}|g" "${script}"
      sed -i -e "s|%smtpserver.credentials%|${smtpserver_credentials}|g" "${script}"
      sed -i -e "s|%smtpserver.use_tls%|${smtpserver_use_tls}|g" "${script}"

      # Run the script and wait for Wildfly to be ready again
      "${APPSRV_HOME}/bin/jboss-cli.sh" -c --file="${script}" >>"${WILDFLY_LOG}" 2>&1 && \
      touch "${init_file}"
      rm -f "${script}"
      wildfly_wait 60 ":read-attribute(name=server-state)" "running"
    fi
  done
  return 0
}

#
# ejbca_pre_deploy()
#   Perform required EJBCA pre-deployment steps
#
ejbca_pre_deploy() {
  # Run the scripts
  for cli_file in $(find /usr/local/lib/ejbca/predeploy -type f -name \*.cli | sort); do
    i=$(basename "${cli_file}" .cli)
    init_file="${EJBCA_INITDIR}/predeploy_$i"
    if [ ! -f "${init_file}" ]; then
      echo "  Running EJBCA pre-deployment script #$i..."

      # Replace variables in the script
      script=$(mktemp)
      sed -e "s|%mysql.ejbca_password%|$(cat "${MYSQL_VAULTDIR}/ejbca")|g" "${cli_file}" > "${script}"

      # Run the script and wait for Wildfly to be ready again
      "${APPSRV_HOME}/bin/jboss-cli.sh" -c --file="${script}" >>"${WILDFLY_LOG}" 2>&1 && \
      touch "${init_file}"
      rm -f "${script}"
      wildfly_wait 60 ":read-attribute(name=server-state)" "running"
    fi
  done
  return 0
}
