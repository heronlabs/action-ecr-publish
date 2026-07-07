#!/usr/bin/env bash
set -euo pipefail

TAG="${BUILD_NAME}:${TAG_NAME}"

docker tag "${TAG}" "${AWS_REPOSITORY}/${TAG}"

docker push "${AWS_REPOSITORY}/${TAG}"

if [ -n "${TAG_ALIAS:-}" ]; then
  IFS=',' read -ra ALIASES <<< "${TAG_ALIAS}"
  for ALIAS in "${ALIASES[@]}"; do
    ALIAS_TAG="${BUILD_NAME}:${ALIAS}"
    docker tag "${TAG}" "${AWS_REPOSITORY}/${ALIAS_TAG}"
    docker push "${AWS_REPOSITORY}/${ALIAS_TAG}"
  done
fi
