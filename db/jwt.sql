-- Runs once, when the database is first created. (Matches Supabase's own
-- self-hosted setup: only the token lifetime is stored, never the secret.)
\set jwt_exp `echo "$JWT_EXP"`

ALTER DATABASE postgres SET "app.settings.jwt_exp" TO :'jwt_exp';
