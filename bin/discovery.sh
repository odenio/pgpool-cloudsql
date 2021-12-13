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

PGPDIR="${PGPDIR:-"/etc/pgpool"}"
CONFIG="${PGPDIR}/pgpool.conf"
TMPLDIR="${TMPLDIR:-"/etc/templates"}"
TEMPLATE="${TMPLDIR}/pgpool.conf.tmpl"
STATEDIR="${STATEDIR:-"/etc/pgpool/nodes"}"
REFRESH_INTERVAL="${REFRESH_INTERVAL:-60}"

export STATEDIR

PATH=/bin:/usr/bin:/usr/local/bin:/usr/local/gcloud/google-cloud-sdk/bin

# shellcheck disable=SC1091
. /usr/bin/functions.sh

if [ -z "${PRIMARY_INSTANCE_PREFIX}" ]; then
  log fatal "PRIMARY_INSTANCE_PREFIX unset"
fi

get_metadata

# set up passwordless pcp auth
if [ -z "${PCP_PASSWORD}" ]; then
  log info "PCP_PASSWORD unset; generating a random one"
  PCP_PASSWORD="$(head -c 10 /dev/urandom | base64)"
fi
PCP_PASSWORD_HASH="$(pg_md5 "${PCP_PASSWORD}")"
export PCP_PASSWORD PCP_PASSWORD_HASH
envtpl -m error -o /root/.pcppass "${TMPLDIR}/pcppass.tmpl" || log fatal "Error processing ${TMPLDIR}/pcppass.tmpl"
envtpl -m error -o "${PGPDIR}/pcp.conf" "${TMPLDIR}/pcp.conf.tmpl" || log fatal "Error processing ${TMPLDIR}/pcp.conf.tmpl"
chmod 0600 /root/.pcppass

# copy in static config files
for conf in "${TMPLDIR}"/*.conf; do
  log info "Copying ${conf} to ${PGPDIR}"
  cp "${conf}" "${PGPDIR}/"
done

mkdir -p "${STATEDIR}"

declare -a active_replicas

while true; do
  log info "Looking up primary instance matching prefix '${PRIMARY_INSTANCE_PREFIX}'"
  until mapfile -t primary_instances < <(
    gcloud \
      --project "${PROJECT_ID}" \
      sql instances list \
        --filter "region:${REGION} AND name:${PRIMARY_INSTANCE_PREFIX} AND state:RUNNABLE AND instanceType:CLOUD_SQL_INSTANCE" \
        --format 'csv[no-heading](name,ip_addresses.filter("type:PRIVATE").*extract(ip_address).flatten())'); do
    log error "Could not successfully look up primary instance matching ${PRIMARY_INSTANCE_PREFIX}, sleeping 5s and re-looping"
    sleep 5
    continue
  done

  if [[ "${#primary_instances[@]}" -ne 1 ]]; then
    log error "${#primary_instances[@]} entries returned by primary lookup?! '${primary_instances[*]}' sleeping 5s and retrying."
    sleep 5
    continue
  fi

  unset primary_name primary_ip
  IFS="," read -r primary_name primary_ip <<< "${primary_instances[0]}"

  if [ -z "${primary_ip}" ]; then
    log error "No primary IP found for ${primary_name}; sleeping 5s and retrying."
    sleep 5
    continue
  fi

  log info "found primary instance ${primary_name} at ${primary_ip}"
  export "primary_ip=${primary_ip}"

  log info "Looking up replicas"

  # otherwise old dbs persist...
  mapfile -t replica_vars < <(compgen -A variable replica_ip_)
  if [[ "${#replica_vars[@]}" -gt 0 ]]; then
    for repl_var in "${replica_vars[@]}"; do
      log debug "Unsetting ${repl_var}"
      unset "${repl_var}"
    done
  fi

  mapfile -t current_replicas < <(
    gcloud \
      --project "${PROJECT_ID}" \
      sql instances list \
        --sort-by serverCaCert.createTime \
        --filter "region:${REGION} AND masterInstanceName:${PROJECT_ID}:${primary_name} AND state:RUNNABLE" \
        --format 'csv[no-heading](name,ip_addresses.filter("type:PRIVATE").*extract(ip_address).flatten())' \
      )

  for replspec in "${current_replicas[@]}"; do
    IFS="," read -r repl_dbname repl_private_ip <<< "${replspec}"
    if [[ "${repl_private_ip}" ]]; then
      pool_node_id="$(get_repl_pool_node_id "${repl_private_ip}" "${STATEDIR}")"
      if [[ -z "${pool_node_id}" ]]; then
        log error "Could not get a pool node id for ${repl_private_ip}, which is probably very bad; skipping"
        continue
      fi
      log info "${repl_dbname} at ${repl_private_ip} assigned node ID: ${pool_node_id}"
      export "replica_ip_${pool_node_id}=${repl_private_ip}"
    else
      log warning "Could not find a private IP address for ${repl_dbname} -- skipping"
    fi
  done

  tmpfile="$(mktemp)"
  log info "Generating temporary config ${tmpfile}"
  envtpl -m error -o "${tmpfile}" "${TEMPLATE}" || log fatal "Error processing ${TEMPLATE}"

  if ! [[ -f "${CONFIG}" ]]; then
    log warning "No config file present; we must be in pod startup"
    mv "${tmpfile}" "${CONFIG}"
    log info "Sleeping ${REFRESH_INTERVAL} seconds before looking again"
    # since we're starting up, active_replicas == current_replicas
    active_replicas=("${current_replicas[@]}")
    sleep "${REFRESH_INTERVAL}"
    continue
  fi

  if ! cmp "${tmpfile}" "${CONFIG}"; then
    log info "Config diff found:"
    diff "${CONFIG}" "${tmpfile}" || true
    log info "Updating ${CONFIG}"
    ${DRY_RUN} mv "${tmpfile}" "${CONFIG}"
    log info "Forcing pgpool config reload"
    ${DRY_RUN} pcp_reload_config -h localhost --no-password || log fatal "pgpool reload returned status $?"
  else
    log info "No config diff found; nothing to do"
  fi
  ${DRY_RUN} rm -f "${tmpfile}"

  # Just adding a node to the config isn't enough: we need to attach any new ones.
  # (if by some chance our container restarts w/o the pod restarting, we'll re-attach
  # all of the current replicas, but that's fine: it's a no-op)
  for replspec in "${current_replicas[@]}"; do
    IFS="," read -r repl_dbname repl_private_ip <<< "${replspec}"
    if ! printf '%s\0' "${active_replicas[@]}" | grep -qzoP "${repl_private_ip}\n?"; then
      pool_node_id="$(get_repl_pool_node_id "${repl_private_ip}" "${STATEDIR}")"
      if [[ -z "${pool_node_id}" ]]; then
        log error "Could not get a pool node id for ${repl_private_ip}, which is probably very bad; skipping"
        continue
      fi
      log info "Attaching node ${pool_node_id} (${repl_private_ip})"
      pcp_attach_node -h localhost -w "${pool_node_id}" || log error "Could not attach node ${pool_node_id}"
    fi
  done

  active_replicas=("${current_replicas[@]}")

  log info "Sleeping ${REFRESH_INTERVAL} seconds before looking again"
  sleep "${REFRESH_INTERVAL}"
done
