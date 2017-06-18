#
# Shared functions and variables for EJBCA
#

# Setup shared variables
export EJBCA_HOME="/opt/ejbca"
export EJBCA_DATADIR="/var/lib/ejbca"
export PATH=$PATH:${EJBCA_HOME}/bin

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

  # Configure properties file

    echo 'ca.name="Root Certificate Authority"' >"${ca_properties_file}"
    echo 'ca.dn="CN=Root Certificate Authority"' >>"${ca_properties_file}"
    echo 'ca.keytype=RSA' >>"${ca_properties_file}"
    echo 'ca.keyspec=2048' >>"${ca_properties_file}"
    echo 'ca.signaturealgorithm=SHA256WithRSA' >>"${ca_properties_file}"
    echo 'ca.validity=7300' >>"${ca_properties_file}"
    echo 'ca.policy=null' >>"${ca_properties_file}"
    echo "ca.tokenpassword=\"$(openssl rand 16 -base64)\"" >>"${ca_properties_file}"

    echo "java.trustpassword=\"$(openssl rand 16 -base64)\"" >"${java_properties_file}"

    echo 'superadmin.cn=admin' >"${superadmin_properties_file}"
    echo 'superadmin.dn="CN=admin"' >>"${superadmin_properties_file}"
    echo "superadmin.password=\"$(openssl rand 16 -base64)\"" >>"${superadmin_properties_file}"
    echo 'superadmin.batch=true' >>"${superadmin_properties_file}"

    echo 'httpsserver.hostname=ejbca' >"${httpsserver_properties_file}"
    echo 'httpsserver.dn="CN=ejbca"' >>"${httpsserver_properties_file}"
    echo "httpsserver.password=\"$(openssl rand 16 -base64)\"" >>"${httpsserver_properties_file}"

    echo 'smtpserver.enabled=false' >"${smtpserver_properties_file}"
    echo 'smtpserver.port=25' >>"${smtpserver_properties_file}"
    echo 'smtpserver.host=localhost' >>"${smtpserver_properties_file}"
    echo 'smtpserver.from=ejbca-noreply@localhost' >>"${smtpserver_properties_file}"
    echo 'smtpserver.user=' >>"${smtpserver_properties_file}"
    echo 'smtpserver.password=' >>"${smtpserver_properties_file}"
    echo 'smtpserver.use_tls=false' >>"${smtpserver_properties_file}"




#(cli) ca init &quot;${ca.name}&quot; &quot;${ca.dn}&quot; ${ca.tokentype} ${ca.tokenpassword} ${ca.keyspec} ${ca.keytype} ${ca.validity} ${ca.policy} ${ca.signaturealgorithm} ${install.catoken.command} ${install.certprofile.command} -superadmincn &quot;${superadmin.cn}&quot;"
#(cli) ra addendentity tomcat --password ${httpsserver.password} &quot;${httpsserver.dn}&quot; --altname &quot;${httpsserver.an}&quot; &quot;${ca.name}&quot; 1 JKS --certprofile SERVER
#(cli) ra setclearpwd tomcat ${httpsserver.password}
#(cli) batch tomcat

#(cli) ra addendentity superadmin --password ${superadmin.password} &quot;${superadmin.dn}&quot; &quot;${ca.name}&quot; 1 ${superadmin.keystoretype}"
#(cli) ra setclearpwd superadmin ${superadmin.password}
#(cli) batch superadmin

#(cli) ca getcacert &quot;${ca.name}&quot; ${java.io.tmpdir}/rootca.der -der
#(keytool) -v -alias &quot;${ca.name}&quot; -import -trustcacerts -file '${java.io.tmpdir}/rootca.der' -keystore '${trust.keystore}' -storepass ${trust.password} -noprompt
#rm rootca.der


  # Run the script to create the CA
  script=$(mktemp)
  chmod a+rx "${script}"
  echo '#!/bin/bash' >"${script}"
  flags=""
  for f in $(find "${EJBCA_SECRETDIR}" -type f -name \*.properties); do
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
# ejbca_init()
#   Initializes and deploys EJBCA if it has not been set up already
#
ejbca_init() {
  echo "Initializing EJBCA server..."

  ejbca_startup_check
  ejbca_init_vars
  wildfly_init
  wildfly_start_bg
  #ejbca_create_ca
  wildfly_stop

  echo "EJBCA server initialized."
  return 0
}

