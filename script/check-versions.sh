#!/usr/bin/env bash
#
# Keep every place that names a supported pgpool version in agreement.
#
# These drifted silently between v1.4.1 and v1.6.1: the docker build matrix moved
# to 4.5.8 while values.yaml stayed on 4.5.4, so the default `helm install`
# resolved to an image tag that had never been built and the pods sat in
# ImagePullBackOff.  Nothing failed at release time, because nothing was
# comparing the two.  Now something is.
#
# Run it by hand from anywhere in the tree; CI runs it on every pull request.

set -euo pipefail

TOP="$(git rev-parse --show-toplevel)"
cd "${TOP}"

WORKFLOW=.github/workflows/docker.yaml
SCHEMA=charts/pgpool-cloudsql/values.schema.json
VALUES=charts/pgpool-cloudsql/values.yaml
CHART=charts/pgpool-cloudsql/Chart.yaml

fail=0
err() {
  echo "ERROR: $*" >&2
  fail=1
}

matrix="$(yq eval '.jobs.docker_build.strategy.matrix.pgpool_version[]' "${WORKFLOW}")"
enum="$(yq -o=yaml eval '.properties.pgpool.properties.version.enum[]' "${SCHEMA}")"
values_default="$(yq eval '.pgpool.version' "${VALUES}")"
schema_default="$(yq -o=yaml eval '.properties.pgpool.properties.version.default' "${SCHEMA}")"
app_version="$(yq eval '.appVersion' "${CHART}")"

# the list of versions we build has to be exactly the list the chart will accept
if [ "$(sort <<<"${matrix}")" != "$(sort <<<"${enum}")" ]; then
  err "${WORKFLOW} build matrix and ${SCHEMA} version enum disagree:"
  diff --label "${WORKFLOW}" --label "${SCHEMA}" -u \
    <(sort <<<"${matrix}") <(sort <<<"${enum}") >&2 || true
fi

# ...and every default has to be a version we actually build, or the out-of-the-box
# install points at an image tag that does not exist
grep -qxF "${values_default}" <<<"${matrix}" ||
  err "${VALUES} pgpool.version '${values_default}' is not in the ${WORKFLOW} build matrix"

grep -qxF "${app_version}" <<<"${matrix}" ||
  err "${CHART} appVersion '${app_version}' is not in the ${WORKFLOW} build matrix"

[ "${schema_default}" = "${values_default}" ] ||
  err "${SCHEMA} version default '${schema_default}' != ${VALUES} pgpool.version '${values_default}'"

[ "${app_version}" = "${values_default}" ] ||
  err "${CHART} appVersion '${app_version}' != ${VALUES} pgpool.version '${values_default}' (appVersion should name the version we deploy by default)"

# the comment above pgpool.version in values.yaml is the list operators actually
# read, so it rots the same way and is worth pinning down too
comment_list="$(sed -n '/# what version of pgpool to use/,/^  version:/p' "${VALUES}" |
  grep -oE '^  # [0-9]+\.[0-9]+\.[0-9]+$' | awk '{print $2}')"
if [ "$(sort <<<"${comment_list}")" != "$(sort <<<"${matrix}")" ]; then
  err "the supported-version comment in ${VALUES} does not match the build matrix:"
  diff --label "${VALUES} comment" --label "${WORKFLOW}" -u \
    <(sort <<<"${comment_list}") <(sort <<<"${matrix}") >&2 || true
fi

# and the README table operators read before they ever look at values.yaml.
# Compare the supported-version list exactly rather than just checking that each
# version is mentioned somewhere: a retired version left behind in that row is
# every bit as misleading as a missing one, and "mentioned somewhere" is
# satisfied by an unrelated example or an old upgrade note.
# shellcheck disable=SC2016  # the backticks are literal markdown, not a subshell
readme_row="$(grep -F '`pgpool.version` |' README.md || true)"
if [ -z "${readme_row}" ]; then
  err "could not find the pgpool.version row in README.md"
else
  # take only the "Currently supported: ..." cell, not the default in the next one
  readme_list="$(sed -E 's/.*Currently supported: *//; s/\|.*$//' <<<"${readme_row}" |
    grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -u)"
  if [ "${readme_list}" != "$(sort <<<"${matrix}")" ]; then
    err "the supported-version list in README.md does not match the build matrix:"
    diff --label "README.md pgpool.version row" --label "${WORKFLOW}" -u \
      <(echo "${readme_list}") <(sort <<<"${matrix}") >&2 || true
  fi
fi

if [ "${fail}" -ne 0 ]; then
  echo >&2
  echo "pgpool version references are inconsistent; see the errors above." >&2
  exit 1
fi

echo "pgpool version references agree: $(tr '\n' ' ' <<<"${matrix}")"
echo "  default: ${values_default} (chart appVersion ${app_version})"
