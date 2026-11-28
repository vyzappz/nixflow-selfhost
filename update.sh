#!/usr/bin/env sh
# Updates a self-hosted Nixflow to the latest version — safely, in one step.
#
#   ./update.sh               back up, download the new version, restart
#   ./update.sh --no-backup   same, without the backup (not recommended)
#   ./update.sh --auto-on     update automatically every night at 03:00
#   ./update.sh --auto-off    stop automatic updates
#
# Database changes are applied automatically when Nixflow starts. If anything
# fails, your backup is in ./backups — see ./restore.sh.
set -eu
cd "$(dirname "$0")"
export MSYS_NO_PATHCONV=1 # Git Bash on Windows: don't rewrite paths
here="$(pwd)"
mark="# nixflow-auto-update"

# Current/latest version, as reported by the running server itself.
status() { docker compose exec -T api wget -qO- http://localhost:8080/api/status 2>/dev/null || true; }
field() { printf '%s' "$1" | sed -n "s/.*\"$2\":\"\{0,1\}\([^\",}]*\)\"\{0,1\}.*/\1/p"; }

case "${1:-}" in
--auto-on)
	command -v crontab >/dev/null || { echo "crontab isn't available on this machine — schedule ./update.sh --auto yourself."; exit 1; }
	mkdir -p backups
	# (grep finds nothing in an empty crontab — that must not stop the script)
	{ crontab -l 2>/dev/null | grep -v "$mark" || true; echo "0 3 * * * cd '$here' && ./update.sh --auto >> '$here/backups/update.log' 2>&1 $mark"; } | crontab -
	echo "Automatic updates are ON: every night at 03:00 this server checks for a new"
	echo "Nixflow version and, if there is one, backs up and updates. Log: backups/update.log"
	echo "Turn off with: ./update.sh --auto-off"
	exit 0 ;;
--auto-off)
	if command -v crontab >/dev/null; then { crontab -l 2>/dev/null | grep -v "$mark" || true; } | crontab -; fi
	echo "Automatic updates are OFF."
	exit 0 ;;
esac

if grep -qE '^NIXFLOW_VERSION=.+' .env 2>/dev/null; then
	echo "This server is pinned to a version (NIXFLOW_VERSION in .env)."
	echo "Remove that line (or set the version you want) to update."
	exit 1
fi

st="$(status)"
running="$(field "$st" version)"
if [ "${1:-}" = "--auto" ]; then
	# Nightly run: do nothing unless the server knows a newer version exists.
	if [ "$(field "$st" update_available)" != "true" ]; then
		echo "$(date '+%Y-%m-%d %H:%M') up to date (${running:-unknown})"
		exit 0
	fi
	echo "$(date '+%Y-%m-%d %H:%M') updating from ${running:-unknown} to $(field "$st" latest_version)"
fi

if [ "${1:-}" != "--no-backup" ]; then
	echo "1/3  Backing up (database, files, .env)..."
	./backup.sh
else
	echo "1/3  Skipping the backup."
fi

echo "2/3  Downloading the latest Nixflow..."
git pull --ff-only
docker compose pull

echo "3/3  Restarting with the new version..."
docker compose up -d

# Give the server a moment, then report what it's running now.
i=0
while [ $i -lt 30 ]; do
	now="$(field "$(status)" version)"
	[ -n "$now" ] && break
	i=$((i + 1)); sleep 2
done
echo ""
echo "Done. Nixflow ${running:+$running → }${now:-(starting…)} is running."
echo "If something looks wrong, restore the backup with ./restore.sh backups/<folder>."
