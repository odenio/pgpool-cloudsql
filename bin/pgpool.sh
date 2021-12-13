#!/bin/bash -e

# Copyright 2021 Oden Technologies Inc (https://oden.io/)
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# shellcheck disable=SC1091
. /usr/bin/functions.sh

# there is no point in starting until the discovery script has generated
# our config file
until [ -f /etc/pgpool/pgpool.conf ]; do
  log info "Waiting 5s for our config to be generated"
  sleep 5
done

log info "Starting pgpool"
# even with TERSE debugging on, pgpool logs are very spammy :(
set -o pipefail
/usr/bin/pgpool -m fast -n 2>&1 | grep -E -v '(status_changed_time|using clear text authentication with frontend)'
EVAL="$?"
log error "pgpool exited with value ${EVAL}"
sleep 1 # don't spam the kubelet
log fatal "Exiting"
