# Nixflow — self-hosted

Run Nixflow on your own server, free — including for your business. The free
**Community** edition is the same app as Nixflow Cloud for a small team; a
**Business** license lifts the limits and unlocks the rest (see
[Community and Business](#community-and-business)).

## Community and Business

| | Community (free) | Business (license key) |
|---|---|---|
| Tracks switched on at once | 10 | Unlimited |
| Runs per month | 5,000 | Unlimited |
| Users | 5 | Unlimited |
| Workspaces (companies) | 1 | Unlimited |
| Run history | last 7 days | Unlimited |
| Environments | Dev | Dev, Test, Prod + Deployments |
| Roles | Admin, Editor | + Viewer, per-feature permissions |
| Version history, Reports, Activity logs | — | ✓ |
| Enterprise apps (SAP, NetSuite, Coupa, Workday, ServiceNow, Jira, Salesforce) | — | ✓ |
| AI Consultant, Knowledge bases, custom Job History columns | — | ✓ |
| External User Portal, no "Powered by Nixflow" | — | ✓ |
| Support | Community forum | Email support |

Everything else — every other app and step, AI Agent and Assistant with your
own key, webhooks, schedules, the database and file manager — is in Community.

- **Register once.** On first sign-in an admin registers the server with the
  company name (only the name is sent, with the install ID and version). No
  internet? It registers locally and sends the name later.
- **Upgrading never breaks a server.** Tracks that were already switched on
  before the limits existed keep running; only new ones count.
- **Business license:** email support@nixflow.cloud. You get a key; an admin
  pastes it in the admin portal → **License**. The key is checked on your
  server itself, so it works offline.

Changing or bypassing the license check isn't allowed by Nixflow's license
(Elastic License 2.0).

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

Then open Nixflow and sign up — the first account creates your workspace. The
admin portal is where you manage your team, roles and AI key. **Which address
to open depends on where you installed it:**

| Installed on | Run setup with | Open the app at | Admin portal |
|---|---|---|---|
| **Your own computer** | `./setup.sh` | http://localhost:8080 | http://localhost:8081 |
| **A server, no domain** | `./setup.sh http://SERVER-IP:8080 http://SERVER-IP:8081` | http://SERVER-IP:8080 | http://SERVER-IP:8081 |
| **A server with a domain** | `./setup.sh https://nixflow.example.com https://nixflow-admin.example.com` | your app domain | your admin domain |

Replace `SERVER-IP` with your server's public IP (e.g. `203.0.113.10`), and
open ports 8080 and 8081 in its firewall. `localhost` only works on the machine
Nixflow runs on — from another computer, use the server's IP or domain.

**With a domain**, put a reverse proxy with HTTPS (Caddy, nginx, Traefik…) in
front of port 8080 (app) and 8081 (admin portal). Use this for anything beyond
testing: without HTTPS, passwords travel unencrypted.

**Already ran `./setup.sh` with the wrong address?** It won't overwrite your
`.env` (it holds your secrets). Edit `PUBLIC_URL` and `ADMIN_URL` in `.env`
instead, then run `docker compose up -d` (everyone signs in again).

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

## Update

When a new version is out, admins see a banner in Nixflow saying what's new.
To update, run this in the Nixflow folder:

```sh
./update.sh              # backs up, downloads the new version, restarts
```

It takes a backup first (`./backup.sh`), then updates and restarts. Database
changes apply automatically on start. If anything goes wrong, restore the
backup with `./restore.sh backups/<folder>`.

**Automatic updates (optional):**

```sh
./update.sh --auto-on    # every night at 03:00: if there's a new version, back up and update
./update.sh --auto-off   # turn it off again
```

The nightly check does nothing when you're already up to date. Its log is
`backups/update.log`. To stay on a version until you choose to move, set
`NIXFLOW_VERSION=1.0.0` (for example) in `.env` — updates then stop until
you change it.

Nixflow never updates your server by itself: updates happen only when you run
`./update.sh` or turn on automatic updates.

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
