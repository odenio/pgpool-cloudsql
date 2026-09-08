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

# Watches the core dump directory and, by default, stops pgpool from writing any
# further cores once we have captured one.  A pgpool child can dump hundreds of
# megabytes and there can be num_init_children of them, so left unbounded a crash
# loop will happily fill the volume (and, for an emptyDir, get the pod evicted).
# Keeping exactly the first core is bounded by construction and is the one you
# want anyway: it is the crash that has not yet been perturbed by whatever the
# earlier crashes broke.

# shellcheck disable=SC1091
. /usr/bin/functions.sh

COREDUMP_PATH="${COREDUMP_PATH:-"/var/coredumps"}"
COREDUMP_STOP_AFTER_FIRST="${COREDUMP_STOP_AFTER_FIRST:-"true"}"
COREDUMP_POLL_INTERVAL="${COREDUMP_POLL_INTERVAL:-5}"

shopt -s nullglob

# The pids of every running pgpool process, parent and children.  We read /proc
# directly rather than add a procps dependency for a single pgrep call.
pgpool_pids() {
  local proc comm
  for proc in /proc/[0-9]*; do
    [ -r "${proc}/comm" ] || continue
    read -r comm <"${proc}/comm" 2>/dev/null || continue
    if [ "${comm}" = "pgpool" ]; then
      echo "${proc#/proc/}"
    fi
  done
}

# Drop RLIMIT_CORE to zero on the running pgpool processes.  Setting it on the
# parent is what stops *future* children from dumping, since a child inherits the
# limit at fork; setting it on the existing children stops those as well.  There
# is no /proc interface for writing a limit, hence prlimit(1) from util-linux.
disable_further_coredumps() {
  local pid count=0
  if ! command -v prlimit >/dev/null 2>&1; then
    log error "prlimit not found; cannot disable further core dumps"
    return 1
  fi
  for pid in $(pgpool_pids); do
    if prlimit --pid "${pid}" --core=0:0 2>/dev/null; then
      count=$((count + 1))
    fi
  done
  if [ "${count}" -eq 0 ]; then
    log error "Found no pgpool processes to disable core dumps on"
    return 1
  fi
  log info "Set RLIMIT_CORE=0 on ${count} pgpool process(es)"
}

# The kernel writes a core incrementally, so wait for the size to settle before
# reporting on it (or before deciding we have "captured" it).
wait_until_complete() {
  local f="${1}" last="" cur
  while true; do
    cur="$(stat -c %s "${f}" 2>/dev/null)" || return 1
    if [ -n "${cur}" ] && [ "${cur}" = "${last}" ] && [ "${cur}" != "0" ]; then
      return 0
    fi
    last="${cur}"
    sleep 2
  done
}

log info "Watching ${COREDUMP_PATH} for core files (stopAfterFirst=${COREDUMP_STOP_AFTER_FIRST})"

declare -A seen

while true; do
  for core in "${COREDUMP_PATH}"/*; do
    [ -f "${core}" ] || continue
    [ -n "${seen[${core}]}" ] && continue
    seen["${core}"]=1

    log warning "Core file detected: ${core}"
    if wait_until_complete "${core}"; then
      log warning "Core file ${core} is complete ($(stat -c %s "${core}" 2>/dev/null) bytes)"
    else
      log error "Core file ${core} disappeared while we were waiting for it"
      continue
    fi

    if [ "${COREDUMP_STOP_AFTER_FIRST}" = "true" ]; then
      disable_further_coredumps
      log warning "Retaining ${core}. No further cores will be written until this pod is restarted."
      log info "Retrieve it with: kubectl cp <namespace>/<pod>:${core#/} ./$(basename "${core}") -c pgpool"
      exit 0
    fi
  done
  sleep "${COREDUMP_POLL_INTERVAL}"
done
