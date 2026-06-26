#!/usr/bin/env bats
# Offline test harness for core/publish-ecr-image.sh.
#
# Points the `docker` stub (sibling file) at PATH, runs the action script with
# the env vars that action.yml wires in, and asserts on the tag/push calls
# captured in DOCKER_LOG.
# shellcheck disable=SC2015  # `run script && ok` is intentional

setup() {
  DOCKER_LOG="$(mktemp)"
  export DOCKER_LOG
  PATH="${BATS_TEST_DIRNAME}:$PATH"
}

teardown() {
  rm -f "$DOCKER_LOG"
}

# Helper: run publish-ecr-image.sh with the given env vars.
run_script() {
  : >"$DOCKER_LOG"
  run env DOCKER_LOG="$DOCKER_LOG" PATH="${BATS_TEST_DIRNAME}:$PATH" "$@" bash "${BATS_TEST_DIRNAME}/../core/publish-ecr-image.sh"
}

@test "base: single push" {
  run_script BUILD_NAME=app TAG_NAME=sha1 AWS_REPOSITORY=123.dkr.ecr.amazonaws.com
  [ "$status" -eq 0 ]
  grep -q '^docker tag app:sha1 123.dkr.ecr.amazonaws.com/app:sha1$' "$DOCKER_LOG"
  grep -q '^docker push 123.dkr.ecr.amazonaws.com/app:sha1$' "$DOCKER_LOG"
  local pushes
  pushes="$(grep -c '^docker push ' "$DOCKER_LOG")"
  [ "$pushes" -eq 1 ]
}

@test "alias: comma-split fans out pushes" {
  run_script BUILD_NAME=app TAG_NAME=sha1 AWS_REPOSITORY=123.dkr.ecr.amazonaws.com TAG_ALIAS=latest,stable
  [ "$status" -eq 0 ]
  grep -q '^docker tag app:sha1 123.dkr.ecr.amazonaws.com/app:latest$' "$DOCKER_LOG"
  grep -q '^docker tag app:sha1 123.dkr.ecr.amazonaws.com/app:stable$' "$DOCKER_LOG"
  grep -q '^docker push 123.dkr.ecr.amazonaws.com/app:latest$' "$DOCKER_LOG"
  grep -q '^docker push 123.dkr.ecr.amazonaws.com/app:stable$' "$DOCKER_LOG"
  local pushes
  pushes="$(grep -c '^docker push ' "$DOCKER_LOG")"
  [ "$pushes" -eq 3 ]
}

@test "missing repository: hard error" {
  run_script BUILD_NAME=app TAG_NAME=sha1
  [ "$status" -ne 0 ]
}
