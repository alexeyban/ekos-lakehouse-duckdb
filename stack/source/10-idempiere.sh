#!/bin/bash
# First start of the source container: restore the iDempiere 12 seed (GardenWorld) and create the
# read-only role EKOS and Trino use. Runs once, from docker-entrypoint-initdb.d, on an empty volume.
set -euo pipefail
ro_password="${EKOS_SOURCE_PASSWORD:?EKOS_SOURCE_PASSWORD is not set}"

psql -v ON_ERROR_STOP=1 -U postgres -c "CREATE ROLE adempiere LOGIN" -c "CREATE DATABASE idempiere OWNER adempiere"
pg_restore -U postgres -d idempiere --no-owner --role=adempiere /seed/idempiere.dump
# This year and last year of synthetic business on top of the seed (2002–2003 only).
psql -v ON_ERROR_STOP=1 -U postgres -d idempiere -q -f /synthetic/20-synthetic.sql

psql -v ON_ERROR_STOP=1 -U postgres -d idempiere \
  -c "CREATE ROLE ekos_ro LOGIN PASSWORD '${ro_password}'" \
  -c "GRANT CONNECT ON DATABASE idempiere TO ekos_ro" \
  -c "GRANT USAGE ON SCHEMA adempiere TO ekos_ro" \
  -c "GRANT SELECT ON ALL TABLES IN SCHEMA adempiere TO ekos_ro" \
  -c "ALTER DEFAULT PRIVILEGES IN SCHEMA adempiere GRANT SELECT ON TABLES TO ekos_ro" \
  -c "GRANT pg_read_all_stats TO ekos_ro" \
  -c "ALTER ROLE ekos_ro SET default_transaction_read_only = on" \
  -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements"
echo "idempiere restored: $(psql -U postgres -d idempiere -Atc "SELECT count(*) FROM pg_tables WHERE schemaname = 'adempiere'") tables"
