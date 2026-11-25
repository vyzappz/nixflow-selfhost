-- ============================================================================
-- Prepare YOUR OWN PostgreSQL for Nixflow (instead of the built-in database).
--
-- Run ONCE, as an admin (superuser, or rds_superuser / azure_pg_admin / a
-- Cloud SQL admin), connected to the EMPTY database Nixflow will use.
-- Easiest: ./external-db/prepare.sh (it passes the password for you).
--
-- Requires PostgreSQL 15+ with the pgvector extension available.
-- Safe to run again: every step is "create if missing".
--
-- It creates the login roles the Nixflow services use — all with the password
-- from POSTGRES_PASSWORD in .env (passed in as :pgpass):
--   authenticator           database REST API
--   supabase_auth_admin     sign-in service (owns schema "auth")
--   supabase_storage_admin  file storage service (owns schema "storage")
--   nixflow_migrator        applies Nixflow's tables (owns schema "public" objects)
-- and the API roles anon / authenticated / service_role (no login).
-- After this, Nixflow never needs your admin password.
-- ============================================================================
\set ON_ERROR_STOP on

\if :{?pgpass}
\else
  \echo 'Run with -v pgpass=<POSTGRES_PASSWORD from .env> (or use ./external-db/prepare.sh)'
  \quit
\endif

-- ── Extensions (in their own schema, like Supabase) ─────────────────────────
create schema if not exists extensions;
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pgcrypto     with schema extensions;
create extension if not exists vector       with schema extensions;

-- ── API roles (no login; PostgREST switches into them per request) ──────────
select 'create role anon nologin noinherit'
  where not exists (select from pg_roles where rolname = 'anon') \gexec
select 'create role authenticated nologin noinherit'
  where not exists (select from pg_roles where rolname = 'authenticated') \gexec
select 'create role service_role nologin noinherit bypassrls'
  where not exists (select from pg_roles where rolname = 'service_role') \gexec

-- ── Service login roles ──────────────────────────────────────────────────────
select 'create role authenticator login noinherit'
  where not exists (select from pg_roles where rolname = 'authenticator') \gexec
select 'create role supabase_auth_admin login noinherit createrole'
  where not exists (select from pg_roles where rolname = 'supabase_auth_admin') \gexec
select 'create role supabase_storage_admin login noinherit createrole'
  where not exists (select from pg_roles where rolname = 'supabase_storage_admin') \gexec
select 'create role nixflow_migrator login inherit'
  where not exists (select from pg_roles where rolname = 'nixflow_migrator') \gexec

alter role authenticator          with login password :'pgpass';
alter role supabase_auth_admin    with login password :'pgpass';
alter role supabase_storage_admin with login password :'pgpass';
alter role nixflow_migrator       with login password :'pgpass';

-- PostgREST logs in as authenticator and becomes anon/authenticated/service_role.
grant anon, authenticated, service_role to authenticator;
-- Storage acts as these roles too when it checks access.
grant anon, authenticated, service_role to supabase_storage_admin;
-- The migrator adds triggers/foreign keys on auth.users and policies/rows on
-- storage tables, so it works through the owners of those schemas.
grant supabase_auth_admin, supabase_storage_admin to nixflow_migrator;

-- ── Database-level rights ────────────────────────────────────────────────────
select format('grant connect, create on database %I to supabase_auth_admin, supabase_storage_admin, nixflow_migrator', current_database()) \gexec
select format('grant connect on database %I to authenticator', current_database()) \gexec
-- Resolve extension types/functions (uuid_generate_v4, vector…) without a prefix.
select format('alter database %I set search_path to "$user", public, extensions', current_database()) \gexec

-- ── Schemas ──────────────────────────────────────────────────────────────────
create schema if not exists auth    authorization supabase_auth_admin;
create schema if not exists storage authorization supabase_storage_admin;
alter role supabase_auth_admin    set search_path = auth;
alter role supabase_storage_admin set search_path = storage, public, extensions;

grant usage on schema auth, storage, extensions to anon, authenticated, service_role, nixflow_migrator;
grant usage, create on schema public to nixflow_migrator;
grant usage on schema public to anon, authenticated, service_role, supabase_storage_admin;

-- Tables/functions/sequences Nixflow creates are usable by the API roles —
-- row-level security policies then decide what each user may see.
alter default privileges for role nixflow_migrator in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges for role nixflow_migrator in schema public
  grant all on functions to anon, authenticated, service_role;
alter default privileges for role nixflow_migrator in schema public
  grant all on sequences to anon, authenticated, service_role;

-- Short timeouts for browser-facing roles, like Supabase.
alter role anon          set statement_timeout = '3s';
alter role authenticated set statement_timeout = '8s';

\echo 'Done: this database is ready for Nixflow.'
