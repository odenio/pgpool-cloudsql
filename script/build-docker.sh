#!/usr/bin/env bash
#
# warning: this is not meant for external use and will fail badly in most cases.
#
# The github action this backstops (.github/workflows/docker.yaml) is now wired
# up to actually run -- release.yml calls it directly, because the `release:
# published` event it used to wait on is never delivered for a release cut by
# GITHUB_TOKEN.  Keep this around for building images by hand anyway: testing a
# patch from patches/, or re-cutting an image without re-cutting a release.
#
# Note that by default this script sets STRIP_BINARIES to "false" -- if you're
# testing patches you probably want the ability to generate a gdb backtrace.

set -euo pipefail

TOP="$(git rev-parse --show-toplevel)"

cd "${TOP}"

CHART_VERSION="$(yq eval '.version' <charts/pgpool-cloudsql/Chart.yaml)"
REPOSITORY="${REPOSITORY:-"$1"}"
APPLY_PATCHES="${APPLY_PATCHES:-"true"}"
STRIP_BINARIES="${STRIP_BINARIES:-"false"}"
TAG_SUFFIX="${TAG_SUFFIX:-"$2"}"

if [ -z "${REPOSITORY}" ]; then
  echo "*** FATAL: You must set the docker repository, either as the first arg or the REPOSITORY env var"
  exit 1
fi

yq eval '.jobs.docker_build.strategy.matrix.pgpool_version[]' <.github/workflows/docker.yaml | while read -r PGPOOL_VERSION; do
  tag="${REPOSITORY}:${CHART_VERSION}-${PGPOOL_VERSION}"
  if [ "${TAG_SUFFIX}" ]; then
    tag="${tag}-${TAG_SUFFIX}"
  fi
  echo "*** Building ${tag}"
  docker build \
    --build-arg PGPOOL_VERSION="${PGPOOL_VERSION}" \
    --build-arg APPLY_PATCHES="${APPLY_PATCHES}" \
    --build-arg STRIP_BINARIES="${STRIP_BINARIES}" \
    --pull \
    -t "${tag}" \
    --push \
    .
done
