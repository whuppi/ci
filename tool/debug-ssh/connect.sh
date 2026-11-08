#!/usr/bin/env bash
# connect.sh <owner/repo> <run-id> [command…] — log in to a runner that
# actions/debug-ssh opened. Waits for the ssh-info-<OS> artifact (it exists
# while the job is still running), then runs ssh with it. Exits non-zero,
# saying why, when the run ends without a tunnel.
#
# The key is whichever key in your agent or ~/.ssh GitHub knows; set
# DEBUG_SSH_KEY=<path> to pick one when you hold several.
set -euo pipefail
repo="${1:?usage: connect.sh <owner/repo> <run-id> [command…]}"
run="${2:?usage: connect.sh <owner/repo> <run-id> [command…]}"
shift 2
dir="$(mktemp -d)"; trap 'rm -rf "${dir:?}"' EXIT
for _ in $(seq 1 120); do
  if gh run download "$run" -R "$repo" -p 'ssh-info-*' -D "$dir" >/dev/null 2>&1; then break; fi
  if [ "$(gh run view "$run" -R "$repo" --json status -q .status)" = completed ]; then
    echo "run $run ended without opening a tunnel; read its log: gh run view $run -R $repo --log-failed" >&2
    exit 1
  fi
  sleep 15
done
cmd="$(cat "$(find "$dir" -name connect.txt | sed -n 1p)")" \
  || { echo "no tunnel after 30 minutes of waiting on run $run" >&2; exit 1; }
port="$(printf '%s' "$cmd" | sed -nE 's/.*-p ([0-9]+).*/\1/p')"
user="$(printf '%s' "$cmd" | sed -nE 's/.* ([a-z]+)@bore\.pub.*/\1/p')"
key=()
[ -n "${DEBUG_SSH_KEY:-}" ] && key=(-i "$DEBUG_SSH_KEY" -o IdentitiesOnly=yes)
exec ssh ${key[@]+"${key[@]}"} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o ServerAliveInterval=30 -o ConnectTimeout=20 -p "$port" "$user@bore.pub" "$@"
