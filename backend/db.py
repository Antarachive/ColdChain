"""Oracle connection pool and small query helpers (python-oracledb, thin mode - no Oracle Client needed)."""
import os
from contextlib import contextmanager
from datetime import datetime
from decimal import Decimal

import oracledb

_pool = None


def pool():
    global _pool
    if _pool is None:
        _pool = oracledb.create_pool(
            user=os.environ["ORACLE_USER"],
            password=os.environ["ORACLE_PASSWORD"],
            dsn=os.environ["ORACLE_DSN"],
            min=1, max=5, increment=1,
        )
    return _pool


def clean(v):
    """Make Oracle values JSON-friendly: dates -> text, NUMBER(Decimal) -> float."""
    if isinstance(v, datetime):
        return v.strftime("%Y-%m-%d") if (v.hour, v.minute) == (0, 0) else v.strftime("%Y-%m-%d %H:%M")
    if isinstance(v, Decimal):
        return float(v)
    return v


def rows(cur):
    cols = [d[0].lower() for d in cur.description]
    return [dict(zip(cols, map(clean, r))) for r in cur.fetchall()]


def query(sql, **params):
    """Run a SELECT and return a list of dicts (lower-case keys)."""
    with pool().acquire() as conn:
        cur = conn.cursor()
        cur.execute(sql, params)
        return rows(cur)


@contextmanager
def tx():
    """Transaction: yields a cursor, commits on success, rolls back on any error
    (so a rejected trigger/constraint never leaves partial changes)."""
    with pool().acquire() as conn:
        cur = conn.cursor()
        try:
            yield cur
            conn.commit()
        except Exception:
            conn.rollback()
            raise


def next_id(cur, seq):
    cur.execute(f"SELECT {seq}.NEXTVAL FROM dual")
    return int(cur.fetchone()[0])
