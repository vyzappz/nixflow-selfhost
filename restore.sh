#!/usr/bin/env sh
# Restores a backup made by backup.sh. REPLACES all current Nixflow data.
#   ./restore.sh backups/nixflow-2026-01-31_020000
set -eu
cd "$(dirname "$0")"
# Git Bash on Windows rewrites "/data"-style arguments into Windows paths;
# turn that off (no effect on Linux/macOS).
export MSYS_NO_PATHCONV=1

dir="${1:?usage: ./restore.sh <backup folder>}"
# A backup made with your own PostgreSQL has no db-data (that database is
# restored with your own tooling) — restore whatever volumes the backup holds.
volumes=""
for v in db-data storage-data; do [ -f "$dir/$v.tgz" ] && volumes="$volumes $v"; done
[ -f "$dir/.env" ] && [ -f "$dir/storage-data.tgz" ] || { echo "Not a Nixflow backup: $dir needs .env and storage-data.tgz"; exit 1; }
case "$volumes" in *db-data*) ;; *) echo "Note: no database in this backup (own PostgreSQL) — restore that database separately." ;; esac

printf "This replaces ALL current Nixflow data with %s. Type 'restore' to continue: " "$dir"
read -r answer
[ "$answer" = "restore" ] || { echo "Cancelled."; exit 1; }

docker compose down
ok=0
trap '[ "$ok" = 1 ] || echo "RESTORE FAILED part-way — Nixflow is stopped. Fix the problem and run ./restore.sh again with the same backup." >&2' EXIT
cp "$dir/.env" .env # the data only opens with the secrets it was made with
for v in $volumes; do
	docker volume rm "nixflow_$v" >/dev/null 2>&1 || true
	# Labelled like Compose's own, so `docker compose` adopts the volume.
	docker volume create \
		--label com.docker.compose.project=nixflow \
		--label com.docker.compose.volume="$v" \
		"nixflow_$v" >/dev/null
	docker run --rm -i -v "nixflow_$v:/data" alpine tar xzf - -C /data < "$dir/$v.tgz"
	echo "  restored $v"
done
docker compose up -d
ok=1
echo "Restored from $dir."
