#!/usr/bin/env bash
# Offline test harness for core/publish-ecr-image.sh.
#
# Points a `docker` stub at PATH, runs the action script with the env vars the
# action.yml wires in, and asserts on the tag/push calls captured in DOCKER_LOG.
# No real images, no registry, no network.
#
# shellcheck disable=SC2015  # `cond && ok || bad` is intentional; ok() always returns 0
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../core/publish-ecr-image.sh"
STUB_DIR="$HERE"   # contains the `docker` stub

pass=0
fail=0
note() { printf '  %s\n' "$*"; }
ok()   { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; [ -n "${2:-}" ] && note "$2"; }

# Run the action script with the `docker` stub on PATH. Captures combined output,
# exit code and the docker call log into RUN_OUT / RUN_RC / RUN_LOG.
# Usage: run_publish <env assignments...>
run_publish() {
  RUN_LOG="$(mktemp)"
  : >"$RUN_LOG"
  RUN_OUT="$(
    env PATH="$STUB_DIR:$PATH" \
        DOCKER_LOG="$RUN_LOG" \
        "$@" \
        bash "$SCRIPT" 2>&1
  )"
  RUN_RC=$?
}

# ---------------------------------------------------------------- tests

test_base_single_push() {
  run_publish BUILD_NAME=app TAG_NAME=sha1 AWS_REPOSITORY=123.dkr.ecr.amazonaws.com

  [ "$RUN_RC" -eq 0 ] && ok "base: exit 0" || bad "base: exit 0" "rc=$RUN_RC out=$RUN_OUT"
  grep -q '^docker tag app:sha1 123.dkr.ecr.amazonaws.com/app:sha1$' "$RUN_LOG" \
    && ok "base: tagged image for the repository" \
    || bad "base: tagged image for the repository" "$(cat "$RUN_LOG")"
  grep -q '^docker push 123.dkr.ecr.amazonaws.com/app:sha1$' "$RUN_LOG" \
    && ok "base: pushed the repository image" \
    || bad "base: pushed the repository image" "$(cat "$RUN_LOG")"

  local pushes; pushes="$(grep -c '^docker push ' "$RUN_LOG")"
  [ "$pushes" -eq 1 ] && ok "base: exactly one push" || bad "base: exactly one push" "count=$pushes log=$(cat "$RUN_LOG")"

  rm -f "$RUN_LOG"
}

test_alias_fans_out_pushes() {
  run_publish BUILD_NAME=app TAG_NAME=sha1 AWS_REPOSITORY=123.dkr.ecr.amazonaws.com TAG_ALIAS=latest,stable

  [ "$RUN_RC" -eq 0 ] && ok "alias: exit 0" || bad "alias: exit 0" "rc=$RUN_RC out=$RUN_OUT"
  grep -q '^docker tag app:sha1 123.dkr.ecr.amazonaws.com/app:latest$' "$RUN_LOG" \
    && ok "alias: comma-split produced latest" \
    || bad "alias: comma-split produced latest" "$(cat "$RUN_LOG")"
  grep -q '^docker tag app:sha1 123.dkr.ecr.amazonaws.com/app:stable$' "$RUN_LOG" \
    && ok "alias: comma-split produced stable" \
    || bad "alias: comma-split produced stable" "$(cat "$RUN_LOG")"
  grep -q '^docker push 123.dkr.ecr.amazonaws.com/app:latest$' "$RUN_LOG" \
    && ok "alias: pushed latest" \
    || bad "alias: pushed latest" "$(cat "$RUN_LOG")"
  grep -q '^docker push 123.dkr.ecr.amazonaws.com/app:stable$' "$RUN_LOG" \
    && ok "alias: pushed stable" \
    || bad "alias: pushed stable" "$(cat "$RUN_LOG")"

  local pushes; pushes="$(grep -c '^docker push ' "$RUN_LOG")"
  [ "$pushes" -eq 3 ] && ok "alias: three pushes total" || bad "alias: three pushes total" "count=$pushes log=$(cat "$RUN_LOG")"

  rm -f "$RUN_LOG"
}

test_missing_repository_hard_error() {
  run_publish BUILD_NAME=app TAG_NAME=sha1

  [ "$RUN_RC" -ne 0 ] && ok "missing repository: hard error (non-zero)" || bad "missing repository: hard error (non-zero)" "rc=$RUN_RC out=$RUN_OUT"

  rm -f "$RUN_LOG"
}

# ---------------------------------------------------------------- run

test_base_single_push
test_alias_fans_out_pushes
test_missing_repository_hard_error

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
