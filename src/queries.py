"""Run the named queries in sql/analysis.sql against data/olist.db.

    from queries import run_query
    run_query("monthly_trend")          # -> pandas DataFrame

Run directly to print every query result and save them to reports/sql_results/:
    python src/queries.py
"""
import re
import sqlite3
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "data" / "olist.db"
ANALYSIS_SQL = ROOT / "sql" / "analysis.sql"
RESULTS_DIR = ROOT / "reports" / "sql_results"


def load_queries(path=ANALYSIS_SQL):
    """Split the .sql file on '-- name: <id>' markers into {id: sql}."""
    text = path.read_text(encoding="utf-8")
    parts = re.split(r"^-- name:\s*(\w+)\s*$", text, flags=re.MULTILINE)
    # parts = [header, name1, sql1, name2, sql2, ...]
    return {name: sql.strip() for name, sql in zip(parts[1::2], parts[2::2])}


QUERIES = load_queries()


def connect():
    return sqlite3.connect(DB_PATH)


def run_query(name, conn=None, sql=None):
    """Run one named query from analysis.sql (or the given sql) and return a DataFrame."""
    sql = sql or QUERIES[name]
    if conn is None:
        with connect() as own_conn:
            return pd.read_sql_query(sql, own_conn)
    return pd.read_sql_query(sql, conn)


def main():
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    with connect() as conn:
        for name in QUERIES:
            df = run_query(name, conn)
            df.to_csv(RESULTS_DIR / f"{name}.csv", index=False)
            print(f"\n=== {name} ({len(df)} rows)")
            print(df.head(12).to_string(index=False))


if __name__ == "__main__":
    main()
