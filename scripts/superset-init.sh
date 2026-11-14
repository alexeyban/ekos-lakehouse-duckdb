#!/bin/bash
# Superset's first start: metadata database, the admin user, roles, and the `marts` connection to
# the published DuckDB file — opened read-only, external access off and the configuration locked
# (EKOS_AI.md, "DuckDB gold marts"), so no query can read files or change a setting.
set -euo pipefail
c=ekos-duckdemo-superset-1
until docker exec "$c" curl -sf http://127.0.0.1:18098/health >/dev/null 2>&1; do sleep 3; done
docker exec "$c" superset db upgrade >/dev/null
docker exec "$c" superset fab create-admin --username maria --firstname Maria --lastname Analyst \
  --email maria@example.invalid --password "${SUPERSET_ADMIN_PASSWORD:-maria-local-only}" >/dev/null 2>&1 || true
docker exec "$c" superset init >/dev/null
docker exec -i "$c" python - <<'EOF'
import json
from superset.app import create_app
app = create_app()
with app.app_context():
    from superset import db
    from superset.models.core import Database
    extra = {"engine_params": {"connect_args": {"read_only": True, "config": {
        "enable_external_access": False, "lock_configuration": True}}}}
    d = db.session.query(Database).filter_by(database_name="marts").one_or_none()
    if d is None:
        d = Database(database_name="marts")
        db.session.add(d)
    d.sqlalchemy_uri = "duckdb:////marts/marts.duckdb"
    d.extra = json.dumps(extra)
    d.expose_in_sqllab = True
    d.allow_run_async = False
    db.session.commit()
    print("superset: connection marts →", d.sqlalchemy_uri, "(read-only, external access off, configuration locked)")
EOF
