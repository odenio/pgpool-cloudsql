#!/bin/sh -ex
#

if [ "${APPLY_PATCHES}" == "true" ]; then
  for f in patches/*; do
    echo "*** Applying prebuild patch: ${f}"
    patch -p1 -u -s <"${f}"
  done
else
  echo "*** Skipping patch apply"
fi
