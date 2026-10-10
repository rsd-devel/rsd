#!/usr/bin/env bash
# Start the repository's dev container and run a command inside it.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ./DevContainer.sh [--rebuild] [--] [command [args...]]

With no command, open a login Bash shell in the current checkout directory.
Otherwise, run the command there and return its exit status.
Invocations from outside the checkout use the repository directory.
Changes under .devcontainer/ automatically recreate this script's container,
using Docker's build cache. --rebuild forces recreation with the same cache.
The container is separate from containers opened by VS Code.
Startup state is stored in Processor/Tools/DevContainer/State/<Docker daemon ID>/.

Host requirements: Bash, Python 3, flock, Docker, and the Dev Container CLI.
Examples:
  ./DevContainer.sh
  ./DevContainer.sh make -C Processor/Src -f Makefile.verilator.mk test-1
  cd Processor/Src
  ../../DevContainer.sh make -f Makefile.verilator.mk
EOF
}

rebuild=0
while (( $# )); do
    case "$1" in
        --rebuild) rebuild=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
        *) break ;;
    esac
done

for tool in python3 flock docker devcontainer; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "$tool" >&2
        if [[ "$tool" == devcontainer ]]; then
            printf 'See Getting started in README.md for CLI installation.\n' >&2
        fi
        exit 1
    fi
done

# Resolve entry-point symlinks before locating the repository.
repo_root=$(python3 - "${BASH_SOURCE[0]}" <<'PYROOT'
from pathlib import Path
import sys

print(Path(sys.argv[1]).resolve(strict=True).parents[3])
PYROOT
)
# Map the caller's location to the same relative directory in the container.
relative_dir=$(python3 - "$repo_root" <<'PYCWD'
from pathlib import Path
import sys

try:
    print(Path.cwd().relative_to(Path(sys.argv[1])))
except ValueError:
    print('.')
PYCWD
)
# NFS shares the checkout, but each Docker daemon has its own containers.
# Track each daemon separately so another machine cannot consume its changes.
daemon_id=$(docker info --format '{{.ID}}')
case "$daemon_id" in
    ''|*[!a-zA-Z0-9:_-]*) printf 'Docker daemon did not return a valid ID.\n' >&2; exit 1 ;;
esac
state_dir="$repo_root/Processor/Tools/DevContainer/State/$daemon_id"
mkdir -p "$state_dir"

# Serialize startup for this daemon without blocking other machines on NFS.
exec 9>"$state_dir/start.lock"
flock 9

# The build context is .devcontainer/. Hash contents, names, and permissions,
# so edits and file additions/deletions are detected independently of mtimes.
fingerprint=$(python3 - "$repo_root/.devcontainer" <<'PY'
import hashlib
import os
from pathlib import Path
import sys

root = Path(sys.argv[1])
if not (root / 'devcontainer.json').is_file():
    sys.exit('Missing .devcontainer/devcontainer.json')
digest = hashlib.sha256()
digest.update(f'{os.getuid()}:{os.getgid()}\0'.encode())
for path in sorted(root.rglob('*')):
    if path.is_file():
        digest.update(str(path.relative_to(root)).encode() + b'\0')
        digest.update(str(path.stat().st_mode & 0o777).encode() + b'\0')
        digest.update(hashlib.sha256(path.read_bytes()).digest())
print(digest.hexdigest())
PY
)

previous=''
if [[ -f "$state_dir/fingerprint" ]]; then
    previous=$(cat "$state_dir/fingerprint")
fi

# A dedicated label keeps automatic recreation separate from VS Code sessions.
container_args=(--workspace-folder "$repo_root" --id-label "rsd.devcontainer.workspace=$repo_root")
up_args=()
if [[ "$fingerprint" != "$previous" || "$rebuild" == 1 ]]; then
    printf 'Dev container inputs changed or rebuild requested; preparing the environment.\n' >&2
    up_args+=(--remove-existing-container)
fi

# Keep build/setup output off the executed command's stdout, and preserve stdin.
devcontainer up "${container_args[@]}" "${up_args[@]}" </dev/null >&2
printf '%s\n' "$fingerprint" >"$state_dir/fingerprint.tmp"
mv -- "$state_dir/fingerprint.tmp" "$state_dir/fingerprint"
flock -u 9
exec 9>&-

if (( $# == 0 )); then
    set -- bash -l
fi
# devcontainer exec starts at the container workspace root. Pass the directory
# and command as separate arguments so spaces and shell metacharacters stay literal.
exec devcontainer exec "${container_args[@]}" -- /bin/sh -c \
    'cd -- "$1" && shift && exec "$@"' DevContainer.sh "./$relative_dir" "$@"
