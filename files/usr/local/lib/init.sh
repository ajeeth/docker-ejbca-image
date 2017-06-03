#
# Shared functions and variables used by EJBCA container init script
#

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# EJBCA functions and variables
. ${SCRIPT_DIR}/ejbca.sh

# MySQL server functions and variables
. ${SCRIPT_DIR}/mysql.sh

# Wildfly server functions and variables
. ${SCRIPT_DIR}/wildfly.sh
