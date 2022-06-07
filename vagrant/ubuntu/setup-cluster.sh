#!/bin/bash
set -e
#set -x

# Green & Red marking for Success and Failed messages
SUCCESS='\033[0;32m'
FAILED='\033[0;31m'
NC='\033[0m'

/bin/bash ./ubuntu/setup-common.sh
echo "Starting to setup ETCD"
/bin/bash ./ubuntu/setup-etcd-cluster.sh