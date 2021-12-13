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

METADATA_BASE="http://metadata.google.internal/computeMetadata/v1"
INST_META="${METADATA_BASE}/instance"
PROJ_META="${METADATA_BASE}/project"
NAMESPACE_FILE="/var/run/secrets/kubernetes.io/serviceaccount/namespace"

log(){
  local level msg highlight printcmd printflags emoji
  printcmd="${PRINTCMD:-echo}"
  printflags="${PRINTFLAGS:-"-e"}"
  level="$(tr '[:lower:]' '[:upper:]' <<< "${@:1:1}")"
  msg=("${@:2}")
  case "${level}" in
    FATAL) highlight="${RED}"; emoji="💀 "  ;;
    ERR*) highlight="${RED}"; emoji="⛔️ " ;;
    WARN*) highlight="${ORANGE}"; emoji="⚠️  " ;;
    DEBUG) if [[ "${DEBUG}" != "true" ]]; then return; fi; highlight=""; emoji="🔎 " ;;
    *) highlight="${CYAN}"; emoji="" ;;
  esac
  "${printcmd}" "${printflags}" "${highlight}$(date --iso=seconds --utc) ${emoji}${level}: ${msg[*]}${RST}" 1>&2
  if [[ "${level}" == "FATAL" ]]; then
    if [[ "${-}" =~ 'i' ]] ; then return 1; else exit 1; fi
  fi
}

get_repl_pool_node_id(){
  local ip dir suffix
  ip="${1}"
  dir="${2:-"${STATEDIR}"}"
  # start the count at 1 because pgpool.conf makes no distinction
  # between primaries and replicas at this level
  suffix=1
  if [ -z "${ip}" ]; then
    log error "You must provide an IP address"
    return 1
  fi
  mkdir -p "${dir}"
  if [ -f "${dir}"/"${ip}" ]; then
    suffix="$(cat "${dir}/${ip}")"
    log debug "Returning existing suffix for ${ip}: ${suffix}"
  else
    if ls "${dir}"/* >/dev/null 2>/dev/null; then
      log debug "state files exist already"
      suffix="$(cat "${dir}"/* | sort -nr | head -1)"
      log debug "highest: ${suffix}"
      ((suffix++))
    else
      log debug "no statefiles exist yet"
    fi
    log debug "Generated new suffix for ${ip}: ${suffix}"
    echo "${suffix}" > "${dir}/${ip}"
  fi

  echo "${suffix}"
}

get_metadata(){
  if [ "${DEBUG}" = "true" ]; then
    CURLFLAGS="-vf"
  else
    CURLFLAGS="-sf"
  fi
  
  if [ -f "${NAMESPACE_FILE}" ]; then
    NAMESPACE="$(cat "${NAMESPACE_FILE}")"
  else
    log warning "Could not find ${NAMESPACE_FILE} -- assuming we are in the default ns"
    NAMESPACE=default
  fi
  log info "Namespace: ${NAMESPACE}"

  log info "getting our location"
  until ZONE=$(curl "${CURLFLAGS}" -H 'Metadata-Flavor: Google' ${INST_META}/zone); do
    log warning "Could not get cluster location; sleeping 5s"
    sleep 5
  done
  ZONE="$(basename "${ZONE}")"
  REGION="$(cut -d- -f1-2 <<< "${ZONE}")"
  log info "Region: ${REGION}"
  log info "Zone: ${ZONE}"

  log info "getting our cluster name"
  until CLUSTER_NAME=$(curl "${CURLFLAGS}" -H 'Metadata-Flavor: Google' ${INST_META}/attributes/cluster-name); do
    log warning "Could not get cluster name; sleeping 5s"
    sleep 5
  done
  log info "Cluster name: ${CLUSTER_NAME}"

  log info "getting instance ID"
  until INSTANCE_ID=$(basename "$(curl "${CURLFLAGS}" -H 'Metadata-Flavor: Google' ${INST_META}/name)"); do
    log warning "Could not get instance ID; sleeping 5s"
    sleep 5
  done
  log info "Instance ID: ${INSTANCE_ID}"

  log info "Finding our GCP project ID"
  until PROJECT_ID="$(curl "${CURLFLAGS}" -H 'Metadata-Flavor: Google' ${PROJ_META}/project-id)"; do
    log error "Could not determine our GCP project ID; waiting 5s for the metadata api to become available"
    sleep 5
  done
  log info "GCP Project: ${PROJECT_ID}"

  export NAMESPACE REGION ZONE CLUSTER_NAME INSTANCE_ID PROJECT_ID
}
