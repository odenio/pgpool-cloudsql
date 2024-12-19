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

EXIT_ON_ERROR="${EXIT_ON_ERROR:-"false"}"
LOG_LEVEL="${LOG_LEVEL:-"info"}"

REQUIRED_VARS=(
  PGPOOL_SERVICE
  PGPOOL_SERVICE_PORT
  POSTGRES_DATABASE
  POSTGRES_PASSWORD
  POSTGRES_USERNAME
)

log info "Starting up!"
log info "Checking for required env vars"
for v in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!v}" ]; then
    log error "Required env var ${v} unset"
    FAIL=true
  fi
done

if [ "${FAIL}" ]; then
  log error "Missing required env vars, I cannot start"
  log info "Sleeping 10s so as not to spam the logs"
  sleep 10
  log fatal "Exiting"
fi
log info "Environment looks good"

# cf https://github.com/pgpool/pgpool2_exporter/blob/master/Dockerfile
DATA_SOURCE_NAME="postgresql://${POSTGRES_USERNAME}:${POSTGRES_PASSWORD}@${PGPOOL_SERVICE}:${PGPOOL_SERVICE_PORT}/${POSTGRES_DATABASE}?sslmode=disable"
scrubbed_dsn="postgresql://${POSTGRES_USERNAME}:*****@${PGPOOL_SERVICE}:${PGPOOL_SERVICE_PORT}/${POSTGRES_DATABASE}?sslmode=disable"
export DATA_SOURCE_NAME
log info "DSN: ${scrubbed_dsn}"

log info "Setting up PGPASSFILE"
PGPASSFILE="/.pgpass"
export PGPASSFILE
cat >"${PGPASSFILE}" <<EOF
${PGPOOL_SERVICE}:${PGPOOL_SERVICE_PORT}:${POSTGRES_DATABASE}:${POSTGRES_USERNAME}:${POSTGRES_PASSWORD}
EOF
chmod 0600 "${PGPASSFILE}"

set +e

# pgpool will not be available until the discovery script runs at least once
log info "Checking pgpool availability..."
until echo 'SELECT null;' | psql -h "${PGPOOL_SERVICE}" -p "${PGPOOL_SERVICE_PORT}" -U "${POSTGRES_USERNAME}" "${POSTGRES_DATABASE}" 2>/dev/null >/dev/null; do
  log info "Pgpool not available yet; sleeping 5s"
  sleep 5
done

log info "Starting pgpool2_exporter with LOG_LEVEL=${LOG_LEVEL} EXIT_ON_ERROR=${EXIT_ON_ERROR}"

while true; do
  /bin/pgpool2_exporter --web.listen-address=":9090" --log.level="${LOG_LEVEL}" --log.format=logfmt 2>&1
  EXITVAL="$?"
  if [[ "${EXIT_ON_ERROR}" == "true" ]]; then
    log fatal "pgpool2_exporter exited with value ${EXITVAL}"
  fi
  log error "pgpool2_exporter exited with value ${EXITVAL}"
  sleep 1 # don't spam the kubelet
done

log info "exiting..."
