#!/usr/bin/env sh
# Backs up a self-hosted Nixflow: database, uploaded files and .env.
#   ./backup.sh [folder]        (default: ./backups)
# Nixflow is stopped for the few seconds the copy takes, so the database files
# are consistent, then started again.
set -eu
cd "$(dirname "$0")"
# Git Bash on Windows rewrites "/data"-style arguments into Windows paths;
# turn that off (no effect on Linux/macOS).
export MSYS_NO_PATHCONV=1

out="${1:-backups}"
dir="$out/nixflow-$(date +%Y-%m-%d_%H%M%S)"
mkdir -p "$dir"

echo "Stopping Nixflow..."
docker compose stop
# From here on, ALWAYS start Nixflow again — even if the backup fails — so a
# failed backup never leaves the server down.
ok=0
trap 'echo "Starting Nixflow..."; docker compose up -d;
      [ "$ok" = 1 ] || { echo "BACKUP FAILED — $dir is incomplete; Nixflow was restarted." >&2; rm -rf "$dir"; }' EXIT

# With your own PostgreSQL (DB_HOST set by external-db/prepare.sh) the database
# isn't in a Docker volume here — back it up with your own database tooling.
volumes="db-data storage-data"
if grep -qE '^DB_HOST=.+' .env; then
	volumes="storage-data"
	echo "  (own PostgreSQL in use — back up that database separately; saving files + .env here)"
fi

# Stream each volume out as a tarball (no host paths handed to Docker, so this
# works the same on Linux, macOS and Windows).
for v in $volumes; do
	docker run --rm -v "nixflow_$v:/data:ro" alpine tar czf - -C /data . > "$dir/$v.tgz"
	echo "  saved $v"
done
cp .env "$dir/.env"
chmod 600 "$dir/.env"
ok=1

echo "Backup written to $dir (it contains your secrets — store it safely)."
