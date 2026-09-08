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
  # Only matters when core_pattern is relative, in which case the kernel writes
  # the core to the crashing process's working directory.  pgpool only chdir()s
  # to / as part of daemonizing and we always run it with -n, so it inherits
  # ours.  Harmless in the absolute-path case that GKE gives us.
  cd "${COREDUMP_PATH}" || log fatal "Could not cd to ${COREDUMP_PATH}"
  log info "Core dumps enabled; core dump volume is ${COREDUMP_PATH}"

  # RLIMIT_CORE has a hard ceiling we inherit from the container runtime, and a
  # soft limit can never be raised above it.  If containerd (or dockerd) was
  # started with LimitCORE=0, no core can ever be written no matter how the
  # kernel's core_pattern is configured, and the failure is completely silent.
  # Report what we actually ended up with.
  log info "Core dump limit is now soft=$(ulimit -c) hard=$(ulimit -H -c)"
  if [ "$(ulimit -H -c)" = "0" ]; then
    log warning "The container runtime caps RLIMIT_CORE at 0, so no core can be written."
    log warning "This is set on the node, not in the pod; check LimitCORE= on the containerd systemd unit."
  fi

  # core_pattern is a node-wide kernel setting that a pod cannot change, and it
  # alone decides whether we ever see a core.  Work out at startup whether this
  # node is actually configured to give us one, and say so, rather than letting
  # someone wonder for an afternoon why the directory stays empty.
  #
  # For a non-pipe pattern the kernel creates the file in the *crashing
  # process's* mount namespace, so an absolute pattern lands inside this
  # container -- which is why GKE's node-pool sysctl allows absolute paths only.
  core_pattern="$(cat /proc/sys/kernel/core_pattern 2>/dev/null)"
  log info "Kernel core_pattern is '${core_pattern}'"
  case "${core_pattern}" in
  \|*)
    log warning "core_pattern pipes cores to a helper on the node, so nothing will appear in ${COREDUMP_PATH}."
    log warning "Set kernel.core_pattern to an absolute path under ${COREDUMP_PATH} on the node pool; see README.md."
    ;;
  /*)
    # the good case, provided the kernel is writing into the volume we mounted
    # rather than into the container's ephemeral upper layer
    core_dir="${core_pattern%/*}"
    if [ "${core_dir}" = "${COREDUMP_PATH}" ]; then
      log info "core_pattern writes into our core dump volume; core collection is ready"
    else
      log warning "core_pattern writes to '${core_dir}', which is not the mounted core dump volume ${COREDUMP_PATH}."
      log warning "Cores will land in the container's ephemeral storage and be lost when it restarts."
      log warning "Set pgpool.coredump.path to '${core_dir}', or repoint the node pool's kernel.core_pattern."
    fi
    ;;
  *)
    log warning "core_pattern '${core_pattern}' is relative, so cores follow the working directory."
    log warning "That works here, but GKE node pools only accept an absolute kernel.core_pattern; see README.md."
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
