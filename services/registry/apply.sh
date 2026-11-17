#!/usr/bin/env bash
# Apply registry migrations in order. Safe to re-run.
set -euo pipefail

cd "$(dirname "$0")"

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "Set DATABASE_URL to a PostgreSQL connection string." >&2
  exit 1
fi

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -c "CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now());"

for file in migrations/*.sql; do
  version="$(basename "$file")"
  # shellcheck disable=SC2016
  existing="$(psql "$DATABASE_URL" -tAc "SELECT 1 FROM schema_migrations WHERE version = '${version}'")"
  if [[ "${existing}" == "1" ]]; then
    echo "skip ${version}"
    continue
  fi
  echo "apply ${version}"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 --single-transaction -f "$file"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
    -c "INSERT INTO schema_migrations (version) VALUES ('${version}')"
done

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f verify.sql
echo "registry schema ok"
