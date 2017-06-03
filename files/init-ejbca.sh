#!/bin/bash
#
# EJBCA server container initialization script
#
set -e

if [ "$1" == 'ejbca' ]; then
  # Suck in startup functions + variables
  . /usr/local/lib/init.sh

  # Start MySQL server
  mysql_start

  # Start Wildfly server
  wildfly_start
else
  # Execute the command
  exec "$@"
fi