#
# ejbca_init_vars()
#   Initializes all EJBCA environment variables
#
ejbca_init_vars() {
  # Set up MySQL variables
  if [[ -z "${MYSQL_CONNECTION_URL}" ]]; then
    export MYSQL_CONNECTION_URL="mysql://mariadb:3306/ejbca"
  fi
  if [[ -z "${MYSQL_USERNAME}" ]]; then
    if [[ -z "${MYSQL_USERNAME_SECRET}" ]]; then
      export MYSQL_USERNAME="ejbca"
    else
      ejbca_read_secret MYSQL_USERNAME_SECRET MYSQL_USERNAME
    fi
  fi
  if [[ -z "${MYSQL_PASSWORD}" ]]; then
    if [[ -z "${MYSQL_PASSWORD_SECRET}" ]]; then
      echo "MYSQL_PASSWORD or MYSQL_PASSWORD_SECRET environment variable must be set."
      exit 1
    else
      ejbca_read_secret MYSQL_PASSWORD_SECRET MYSQL_PASSWORD
    fi
  fi

  # Setup WildFly variables
  if [[ -z "${WILDFLY_SERVER_CN}" ]]; then
    export WILDFLY_SERVER_CN="ejbca"
  fi
  if [[ -z "${WILDFLY_SERVER_ALT_NAMES}" ]]; then
    export WILDFLY_SERVER_ALT_NAMES=""
  fi
  if [[ -z "${WILDFLY_STOREPASS}" ]]; then
    if [[ -z "${WILDFLY_STOREPASS_SECRET}" ]]; then
      export WILDFLY_STOREPASS="changeit"
    else
      ejbca_read_secret WILDFLY_STOREPASS_SECRET WILDFLY_STOREPASS
    fi
  fi
  if [[ -z "${WILDFLY_TRUSTSTOREPASS}" ]]; then
    if [[ -z "${WILDFLY_TRUSTSTOREPASS_SECRET}" ]]; then
      export WILDFLY_TRUSTSTOREPASS="changeit"
    else
      ejbca_read_secret WILDFLY_TRUSTSTOREPASS_SECRET WILDFLY_TRUSTSTOREPASS
    fi
  fi

  # Setup SMTP server variables
  if [[ -z "${SMTPSERVER_ENABLED}" ]]; then
    export SMTPSERVER_ENABLED="false"
  fi
  if [[ "${SMTPSERVER_ENABLED}" == "true" ]]; then
    if [[ -z "${SMTPSERVER_FROM}" ]]; then
      export SMTPSERVER_FROM="ejbca-noreply@ejbca"
    fi
    if [[ -z "${SMTPSERVER_USE_TLS}" ]]; then
      export SMTPSERVER_USE_TLS="false"
    fi
    if [[ -z "${SMTPSERVER_HOST}" ]]; then
      export SMTPSERVER_HOST="smtp"
    fi
    if [[ -z "${SMTPSERVER_PORT}" ]]; then
      export SMTPSERVER_PORT=25
    fi
    if [[ -z "${SMTPSERVER_AUTH_REQUIRED}" ]]; then
      export SMTPSERVER_AUTH_REQUIRED="false"
    fi
    if [[ "${SMTPSERVER_AUTH_REQUIRED}" == "true" ]]; then
      if [[ -z "${SMTPSERVER_USERNAME}" ]]; then
        if [[ -z "${SMTPSERVER_USERNAME_SECRET}" ]]; then
          export SMTPSERVER_USERNAME="ejbca"
        else
          ejbca_read_secret SMTPSERVER_USERNAME_SECRET SMTPSERVER_USERNAME
        fi
      fi
      if [[ -z "${SMTPSERVER_PASSWORD}" ]]; then
        if [[ -z "${SMTPSERVER_PASSWORD_SECRET}" ]]; then
          echo "SMTPSERVER_PASSWORD or SMTPSERVER_PASSWORD_SECRET environment variable must be set."
          exit 1
        else
          ejbca_read_secret SMTPSERVER_PASSWORD_SECRET SMTPSERVER_PASSWORD
        fi
      fi
    fi
  fi

  # Setup CA server variables
  if [[ -z "${CA_NAME}" ]]; then
    export CA_NAME="Root Certificate Authority"
  fi
  if [[ -z "${CA_DN}" ]]; then
    export CA_DN="CN=Root Certificate Authority"
  fi
  if [[ -z "${CA_KEYTYPE}" ]]; then
    export CA_KEYTYPE="RSA"
  fi
  if [[ -z "${CA_KEYSPEC}" ]]; then
    export CA_KEYSPEC=2048
  fi
  if [[ -z "${CA_SIGNATUREALGORITHM}" ]]; then
    export CA_SIGNATUREALGORITHM="SHA256WithRSA"
  fi
  if [[ -z "${CA_VALIDITY}" ]]; then
    export CA_VALIDITY=7300
  fi
  if [[ -z "${CA_POLICY}" ]]; then
    export CA_POLICY="null"
  fi
  if [[ -z "${CA_PASSWORD}" ]]; then
    if [[ -z ${CA_PASSWORD_SECRET} ]]; then
      export CA_PASSWORD="changeit"
    else
      ejbca_read_secret CA_PASSWORD_SECRET CA_PASSWORD
    fi
  fi

  # Setup SuperAdmin user variables
  if [[ -z "${SUPERADMIN_CN}" ]]; then
    if [[ -z ${SUPERADMIN_CN_SECRET} ]]; then
      export SUPERADMIN_CN="admin"
    else
      ejbca_read_secret SUPERADMIN_CN_SECRET SUPERADMIN_CN
    fi
  fi
  if [[ -z "${SUPERADMIN_DN}" ]]; then
    if [[ -z ${SUPERADMIN_DN_SECRET} ]]; then
      export SUPERADMIN_DN="CN=admin"
    else
      ejbca_read_secret SUPERADMIN_DN_SECRET SUPERADMIN_DN
    fi
  fi
  if [[ -z "${SUPERADMIN_PASSWORD}" ]]; then
    if [[ -z ${SUPERADMIN_PASSWORD_SECRET} ]]; then
      export SUPERADMIN_PASSWORD="changeit"
    else
      ejbca_read_secret SUPERADMIN_PASSWORD_SECRET SUPERADMIN_PASSWORD
    fi
  fi
  return 0  
}

