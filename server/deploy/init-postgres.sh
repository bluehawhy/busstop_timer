#!/bin/sh
# Runs only when the dedicated PostgreSQL volume is initialized for the first time.
set -eu
psql --username "$POSTGRES_USER" --dbname postgres --set ON_ERROR_STOP=1 \
  --set app_password="$BUS_DB_PASSWORD" <<'SQL'
CREATE ROLE bustimer LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'app_password';
CREATE DATABASE bustimer OWNER bustimer;
REVOKE ALL ON DATABASE bustimer FROM PUBLIC;
GRANT CONNECT ON DATABASE bustimer TO bustimer;
SQL
psql --username "$POSTGRES_USER" --dbname bustimer --set ON_ERROR_STOP=1 <<'SQL'
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO bustimer;
SQL
