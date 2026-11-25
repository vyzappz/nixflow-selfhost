# Nixflow — self-hosted

Run Nixflow on your own server, free. Same app as Nixflow Cloud, without
billing or plan limits: unlimited workflows, runs and users.

## What you need

- A Linux server (or a PC with Docker Desktop): 2 CPU, 4 GB RAM, 20 GB disk
- Docker with Docker Compose v2 (`docker compose version`)
- `openssl` (for `setup.sh`)

## Install

```sh
git clone https://github.com/vyzappz/nixflow-selfhost.git && cd nixflow-selfhost
./setup.sh                 # writes .env with fresh secrets
docker compose up -d       # downloads the images and starts Nixflow
```

Open **http://localhost:8080** and sign up. The first account creates your
workspace. The admin portal (team, roles, your AI key) is at
**http://localhost:8081**.

On a server with a domain, pass your addresses to `setup.sh`:

```sh
./setup.sh https://nixflow.example.com https://nixflow-admin.example.com
```

and put a reverse proxy with HTTPS (Caddy, nginx, Traefik…) in front of ports
8080 (app) and 8081 (admin portal).

## What runs

| Service   | What it does                                              |
|-----------|-----------------------------------------------------------|
| `web`     | Serves the app and admin portal; routes the APIs below    |
| `api`     | Nixflow API and workflow engine (schedules, runs)         |
| `migrate` | Sets up / upgrades the database, then exits               |
| `db`      | Postgres (data lives in the `db-data` volume)             |
| `auth`    | Sign-in                                                   |
| `rest`    | Database API used by the app                              |
| `storage` | Uploaded files (`storage-data` volume)                    |

## Upgrade

```sh
git pull                 # latest install files
docker compose pull      # latest images
docker compose up -d
```

New database migrations apply automatically on start. To stay on a version
until you choose to move, set `NIXFLOW_VERSION=1.0.0` (for example) in `.env`.

## Back up and restore

```sh
./backup.sh                                      # → backups/nixflow-<date>/
./restore.sh backups/nixflow-2026-01-31_020000   # replaces ALL current data
```

A backup holds the database, uploaded files and `.env`. Nixflow pauses for the
few seconds the copy takes. Backups contain your secrets — store them safely,
off the server. For nightly backups, add to `crontab -e`:

```
0 2 * * * cd /path/to/nixflow/selfhost && ./backup.sh >> backups/backup.log 2>&1
```

Keep `.env` safe: losing `ENCRYPTION_KEY` makes saved connection credentials
unreadable.

## Options

All settings are in `.env`; `.env.example` explains each one. Common ones:

- **Invite-only:** after creating your account, set `DISABLE_SIGNUP=true`.
- **Email confirmation / password reset:** fill in `SMTP_*` and set
  `EMAIL_AUTOCONFIRM=false`. Without a mail server, new accounts are confirmed
  immediately.
- **Invitation emails:** set `RESEND_API_KEY` and `EMAIL_FROM`.
- **AI:** each workspace adds its own AI provider key in the admin portal.

Apply changes with `docker compose up -d`.

## Use your own PostgreSQL

By default Nixflow runs its own database container. To use a PostgreSQL you
already run instead (your server, AWS RDS, Azure, Google Cloud SQL…):

**You need:** PostgreSQL **15 or newer** with the **pgvector** extension
available, an **admin** login (superuser, `rds_superuser`, `azure_pg_admin` or
a Cloud SQL admin), and an **empty** database for Nixflow
(`CREATE DATABASE nixflow;`).

```sh
./setup.sh                                   # if you haven't yet
./external-db/prepare.sh 'postgresql://ADMIN:PASSWORD@HOST:5432/nixflow?sslmode=require'
docker compose up -d
```

`prepare.sh` runs `external-db/init.sql` once with your admin login: it creates
the roles and schemas Nixflow needs and enables the extensions. **Your admin
password is used only for that and is not saved.** From then on Nixflow logs in
with its own roles (password = `POSTGRES_PASSWORD` in `.env`) and creates its
tables on start, as usual.

- **SSL:** add `?sslmode=require` (or `verify-full`) for cloud databases; leave
  it off for a server without SSL.
- **Postgres on the same machine:** use `localhost` in the URL — it's
  translated so the containers can reach it.
- **Backups:** `./backup.sh` then saves uploaded files and `.env` only — back up
  the database with your own tooling (e.g. your provider's snapshots).
- **New installs only:** this starts Nixflow on an empty database. Moving an
  existing install's data from the built-in database isn't automated yet.

## Privacy

Your users, workflows, runs and files never leave your server. What a
self-hosted server sends to Nixflow — and how to stop it:

| What | When | Contains | Turn off |
|---|---|---|---|
| **Update check** | once a day | a random install ID + your Nixflow version | `UPDATE_CHECK=false` in `.env` |
| **Registration** | only if an admin clicks **Register** on the dashboard and ticks consent | your company name + the install ID (registration date is recorded) | just don't register (the card can be dismissed) |

Nothing else: no usage tracking, no sign-up or support notifications. Other
outside connections happen only when you use them (AI providers, apps your
workflows call). Even the fonts are served by your own server.