#
# ejbca_read_secret($secret, $store_as)
#   Reads the file that the given $secret environment variable points to and return the value as the $store_as variable
#
ejbca_read_secret() {
  secret=$1
  store_as=$2

  # Make sure the file exists
  secret_file=$(eval "echo \$${secret}")
  if [ ! -f "${secret_file}" ]; then
    echo "Cannot find ${secret} file '${secret_file}'."
    exit 1
  fi

  # Store the value
  value=$(cat "${secret_file}")
  eval "${store_as}=\"${value}\""
  return 0
}

#
# ejbca_start()
#   Starts the EJBCA server
#
ejbca_start() {
  wildfly_start
}

#
# ejbca_startup_check()
#   Ensures folders and files required to start EJBCA exist and have the correct permissions
#
ejbca_startup_check() {
  # Make sure folders exist
  if [ ! -d "${EJBCA_DATADIR}/conf" ]; then
    mkdir -p "${EJBCA_DATADIR}/conf"
    find "${EJBCA_HOME}/conf.dist" -name \*.properties | xargs cp -t "${EJBCA_DATADIR}/conf/"
  fi
  for dir in keystore conf/logdevices conf/plugins; do
    if [ ! -d "${EJBCA_DATADIR}/${dir}" ]; then
      mkdir -p "${EJBCA_DATADIR}/${dir}"
    fi
  done

  # Make sure permissions are correct
  chown -hR wildfly:wildfly "${EJBCA_DATADIR}"
  chmod 0750 "${EJBCA_DATADIR}"
  return 0
}

#
# ejbca_update_config()
#   Regenerates the WildFly standalone.xml configuration file based on the current environment variables
#
ejbca_update_config() {
  echo "Regenerating WildFly standalone.xml file..."
  ejbca_startup_check
  wildfly_startup_check
  ejbca_init_vars
  wildfly_create_config
  echo "A new standalone.xml file has been generated."
  return 0
}
