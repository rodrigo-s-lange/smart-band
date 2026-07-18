#!/usr/bin/env python3
"""Apply, test and roll back the Smart-Band PostgreSQL migrations."""

from __future__ import annotations

import argparse
import concurrent.futures
import os
import pathlib
import subprocess
import sys
import time


ROOT = pathlib.Path(__file__).resolve().parents[2]
MIGRATIONS = ROOT / "apps" / "edge-api" / "internal" / "postgres" / "migrations"
TESTS = ROOT / "tests" / "database"


class Psql:
    def __init__(self, database_url: str | None, docker_container: str | None) -> None:
        if docker_container:
            self.command = [
                "docker", "exec", "-i", docker_container, "psql",
                "-X", "-A", "-t", "--set", "ON_ERROR_STOP=1",
                "--username", "postgres", "--dbname", "smartband",
            ]
        elif database_url:
            self.command = [
                "psql", "-X", "-A", "-t", "--set", "ON_ERROR_STOP=1",
                "--dbname", database_url,
            ]
        else:
            raise ValueError("provide --database-url or --docker-container")

    def run(self, sql: str, *, check: bool = True) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            self.command,
            input=sql,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if check and result.returncode != 0:
            raise RuntimeError(
                f"psql failed ({result.returncode})\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
            )
        return result


def migration_parts(path: pathlib.Path) -> tuple[str, str]:
    text = path.read_text(encoding="utf-8")
    up_marker = "-- +goose Up"
    down_marker = "-- +goose Down"
    if text.count(up_marker) != 1 or text.count(down_marker) != 1:
        raise ValueError(f"{path}: expected one goose Up and one goose Down marker")
    before_down, down = text.split(down_marker, 1)
    _, up = before_down.split(up_marker, 1)
    if not up.strip() or not down.strip():
        raise ValueError(f"{path}: empty migration section")
    return up, down


def reset(psql: Psql) -> None:
    psql.run("DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;")


def apply_up(psql: Psql, migrations: list[pathlib.Path]) -> None:
    for migration in migrations:
        up, _ = migration_parts(migration)
        psql.run(up)


def apply_down(psql: Psql, migrations: list[pathlib.Path]) -> None:
    for migration in reversed(migrations):
        _, down = migration_parts(migration)
        psql.run(down)


def read_test(name: str) -> str:
    return (TESTS / name).read_text(encoding="utf-8")


def run_concurrency_test(psql: Psql) -> None:
    transaction_ids = (
        "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1",
        "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2",
    )

    def reserve(transaction_id: str) -> subprocess.CompletedProcess[str]:
        return psql.run(
            f"BEGIN; SELECT smartband_reserve_credit('{transaction_id}'); COMMIT;",
            check=False,
        )

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(reserve, transaction_ids))

    successes = sum(result.returncode == 0 for result in results)
    failures = [result for result in results if result.returncode != 0]
    if successes != 1 or len(failures) != 1:
        details = "\n".join(
            f"returncode={result.returncode}\n{result.stderr}" for result in results
        )
        raise RuntimeError(f"expected one reservation success and one rejection\n{details}")
    if "insufficient available balance" not in failures[0].stderr:
        raise RuntimeError(f"unexpected concurrent failure: {failures[0].stderr}")

    psql.run(read_test("concurrency_assertions.sql"))


def run_cancel_dispatch_race(psql: Psql) -> None:
    psql.run("SELECT smartband_reserve_credit('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1');")
    statements = (
        "SELECT smartband_dispatch_actuation('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1', "
        "'ffffffff-ffff-ffff-ffff-fffffffffff1');",
        "SELECT smartband_cancel_before_dispatch('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1');",
    )

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(lambda sql: psql.run(sql, check=False), statements))

    if sum(result.returncode == 0 for result in results) != 1:
        details = "\n".join(
            f"returncode={result.returncode}\n{result.stderr}" for result in results
        )
        raise RuntimeError(f"cancel/dispatch race expected exactly one winner\n{details}")
    psql.run(read_test("cancel_dispatch_assertions.sql"))


def run_restart_test(psql: Psql, docker_container: str) -> None:
    psql.run(read_test("restart_prepare.sql"))
    restart = subprocess.run(
        ["docker", "restart", docker_container],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if restart.returncode != 0:
        raise RuntimeError(f"database restart failed: {restart.stderr}")
    for _ in range(30):
        if psql.run("SELECT 1;", check=False).returncode == 0:
            break
        time.sleep(1)
    else:
        raise RuntimeError("database did not become ready after restart")
    psql.run(read_test("restart_assertions.sql"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database-url", default=os.environ.get("DATABASE_URL"))
    parser.add_argument("--docker-container")
    args = parser.parse_args()

    migrations = sorted(MIGRATIONS.glob("*.sql"))
    if not migrations:
        raise RuntimeError("no migrations found")
    for migration in migrations:
        migration_parts(migration)

    psql = Psql(args.database_url, args.docker_container)

    reset(psql)
    apply_up(psql, migrations)
    psql.run(read_test("fixture.sql"))
    psql.run(read_test("invariants.sql"))

    reset(psql)
    apply_up(psql, migrations)
    psql.run(read_test("fixture.sql"))
    run_concurrency_test(psql)

    reset(psql)
    apply_up(psql, migrations)
    psql.run(read_test("fixture.sql"))
    psql.run(read_test("ambiguous_ack_assertions.sql"))

    reset(psql)
    apply_up(psql, migrations)
    psql.run(read_test("fixture.sql"))
    run_cancel_dispatch_race(psql)

    if args.docker_container:
        reset(psql)
        apply_up(psql, migrations)
        psql.run(read_test("fixture.sql"))
        run_restart_test(psql, args.docker_container)

    apply_down(psql, migrations)
    remaining = psql.run(
        "SELECT count(*) FROM pg_tables WHERE schemaname = 'public';"
    ).stdout.strip()
    if remaining != "0":
        raise RuntimeError(f"rollback left {remaining} public tables")

    checks = "invariants, concurrency, ambiguous ack, cancel/dispatch race and rollback"
    if args.docker_container:
        checks += ", including database restart"
    print(f"database validation passed: {len(migrations)} migrations; {checks}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # concise CI failure with the underlying database error
        print(f"database validation failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
