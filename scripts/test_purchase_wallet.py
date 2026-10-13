#!/usr/bin/env python3
"""Run wallet SQL tests in a disposable, loopback-only PostgreSQL cluster.

Requires local PostgreSQL binaries; never reads a Supabase project or DATABASE_URL.
The minimal auth fixture exercises wallet SQL, not the live Supabase Auth service.
"""
from datetime import datetime
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
    evidence = ROOT / "build" / "purchase-wallet-tests" / datetime.now().strftime("%Y%m%d-%H%M%S")
    evidence.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="bilu-wallet-") as temporary:
        directory = Path(temporary)
        cluster = directory / "data"
        with socket.socket() as candidate:
            candidate.bind(("127.0.0.1", 0))
            port = candidate.getsockname()[1]
        started = False

        def run(name, args, input_text=None):
            completed = subprocess.run(args, input=input_text, text=True, capture_output=True)
            (evidence / f"{name}.log").write_text(completed.stdout + completed.stderr)
            if completed.returncode:
                raise RuntimeError(f"{name} failed; inspect {evidence / (name + '.log')}")

        try:
            run("init", [binaries["initdb"], "-D", str(cluster), "-A", "trust", "-U", "bilu_wallet_test"])
            run("start", [binaries["pg_ctl"], "-D", str(cluster), "-l", str(evidence / "postgres.log"),
                          "-o", f"-h 127.0.0.1 -p {port} -k {directory}", "-w", "start"])
            started = True
            psql = [binaries["psql"], "-X", "-v", "ON_ERROR_STOP=1", "-h", "127.0.0.1", "-p", str(port),
                    "-U", "bilu_wallet_test", "-d", "postgres"]
            run("bootstrap", psql, """
                CREATE ROLE anon;
                CREATE ROLE authenticated;
                CREATE ROLE service_role BYPASSRLS;
                CREATE SCHEMA auth;
                CREATE TABLE auth.users (id uuid PRIMARY KEY, is_anonymous boolean NOT NULL DEFAULT false);
            """)
            run("migration", psql + ["-f", str(ROOT / "supabase/migrations/20261009000000_purchase_wallet.sql")])
            for name in ("purchase_wallet", "purchase_wallet_concurrency", "purchase_deleted_notifications"):
                run(name, psql + ["-f", str(ROOT / f"supabase/tests/{name}.sql")])
                print(f"PASS {name}")
        finally:
            if started:
                run("stop", [binaries["pg_ctl"], "-D", str(cluster), "-m", "fast", "-w", "stop"])
    print(f"Local SQL evidence: {evidence}")


if __name__ == "__main__":
    main()
