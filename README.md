# Cold Storage Commodity & Chamber Management System

Python (Flask) + Oracle Database + a browser frontend. All business rules are enforced **inside Oracle**
(constraints and triggers); the API only authenticates users, checks roles and runs parameterised SQL.

```
cold-storage/
├── sql/
│   ├── 00_create_user.sql   run once as SYSTEM: creates the COLDSTORAGE schema owner
│   ├── 00_drop_all.sql      optional reset: drops every table/view/sequence
│   ├── 01_schema.sql        9 tables, constraints, indexes, sequences, 3 triggers
│   ├── 02_seed_data.sql     sample data (users, lots, allocations, readings, invoices)
│   ├── 03_views.sql         the 7 report views
│   └── 04_rule_tests.sql    breaks each business rule on purpose (evidence for the test table)
├── backend/
│   ├── app.py               Flask REST API + serves the frontend
│   ├── db.py                python-oracledb pool and helpers
│   └── hash_password.py     makes a password hash for new SystemUser rows
├── frontend/index.html      single-page UI (login, intake, allocation, monitoring, billing, release, reports)
├── requirements.txt
└── .env.example
```

## 1. Database (Oracle 19c / 21c / 23ai)

No Oracle yet? Run the free edition in Docker:

```bash
docker run -d --name oracle-free -p 1521:1521 -e ORACLE_PASSWORD=oracle gvenzl/oracle-free:slim
# wait ~1-2 minutes until the log says "DATABASE IS READY TO USE!"
```

Create the schema owner, then load the scripts **as that user** (SQL*Plus, SQLcl or SQL Developer):

```bash
sqlplus system/oracle@localhost:1521/FREEPDB1 @sql/00_create_user.sql

sqlplus 'coldstorage/"ColdStorage#2026"@localhost:1521/FREEPDB1'
SQL> @sql/01_schema.sql
SQL> @sql/02_seed_data.sql
SQL> @sql/03_views.sql
SQL> @sql/04_rule_tests.sql      -- optional: every line should say "rejected"
```

(`FREEPDB1` is the service name for Oracle Free; use `XEPDB1` for Express Edition, or your own PDB service.)

## 2. Backend

```bash
python -m venv .venv
source .venv/bin/activate            # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env                 # then edit ORACLE_* and SECRET_KEY
python backend/app.py
```

Open **http://localhost:5000**. `python-oracledb` runs in thin mode, so no Oracle Client install is needed.

### Demo logins

| Username | Password | Role | Can use |
|---|---|---|---|
| `admin_user` | `admin123` | Admin | everything, including releases |
| `op_user1` | `op123` | WarehouseOperator | intake, allocation, temperature, inspection |
| `bill_user1` | `bill123` | BillingClerk | billing, payments, reports |
| `greenfields` | `cust123` | Customer | read-only stock, ageing and bills for GreenFields only |

New users: `python backend/hash_password.py <password>` and insert the hash into `SystemUser.PasswordHash`.

## 3. How the rules are enforced

| Business rule | Where | Message on violation |
|---|---|---|
| Allocation within capacity | `trg_allocation_limits` (compound trigger) | `Allocation of … exceeds lot balance / chamber capacity …` |
| Release within stored balance | `trg_release` + `chk_alloc_released` | `Release of … exceeds allocated quantity …` |
| Release after receipt | `trg_release` | `Release date must be on/after the lot receipt date …` |
| Valid temperature range | `chk_temp_range` (-60..60 °C); deviations vs. commodity range flagged by `vw_temperature_deviation` | `Temperature must be between -60 and 60 °C` |
| Payment limit | `chk_inv_paid` | `Payment would exceed the invoice total` |
| Derived values | `Lot.CurrentBalanceQty` (trigger), `Invoice.Status` (trigger), `Invoice.TotalAmount` (virtual column) | n/a |

## 4. REST API

| Method & path | Roles | Purpose |
|---|---|---|
| `POST /api/login`, `POST /api/logout`, `GET /api/me` | any | session login (PBKDF2 hashes, signed cookie) |
| `GET /api/data` | staff | lookup lists and current records for the screens |
| `GET /api/reports/<occ\|age\|dev\|stock\|rel\|bill\|rev>` | any (customers: age, stock, bill, own rows only) | rows from the `vw_*` views |
| `POST /api/lots` | Admin, WarehouseOperator | register a lot and issue its receipt |
| `POST /api/allocations` | Admin, WarehouseOperator | assign a lot to a chamber |
| `POST /api/temperature` | Admin, WarehouseOperator | log a reading (deviations are flagged, not rejected) |
| `POST /api/inspections` | Admin, WarehouseOperator | record an inspection |
| `POST /api/invoices` | Admin, BillingClerk | invoice a lot (daily rate × days × quantity) |
| `POST /api/payments` | Admin, BillingClerk | record a payment |
| `POST /api/releases` | Admin | approve a release |

## Notes

- `SystemUser` has one column beyond the ER diagram, `CustomerID` (NULL for staff), so a *Customer* login can be tied to its own records. The role names are `Admin`, `WarehouseOperator`, `BillingClerk`, `Customer`.
- Compression trade-offs from the 9-entity design still apply: one release total per allocation row, one lot and one running payment per invoice.
- For production, run behind HTTPS, set a long random `SECRET_KEY`, and serve with a WSGI server (e.g. `gunicorn backend.app:app` from the `backend` directory).
