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

get_metadata

set +e
log info "Starting up telegraf"
/bin/telegraf --config /etc/telegraf/telegraf.conf
EVAL="$?"
log error "Telegraf exited with status $EVAL"
sleep 1  # don't spam the kubelet
log fatal "Exiting"
