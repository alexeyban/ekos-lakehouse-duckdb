#!/usr/bin/env python3
"""Step 8 from the command line: one question to Superset's Ask (the EKOS fork), as the page sends
it. Prints the answer's status, the SQL, the rows, and the EKOS calls behind it, so the run log
holds exactly what the page would show.

    scripts/ask.py "Revenue by product category per month this year"
    scripts/ask.py --dashboard "..."      (the page's "Build a dashboard")

Signs in as the demo analyst (scripts/superset-init.sh); everything is on 127.0.0.1.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import http.cookiejar
import urllib.error
import urllib.request

BASE = os.environ.get("SUPERSET_URL", "http://127.0.0.1:18098")
USER = os.environ.get("DEMO_SUPERSET_USER", "maria")
PASSWORD = os.environ.get("DEMO_SUPERSET_PASSWORD", "maria-local-only")
# Superset checks a CSRF token on every POST, bound to the session cookie: keep the cookie.
OPENER = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))


def call(path: str, body: dict | None = None, token: str | None = None, csrf: str | None = None,
         timeout: int = 900) -> dict:
    req = urllib.request.Request(
        BASE + path,
        data=None if body is None else json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Referer": BASE,
                 **({"Authorization": f"Bearer {token}"} if token else {}),
                 **({"X-CSRFToken": csrf} if csrf else {})},
        method="GET" if body is None else "POST",
    )
    try:
        with OPENER.open(req, timeout=timeout) as resp:  # noqa: S310 - a fixed local URL
            return json.load(resp)
    except urllib.error.HTTPError as err:
        sys.exit(f"{path}: HTTP {err.code}: {err.read().decode(errors='replace')[:1000]}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("question")
    ap.add_argument("--dashboard", action="store_true")
    args = ap.parse_args()
    token = call("/api/v1/security/login",
                 {"username": USER, "password": PASSWORD, "provider": "db", "refresh": False})["access_token"]
    csrf = call("/api/v1/security/csrf_token/", token=token)["result"]
    endpoint = "dashboard" if args.dashboard else "sql"
    result = call(f"/api/v1/ekos_ai/{endpoint}", {"question": args.question}, token, csrf)["result"]
    print(f"question: {args.question}")
    print(f"status:   {result.get('status')}")
    for key in ("explanation", "refusal", "reason"):
        if result.get(key):
            print(f"{key}: {result[key]}")
    if result.get("sql"):
        print("\nSQL:\n" + result["sql"])
    rows = result.get("rows") or result.get("data") or []
    if rows:
        print(f"\nrows ({len(rows)}):")
        for r in rows:
            print("  " + json.dumps(r, default=str))
    rest = {k: v for k, v in result.items()
            if k not in {"sql", "rows", "data", "ekos_log", "status", "explanation"}}
    if rest:
        print("\nother fields: " + json.dumps(rest, default=str)[:3000])
    log = result.get("ekos_log") or []
    print(f"\nEKOS calls ({len(log)}):")
    for entry in log:
        print("  " + json.dumps(entry, default=str)[:300])
    return 0 if result.get("status") not in (None, "failed") else 1


if __name__ == "__main__":
    sys.exit(main())
