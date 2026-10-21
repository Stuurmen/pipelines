#!/usr/bin/env bash
# End-to-end test for deploy-v2.1.1: runs the real workflow with act against a throwaway SSH server.
# Needs Docker and act (brew install act). Usage: test/run.sh [scenario ...]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/deploy-v2.1.1.yml"
WORK="$(mktemp -d)"
NET=pipeline-test-net
SSHD=pipeline-test-sshd
IMAGE=pipeline-test-sshd
RUNNER_IMAGE="${RUNNER_IMAGE:-catthehacker/ubuntu:act-24.04}"
THEMES=/home/deploy/public/wp-content/themes
PASS=0; FAIL=0; FAILED=""

cleanup() { docker rm -f "$SSHD" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; if [ "$FAIL" -gt 0 ] || [ -n "${KEEP:-}" ]; then echo "Logs kept in $WORK"; else rm -rf "$WORK"; fi; }
trap cleanup EXIT

# --- Throwaway server -------------------------------------------------------
docker build -q -t "$IMAGE" "$ROOT/test/sshd" >/dev/null
docker network create "$NET" >/dev/null 2>&1 || true
ssh-keygen -q -t ed25519 -N '' -f "$WORK/client_key"
docker rm -f "$SSHD" >/dev/null 2>&1 || true
docker run -d --name "$SSHD" --network "$NET" --network-alias sshd "$IMAGE" >/dev/null
docker cp "$WORK/client_key.pub" "$SSHD:/home/deploy/.ssh/authorized_keys"
docker exec "$SSHD" sh -c 'chown -R deploy:deploy /home/deploy/.ssh && chmod 600 /home/deploy/.ssh/authorized_keys'

server() { docker exec "$SSHD" sh -c "$1"; }
exists() { server "test -e '$THEMES/$1'"; }

# --- Helpers ------------------------------------------------------------------
# project <branch> <pipeline.json content> [dry_run]: builds a git repo that calls the workflow under test
project() {
  set -e
  local dir="$WORK/project-$RANDOM"
  cp -R "$ROOT/test/fixture" "$dir"
  mkdir -p "$dir/.github/workflows"
  # act's artifact server only speaks the upload-artifact v4 protocol; this is the one change to the workflow under test
  sed -E 's|actions/upload-artifact@[0-9a-f]{40}.*|actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2 (act)|' \
    "$WORKFLOW" > "$dir/.github/workflows/deploy-v2.1.1.yml"
  printf '%s\n' "$2" > "$dir/pipeline.json"
  cat > "$dir/.github/workflows/caller.yml" <<EOF
on: push
jobs:
  deploy:
    uses: ./.github/workflows/deploy-v2.1.1.yml
    with:
      dry_run: ${3:-false}
    secrets:
      ssh_private_key: \${{ secrets.SSH_KEY }}
EOF
  git -C "$dir" init -q -b "$1"
  git -C "$dir" add -A
  git -C "$dir" -c user.email=test@example.com -c user.name=test commit -q -m fixture
  echo "$dir"
}

# config <environment> <path> [extra source json]
config() {
  local extra="${3:-}"; [ -n "$extra" ] || extra="{}"
  jq -n --arg path "$2" --argjson source "$extra" '{
    production: { branch: "master", host: "sshd", port: "22", username: "deploy", path: $path, node_version: "20" },
    staging:    { branch: "dev",    host: "sshd", port: "22", username: "deploy", path: $path, node_version: "20" },
    source: ({ path: "", package_manager: "npm" } + $source)
  }'
}

run_act() {
  (cd "$1" && act push -W .github/workflows/caller.yml \
    -P ubuntu-latest="$RUNNER_IMAGE" --network "$NET" --pull=false \
    --secret SSH_KEY="$(cat "$WORK/client_key")" \
    --artifact-server-path "$WORK/artifacts" >"$1.log" 2>&1)
}

check() { if eval "$2"; then echo "    ok   $1"; else echo "    FAIL $1"; return 1; fi; }

scenario() {
  local name="$1"; shift
  if [ -n "$SELECTED" ] && [[ " $SELECTED " != *" $name "* ]]; then return; fi
  echo "• $name"
  if "$@"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); FAILED="$FAILED $name"; fi
}

# --- Scenarios ----------------------------------------------------------------
staging_with_composer() {
  server "mkdir -p $THEMES/a && echo '{}' > $THEMES/a/pipeline.json && echo old > $THEMES/a/old.txt && chown -R deploy $THEMES/a"
  local dir; dir="$(project dev "$(config staging ./public/wp-content/themes/a '{"composer": true, "php_version": "8.3"}')")"
  local ok=0
  check "run succeeds" 'run_act "$dir"' || ok=1
  check "production build shipped" 'server "grep -q production-build $THEMES/a/dist/app.css"' || ok=1
  check "theme files shipped" 'exists a/style.css && exists a/functions.php && exists a/resources/views/index.blade.php' || ok=1
  check "vendor/ installed by Composer" 'exists a/vendor/autoload.php' || ok=1
  for f in pipeline.json package.json composer.json composer.lock README.md .env .git .github .cache-loader .vscode node_modules; do
    check "$f not on server" '! exists "a/$f"' || ok=1
  done
  check "stale file kept without delete" 'exists a/old.txt' || ok=1
  check ".htaccess shipped" 'exists a/.htaccess' || ok=1
  return $ok
}

