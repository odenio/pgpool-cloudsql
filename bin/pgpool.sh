#!/bin/bash

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

# pgpool has a tendency to leave core files around willy-nilly, which is
# disconcerting, so the default remains "don't dump at all".  Set
# pgpool.coredump.enabled when you actually need to catch a crash.
COREDUMP_ENABLED="${COREDUMP_ENABLED:-"false"}"
# the chart always passes COREDUMP_SIZE_LIMIT, but default it off the enable
# flag anyway so that running this image by hand with COREDUMP_ENABLED=true
# does not silently collect nothing
if [ "${COREDUMP_ENABLED}" = "true" ]; then
  COREDUMP_SIZE_LIMIT="${COREDUMP_SIZE_LIMIT:-"unlimited"}"
else
  COREDUMP_SIZE_LIMIT="${COREDUMP_SIZE_LIMIT:-"0"}"
fi
COREDUMP_PATH="${COREDUMP_PATH:-"/var/coredumps"}"
# the watcher is a child process and reads these from the environment; exporting
# here keeps its idea of the directory from diverging from the one we cd into
export COREDUMP_PATH COREDUMP_STOP_AFTER_FIRST

log info "Setting coredump size limit to ${COREDUMP_SIZE_LIMIT}"
ulimit -c "${COREDUMP_SIZE_LIMIT}" ||
  log warning "Could not set coredump size limit to ${COREDUMP_SIZE_LIMIT}"

if [ "${COREDUMP_ENABLED}" = "true" ]; then
  mkdir -p "${COREDUMP_PATH}" || log fatal "Could not create ${COREDUMP_PATH}"
  # pgpool only chdir()s to / as part of daemonizing, and we always run it with
  # -n, so it inherits our working directory.  That is what decides where the
  # kernel puts a core when core_pattern is a bare relative filename.
  cd "${COREDUMP_PATH}" || log fatal "Could not cd to ${COREDUMP_PATH}"
  log info "Core dumps enabled; working directory is ${COREDUMP_PATH}"

  # core_pattern is a node-wide kernel setting that we cannot change from inside
  # an unprivileged pod, and it decides whether we get to see the core at all.
  # Say so loudly at startup rather than letting someone wonder for an afternoon
  # why the directory stays empty.
  core_pattern="$(cat /proc/sys/kernel/core_pattern 2>/dev/null)"
  log info "Kernel core_pattern is '${core_pattern}'"
  case "${core_pattern}" in
  \|*)
    log warning "core_pattern pipes cores to a helper on the node: nothing will appear in ${COREDUMP_PATH}"
    ;;
  /*)
    log warning "core_pattern is an absolute path: cores land on the node filesystem, not in ${COREDUMP_PATH}"
    ;;
  esac

  /usr/bin/coredump-watch.sh &
fi

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
