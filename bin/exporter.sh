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

REQUIRED_VARS=(
  PGPOOL_SERVICE
  PGPOOL_SERVICE_PORT
  POSTGRES_DATABASE
  POSTGRES_PASSWORD
  POSTGRES_USERNAME
)

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

# cf https://github.com/pgpool/pgpool2_exporter/blob/master/Dockerfile
DATA_SOURCE_NAME="postgresql://${POSTGRES_USERNAME}:${POSTGRES_PASSWORD}@${PGPOOL_SERVICE}:${PGPOOL_SERVICE_PORT}/${POSTGRES_DATABASE}?sslmode=disable"
export DATA_SOURCE_NAME

PGPASSFILE="/.pgpass"
export PGPASSFILE
cat >"${PGPASSFILE}" <<EOF
${PGPOOL_SERVICE}:${PGPOOL_SERVICE_PORT}:${POSTGRES_DATABASE}:${POSTGRES_USERNAME}:${POSTGRES_PASSWORD}
EOF
chmod 0600 "${PGPASSFILE}"

# pgpool will not be available until the discovery script runs at least once
until echo 'SELECT null;' | psql -h "${PGPOOL_SERVICE}" -p "${PGPOOL_SERVICE_PORT}" -U "${POSTGRES_USERNAME}" "${POSTGRES_DATABASE}" 2>/dev/null >/dev/null; do
  log info "Pgpool not available yet; sleeping 5s"
  sleep 5
done

set -o pipefail
/usr/bin/pgpool2_exporter --log.level=info --log.format=logfmt 2>&1
EVAL="$?"
log error "pgpool2_exporter exited with value ${EVAL}"
sleep 1 # don't spam the kubelet
log fatal "Exiting"
