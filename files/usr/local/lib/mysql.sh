#
# Shared functions and variables for MySQL server
#

# Setup shared variables
export MYSQL_DATADIR="/var/lib/mysql"
export MYSQL_INITDIR="${MYSQL_DATADIR}/.init"
export MYSQL_VAULTDIR="${MYSQL_DATADIR}/.vault"
export MYSQL_LOG="/var/log/mysqld_safe.log"
export MYSQL_INIT_LOG="/var/log/init_mysql_server.log"

#
# mysql_init()
#   Initializes MySQL database if it has not been set up already
#
mysql_init() {
  # Already initialized
  if [ -f "${MYSQL_INITDIR}/ready" ]; then
    return 0
  fi
  echo "Initializing MySQL server..."

  # Update folder permissions
  if [ ! -d "/run/mysqld" ]; then
    mkdir -p /run/mysqld 
    chown mysql:mysql /run/mysqld
  fi
  chown -hR mysql:mysql "${MYSQL_DATADIR}"

  # Create init dir
  if [ ! -d "${MYSQL_INITDIR}" ]; then
    mkdir -p "${MYSQL_INITDIR}"
  fi
  chown -hR root:root "${MYSQL_INITDIR}"

  # Create vault dir
  if [ ! -d "${MYSQL_VAULTDIR}" ]; then
    mkdir -p "${MYSQL_VAULTDIR}"
  fi
  chown -hR root:root "${MYSQL_VAULTDIR}"
  chmod 750 "${MYSQL_VAULTDIR}"

  # Set user passwords
  for user in root ejbca; do
    if [ ! -f "${MYSQL_VAULTDIR}/${user}" ]; then
      echo $(openssl rand 18 -base64) > "${MYSQL_VAULTDIR}/${user}"
    fi
    chown 0:0 "${MYSQL_VAULTDIR}/${user}"
    chmod 600 "${MYSQL_VAULTDIR}/${user}"
  done

  # Create temp startup script
  script=$(mktemp)
  cat << EOF > "${script}"
DROP DATABASE test;

USE mysql;
DELETE FROM user WHERE user != 'root' OR host != 'localhost';
UPDATE user SET password=PASSWORD("$(cat "${MYSQL_VAULTDIR}/root")") WHERE user = 'root' AND host = 'localhost'; 

CREATE DATABASE IF NOT EXISTS ejbca CHARACTER SET utf8 COLLATE utf8_general_ci;
# We cannot do a GRANT in a bootstrap, so this gets executed when starting the server
# GRANT ALL PRIVILEGES ON ejbca.* TO 'ejbca'@'localhost' IDENTIFIED BY "${MYSQL_EJBCA_PASSWORD}";
FLUSH PRIVILEGES;
EOF

  # Initialize the server
  /usr/bin/mysql_install_db --user=mysql > "${MYSQL_INIT_LOG}" 2>&1
  /usr/bin/mysqld --user=mysql --bootstrap --verbose=0 < "${script}" >> "${MYSQL_INIT_LOG}" 2>&1
  rm -f "${script}"

  # Complete
  echo "  --> MySQL server initialized. Check the '${MYSQL_INIT_LOG}' file for details."
  touch "${MYSQL_INITDIR}/ready"
  return 0
}

#
# mysql_init_users()
#   Initializes required MySQL user accounts
#
mysql_init_users() {
  # Already initialized
  if [ -f "${MYSQL_INITDIR}/users" ]; then
    return 0
  fi
  echo "Initializing MySQL users..."

  # Configure 'ejbca' user
  root_pass="$(cat "${MYSQL_VAULTDIR}/root")"
  ejbca_pass="$(cat "${MYSQL_VAULTDIR}/ejbca")"
  mysql --user=root --password="${root_pass}" -e \
      "GRANT ALL PRIVILEGES ON ejbca.* TO 'ejbca'@'localhost' IDENTIFIED BY '${ejbca_pass}';" >>"${MYSQL_INIT_LOG}" 2>&1

  # Complete
  echo "  --> MySQL users initialized. Check the '${MYSQL_INIT_LOG}' file for details."
  touch "${MYSQL_INITDIR}/users"
  return 0
}

#
# mysql_start()
#   Starts the MySQL server
#
mysql_start() {
  # Initialize DB
  mysql_init

  # Start server
  echo "Starting MySQL server..."
  /usr/bin/mysqld_safe --user=mysql >"${MYSQL_LOG}" 2>&1 &
  mysql_wait 60
  echo "  --> MySQL server started. Check the '${MYSQL_LOG}' file for details."

  # Initialize users
  mysql_init_users
  return 0
}

#
# mysql_wait(num_sec)
#   Waits up to 'num_sec' seconds for MySQL server socket become available
#
mysql_wait() {
  max_wait=$1

  delay=1
  total_wait=0
  until [ $total_wait -gt $max_wait ]; do
    if [ -S /run/mysqld/mysqld.sock ]; then
      break
    fi
    echo "[${total_wait}/${max_wait}s elapsed] Waiting for MySQL server..."
    sleep $delay
    let total_wait=$total_wait+$delay
  done
  if [ $total_wait -gt $max_wait ]; then
    return 1
  else
    return 0
  fi
}
