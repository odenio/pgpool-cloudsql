#!/usr/bin/env bash -e
#

# warning: this is not meant for external use and will fail badly
# in most cases.  This is used internally as a backstop for when the incredibly
# fussy github action fails.
#

TOP="$(git rev-parse --show-toplevel)"

cd "${TOP}"

CHART_VERSION="$(yq eval '.version' <charts/pgpool-cloudsql/Chart.yaml)"

REPOSITORY="${REPOSITORY:-"odentech/pgpool-cloudsql"}"

yq eval '.jobs.docker_build.strategy.matrix.pgpool_version[]' <.github/workflows/docker.yaml | while read PGPOOL_VERSION; do
  tag="${REPOSITORY}:${CHART_VERSION}-${PGPOOL_VERSION}"
  echo "*** Building ${tag}"
  docker build \
    --build-arg PGPOOL_VERSION="${PGPOOL_VERSION}" \
    --build-arg APPLY_PATCHES="TRUE" \
    --pull \
    -t "${tag}" \
    --push \
    .
done
