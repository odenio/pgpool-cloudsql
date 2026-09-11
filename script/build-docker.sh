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

set -euo pipefail

TOP="$(git rev-parse --show-toplevel)"

cd "${TOP}"

CHART_VERSION="$(yq eval '.version' <charts/pgpool-cloudsql/Chart.yaml)"

REPOSITORY="${REPOSITORY:-"odentech/pgpool-cloudsql"}"

yq eval '.jobs.docker_build.strategy.matrix.pgpool_version[]' <.github/workflows/docker.yaml | while read -r PGPOOL_VERSION; do
  tag="${REPOSITORY}:${CHART_VERSION}-${PGPOOL_VERSION}"
  echo "*** Building ${tag}"
  docker build \
    --build-arg PGPOOL_VERSION="${PGPOOL_VERSION}" \
    --build-arg APPLY_PATCHES="true" \
    --pull \
    -t "${tag}" \
    --push \
    .
done
