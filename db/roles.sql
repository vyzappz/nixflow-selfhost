-- Runs once, when the database is first created. Gives the built-in service
-- roles of the Supabase Postgres image the password from POSTGRES_PASSWORD.
\set pgpass `echo "$POSTGRES_PASSWORD"`

ALTER USER authenticator           WITH PASSWORD :'pgpass';
ALTER USER pgbouncer               WITH PASSWORD :'pgpass';
ALTER USER supabase_auth_admin     WITH PASSWORD :'pgpass';
ALTER USER supabase_storage_admin  WITH PASSWORD :'pgpass';
-- (No supabase_functions_admin: that role comes with Supabase Edge Functions,
-- which Nixflow doesn't use, so the image here never creates it.)
