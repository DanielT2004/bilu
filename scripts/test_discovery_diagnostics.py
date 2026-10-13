#!/usr/bin/env python3
"""Check diagnostics SQL in disposable local PostgreSQL; never connects to Supabase.

Cron registration is stubbed because Homebrew PostgreSQL does not ship pg_cron.
"""
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    binaries = {name: shutil.which(name) for name in ("initdb", "pg_ctl", "psql")}
    if not all(binaries.values()):
        raise SystemExit("Install local PostgreSQL (initdb, pg_ctl, psql) first.")
    with tempfile.TemporaryDirectory(prefix="bilu-diagnostics-") as temporary:
        directory = Path(temporary)
        cluster = directory / "data"
        with socket.socket() as candidate:
            candidate.bind(("127.0.0.1", 0))
            port = candidate.getsockname()[1]

        def run(arguments, body=None):
            result = subprocess.run(arguments, input=body, text=True, capture_output=True)
            if result.returncode:
                raise RuntimeError(result.stdout + result.stderr)

        run([binaries["initdb"], "-D", str(cluster), "-A", "trust", "-U", "bilu_diagnostics_test"])
        run([binaries["pg_ctl"], "-D", str(cluster), "-l", str(directory / "postgres.log"),
             "-o", f"-h 127.0.0.1 -p {port} -k {directory}", "-w", "start"])
        try:
            psql = [binaries["psql"], "-X", "-v", "ON_ERROR_STOP=1", "-h", "127.0.0.1",
                    "-p", str(port), "-U", "bilu_diagnostics_test", "-d", "postgres"]
            run(psql, """
                create role anon;
                create role authenticated;
                create role service_role bypassrls;
                create schema auth;
                create table auth.users (id uuid primary key);
                create schema cron;
                create table cron.job (jobid bigint, jobname text);
                create function cron.unschedule(bigint) returns boolean language sql as 'select true';
                create function cron.schedule(text, text, text) returns bigint language sql as 'select 1::bigint';
            """)
            run(psql + ["-f", str(ROOT / "supabase/migrations/20261009010000_discovery_ad_diagnostics.sql")])
            run(psql + ["-f", str(ROOT / "supabase/tests/discovery_diagnostics.sql")])
            print("PASS discovery diagnostics: ingestion, idempotency, caps, aggregates, precision, privileges")
        finally:
            run([binaries["pg_ctl"], "-D", str(cluster), "-m", "fast", "-w", "stop"])


if __name__ == "__main__":
    main()
