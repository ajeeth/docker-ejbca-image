#!/bin/bash
#
# EJBCA server container initialization script
#
set -e

# Suck in startup functions + variables
. /usr/local/lib/ejbca.sh
. /usr/local/lib/wildfly.sh

if [ "$1" == 'run' ]; then
  ejbca_startup_check
  wildfly_startup_check
  ejbca_start
elif [ "$1" == 'init' ]; then
  ejbca_init
elif [ "$1" == 'update-config' ]; then
  ejbca_update_config
else
  # Execute the command
  exec "$@"
fi