production_with_delete() {
  server "mkdir -p $THEMES/b/vendor && echo old > $THEMES/b/old.txt && echo keep > $THEMES/b/vendor/keep.php && chown -R deploy $THEMES/b"
  local dir; dir="$(project master "$(config production ./public/wp-content/themes/b '{"delete": true}')")"
  local ok=0
  check "run succeeds" 'run_act "$dir"' || ok=1
  check "stale file removed with delete" '! exists b/old.txt' || ok=1
  check "hand-managed vendor/ untouched" 'exists b/vendor/keep.php && ! exists b/vendor/autoload.php' || ok=1
  check "production build shipped" 'server "grep -q production-build $THEMES/b/dist/app.css"' || ok=1
  return $ok
}

# expect_failure <name of server folder> <branch> <pipeline.json> <expected log text>
expect_failure() {
  # shellcheck disable=SC2034 # used inside the check strings
  local folder="$1" want="$4"
  server "mkdir -p $THEMES/$1 && echo marker > $THEMES/$1/marker.txt && chown -R deploy $THEMES/$1"
  local dir; dir="$(project "$2" "$3")"
  local ok=0
  check "run fails" '! run_act "$dir"' || ok=1
  check "error explains why ($want)" 'grep -q "$want" "$dir.log"' || ok=1
  check "server untouched" '[ "$(server "ls -A $THEMES/$folder")" = marker.txt ]' || ok=1
  return $ok
}

unknown_branch()   { expect_failure c feature/x "$(config staging ./public/wp-content/themes/c)" "neither the production nor the staging branch"; }
invalid_json()     { expect_failure d dev '{ "staging": { "branch": "dev", }, }' "not valid JSON"; }
delete_on_shared_folder() { expect_failure g dev "$(config staging ./public/wp-content/themes '{"delete": true}')" "points at a shared folder"; }
unsafe_path()      { expect_failure h dev "$(config staging "./public/x'; rm -rf ~; '")" "may only contain"; }

# A Yarn 1 project, like the other Sage 9 themes
yarn1_project() {
  server "mkdir -p $THEMES/k && chown -R deploy $THEMES/k"
  local dir; dir="$(project dev "$(config staging ./public/wp-content/themes/k '{"package_manager": "yarn"}')")"
  (cd "$dir" && npx -y yarn@1.22.22 install >/dev/null 2>&1 && git add -A && git -c user.email=test@example.com -c user.name=test commit -q -m yarn1)
  local ok=0
  check "run succeeds" 'run_act "$dir"' || ok=1
  check "production build shipped" 'server "grep -q production-build $THEMES/k/dist/app.css"' || ok=1
  return $ok
}

# A Yarn 4 project (yarnPath in .yarnrc.yml): the runner's Yarn 1 hands over to it
yarn4_project() {
  server "mkdir -p $THEMES/j && chown -R deploy $THEMES/j"
  local dir; dir="$(project dev "$(config staging ./public/wp-content/themes/j '{"package_manager": "yarn"}')")"
  (cd "$dir" && npx -y yarn@1.22.22 set version 4.18.1 >/dev/null && YARN_ENABLE_IMMUTABLE_INSTALLS=0 node .yarn/releases/yarn-4.18.1.cjs install >/dev/null \
    && git add -A && git -c user.email=test@example.com -c user.name=test commit -q -m yarn4)
  local ok=0
  check "run succeeds" 'run_act "$dir"' || ok=1
  check "production build shipped" 'server "grep -q production-build $THEMES/j/dist/app.css"' || ok=1
  check ".yarn/ and .yarnrc.yml not on server" '! exists j/.yarn && ! exists j/.yarnrc.yml' || ok=1
  return $ok
}

dry_run_on_feature_branch() {
  server "mkdir -p $THEMES/i && echo marker > $THEMES/i/marker.txt && chown -R deploy $THEMES/i"
  local dir; dir="$(project feature/x "$(config production ./public/wp-content/themes/i)" true)"
  local ok=0
  check "run succeeds" 'run_act "$dir"' || ok=1
  check "release uploaded as artifact" 'grep -q "Release contains" "$dir.log" && [ -n "$(find "$WORK/artifacts" -type f 2>/dev/null)" ]' || ok=1
  check "server untouched" '[ "$(server "ls -A $THEMES/i")" = marker.txt ]' || ok=1
  return $ok
}

SELECTED="$*"
docker image inspect "$RUNNER_IMAGE" >/dev/null 2>&1 || docker pull -q "$RUNNER_IMAGE" >/dev/null

scenario staging_with_composer staging_with_composer
scenario production_with_delete production_with_delete
scenario unknown_branch unknown_branch
scenario invalid_json invalid_json
scenario delete_on_shared_folder delete_on_shared_folder
scenario unsafe_path unsafe_path
scenario dry_run_on_feature_branch dry_run_on_feature_branch
scenario yarn1_project yarn1_project
scenario yarn4_project yarn4_project

echo
echo "$PASS passed, $FAIL failed${FAILED:+:$FAILED}"
[ "$FAIL" -eq 0 ]
