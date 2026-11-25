#!/usr/bin/env sh
# Switch this Nixflow install to YOUR OWN PostgreSQL (15+, with pgvector).
#
#   ./setup.sh                                   # first, if you haven't
#   ./external-db/prepare.sh 'postgresql://ADMIN:PASSWORD@HOST:5432/nixflow?sslmode=require'
#   docker compose up -d
#
# The URL is an ADMIN login for an EMPTY database (create it first, e.g.
# `CREATE DATABASE nixflow;`). It is used once, here, to create the roles and
# schemas Nixflow needs (external-db/init.sql) — it is NOT saved anywhere.
# Afterwards Nixflow logs in with its own roles, using POSTGRES_PASSWORD.
#
# Postgres on this same machine? Use host "localhost" — it's translated to
# host.docker.internal for the containers.
set -eu
export MSYS_NO_PATHCONV=1 # Git Bash on Windows: don't rewrite paths
cd "$(dirname "$0")/.."

url="${1:?usage: ./external-db/prepare.sh 'postgresql://ADMIN:PASSWORD@HOST:PORT/DATABASE[?sslmode=require]'}"
[ -f .env ] || { echo "No .env yet — run ./setup.sh first."; exit 1; }
pgpass=$(grep '^POSTGRES_PASSWORD=' .env | cut -d= -f2-)
[ -n "$pgpass" ] || { echo "POSTGRES_PASSWORD missing in .env"; exit 1; }

# Parse postgresql://user:pass@host:port/db?params (no password echoing).
rest=${url#*://}
case "$rest" in *@*) hostpart=${rest#*@} ;; *) hostpart=$rest ;; esac
hostport=${hostpart%%/*}
dbq=${hostpart#*/}; [ "$dbq" = "$hostpart" ] && dbq=postgres
db=${dbq%%\?*}
query=""; case "$dbq" in *\?*) query=${dbq#*\?} ;; esac
host=${hostport%%:*}
port=5432; case "$hostport" in *:*) port=${hostport##*:} ;; esac
sslmode=$(printf '%s' "$query" | tr '&' '\n' | grep '^sslmode=' | cut -d= -f2 || true)
# Every Nixflow service must agree on SSL. The storage service treats any value
# but "disable" as SSL-required, so the in-between modes are not usable.
case "$sslmode" in
	"") sslmode=disable ;;
	disable|require|verify-ca|verify-full) ;;
	prefer|allow) echo "Note: sslmode=$sslmode isn't supported by all services — using 'disable'. Use sslmode=require if your server needs SSL."; sslmode=disable ;;
	*) echo "Unknown sslmode '$sslmode' — use disable, require, verify-ca or verify-full."; exit 1 ;;
esac

# Containers can't reach "localhost" on the host — use the Docker host alias.
case "$host" in localhost|127.0.0.1|::1) chost=host.docker.internal ;; *) chost=$host ;; esac
conn_url=$(printf '%s' "$url" | sed "s#@$host:#@$chost:#; s#@$host/#@$chost/#")

echo "Preparing database '$db' on $host:$port (sslmode=$sslmode)..."
docker run --rm -i --add-host=host.docker.internal:host-gateway postgres:17-alpine \
	psql "$conn_url" -v pgpass="$pgpass" -f - < external-db/init.sql

# Point the install at it (replace any previous values).
tmp=$(mktemp)
grep -vE '^(COMPOSE_PATH_SEPARATOR|COMPOSE_FILE|DB_HOST|DB_PORT|DB_NAME|DB_SSLMODE)=' .env > "$tmp" || true
cat >> "$tmp" <<EOF

# Own PostgreSQL (written by external-db/prepare.sh)
COMPOSE_PATH_SEPARATOR=:
COMPOSE_FILE=docker-compose.yml:docker-compose.external-db.yml
DB_HOST=$chost
DB_PORT=$port
DB_NAME=$db
DB_SSLMODE=$sslmode
EOF
cat "$tmp" > .env; rm -f "$tmp"; chmod 600 .env

echo "Done. .env now uses your PostgreSQL. Next: docker compose up -d"
