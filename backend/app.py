"""Cold Storage Commodity & Chamber Management System - Flask REST API + static frontend.
All business rules live in the Oracle database (constraints + triggers); this layer
authenticates users, applies role-based access, runs parameterised SQL and reports errors."""
import os
import re
from datetime import date, datetime
from functools import wraps

import oracledb
from flask import Flask, jsonify, request, send_from_directory, session
from werkzeug.security import check_password_hash

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

import db

app = Flask(__name__, static_folder=os.path.join(os.path.dirname(__file__), "..", "frontend"), static_url_path="")
app.secret_key = os.environ.get("SECRET_KEY", "dev-only-change-me")
app.config.update(SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE="Lax")

STAFF = ("Admin", "WarehouseOperator", "BillingClerk")
REPORTS = {
    "occ": "vw_chamber_occupancy", "age": "vw_lot_ageing", "dev": "vw_temperature_deviation",
    "stock": "vw_customer_stock", "rel": "vw_releases", "bill": "vw_billing", "rev": "vw_revenue_by_month",
}
CUSTOMER_REPORTS = {"age", "stock", "bill"}  # the read-only customer portal
CONSTRAINT_MSG = {
    "CHK_TEMP_RANGE": "Temperature must be between -60 and 60 °C (sensor sanity check)",
    "CHK_INV_PAID": "Payment would exceed the invoice total",
    "CHK_ALLOC_RELEASED": "Released quantity cannot exceed the allocated quantity",
    "CHK_LOT_QTY": "Quantity must be greater than zero",
    "CHK_LOT_DATES": "Expiry date cannot be before the arrival date",
    "CHK_COND_SCORE": "Condition score must be between 1 and 5",
    "CHK_INV_PERIOD": "Period end cannot be before period start",
    "CHK_ALLOC_QTY": "Quantity must be greater than zero",
    "CHK_INV_QTY": "Quantity and rate must be greater than zero",
    "UQ_TEMP_READING": "A reading for this chamber at this exact time already exists",
}


# ---------------------------------------------------------------- helpers
def need(*roles):
    """Require a signed-in user, optionally restricted to the given roles."""
    def deco(fn):
        @wraps(fn)
        def wrapper(*a, **k):
            u = session.get("u")
            if not u:
                return jsonify(error="Please sign in"), 401
            if roles and u["role"] not in roles:
                return jsonify(error="Your role is not permitted to do this"), 403
            return fn(*a, **k)
        return wrapper
    return deco


def friendly(e):
    """Turn an Oracle error into a short message (custom trigger text, constraint name, ...)."""
    err = e.args[0] if e.args else e
    msg = getattr(err, "message", str(err))
    m = re.search(r"ORA-200\d\d: (.*)", msg)
    if m:
        return m.group(1).strip()
    m = re.search(r"ORA-0(?:2290|0001): .*?\((?:\w+\.)?(\w+)\)", msg)
    if m:
        name = m.group(1).upper()
        return CONSTRAINT_MSG.get(name, f"Constraint {name} violated")
    if "ORA-02291" in msg:
        return "A referenced record does not exist"
    return msg.splitlines()[0]


def number(v, label):
    try:
        return float(v)
    except (TypeError, ValueError):
        raise ValueError(f"{label} must be a number")


def day(v, optional=False):
    if not v:
        if optional:
            return None
        return datetime.combine(date.today(), datetime.min.time())
    try:
        return datetime.strptime(v[:10], "%Y-%m-%d")
    except ValueError:
        raise ValueError("Invalid date")


@app.errorhandler(oracledb.DatabaseError)
def on_db_error(e):
    return jsonify(error=friendly(e)), 400


@app.errorhandler(ValueError)
def on_value_error(e):
    return jsonify(error=str(e)), 400


# ---------------------------------------------------------------- pages & auth
@app.get("/")
def index():
    return send_from_directory(app.static_folder, "index.html")


@app.post("/api/login")
def login():
    d = request.get_json(silent=True) or {}
    u = (d.get("username") or "").strip().lower()
    r = db.query(
        'SELECT UserID AS "id", PasswordHash AS "h", FullName AS "name", RoleName AS "role", '
        'CustomerID AS "cust", Status AS "st" FROM SystemUser '
        "WHERE LOWER(Username) = :u OR LOWER(Email) = :u", u=u)
    if not r or r[0]["st"] != "Active" or not check_password_hash(r[0]["h"], d.get("password") or ""):
        return jsonify(error="invalid username or password"), 401
    user = {k: r[0][k] for k in ("id", "name", "role", "cust")}
    session["u"] = user
    return jsonify(user)


@app.get("/api/me")
def me():
    u = session.get("u")
    return (jsonify(u), 200) if u else (jsonify(error="not signed in"), 401)


@app.post("/api/logout")
def logout():
    session.clear()
    return jsonify(ok=True)


# ---------------------------------------------------------------- read endpoints
@app.get("/api/data")
@need(*STAFF)
def data():
    q = db.query
    return jsonify(
        customers=q('SELECT CustomerID AS "id", Name AS "n" FROM Customer ORDER BY CustomerID'),
        commodities=q('SELECT CommodityID AS "id", Name AS "n", OptTempMinC AS "lo", OptTempMaxC AS "hi", '
                      'UOM AS "u", CurrentRatePerUOMPerDay AS "rate" FROM Commodity ORDER BY CommodityID'),
        chambers=q('SELECT ChamberID AS "id", ChamberName AS "n", Type AS "ty", TotalCapacityKg AS "kg" '
                   "FROM Chamber ORDER BY ChamberID"),
        users=q('SELECT UserID AS "id", FullName AS "n" FROM SystemUser ORDER BY UserID'),
        lots=q('SELECT LotID AS "id", CustomerID AS "c", CommodityID AS "m", InitialQty AS "init", '
               'CurrentBalanceQty AS "bal", ArrivalDate AS "arr", ExpiryDate AS "exp", '
               'ProductionBatchNumber AS "batch", ReceiptNumber AS "rec" FROM Lot ORDER BY LENGTH(LotID), LotID'),
        allocations=q('SELECT AllocationID AS "id", LotID AS "lot", ChamberID AS "ch", AllocatedQuantity AS "qty", '
                      'AllocationDate AS "ad", ReleasedQuantity AS "rel", ReleaseDate AS "rdate", '
                      'ApprovedByID AS "appr", Status AS "st" FROM Allocation ORDER BY LENGTH(AllocationID), AllocationID'),
        temps=q('SELECT LogID AS "id", ChamberID AS "ch", RecordedTimestamp AS "ts", TemperatureCelsius AS "t" '
                "FROM TemperatureLog ORDER BY LENGTH(LogID), LogID"),
        inspections=q('SELECT InspectionID AS "id", LotID AS "lot", InspectionDate AS "idate", '
                      'ConditionScore AS "s", Remarks AS "rem" FROM Inspection ORDER BY LENGTH(InspectionID), InspectionID'),
        invoices=q('SELECT InvoiceID AS "id", CustomerID AS "c", LotID AS "lot", InvoiceNumber AS "num", '
                   'QuantityBilled AS "qty", RateApplied AS "rate", AmountPaid AS "paid", PaymentDate AS "pdate", '
                   'PaymentMethod AS "m", Status AS "st" FROM Invoice ORDER BY LENGTH(InvoiceID), InvoiceID'),
    )


@app.get("/api/reports/<name>")
@need()
def report(name):
    u = session["u"]
    if name not in REPORTS:
        return jsonify(error="Unknown report"), 404
    if u["role"] == "Customer" and name not in CUSTOMER_REPORTS:
        return jsonify(error="Your role is not permitted to do this"), 403
    rows = db.query(f"SELECT * FROM {REPORTS[name]}")  # name is whitelisted above
    if u["role"] == "Customer":
        rows = [r for r in rows if r.get("customerid") == u["cust"]]
    return jsonify(rows=rows)


# ---------------------------------------------------------------- write endpoints
@app.post("/api/lots")
@need("Admin", "WarehouseOperator")
def add_lot():
    d = request.get_json() or {}
    qty = number(d.get("q"), "Quantity")
    with db.tx() as c:
        lot_id = f"LT{db.next_id(c, 'seq_lot')}"
        receipt = f"REC-2026-{db.next_id(c, 'seq_rec'):03d}"
        c.execute(
            "INSERT INTO Lot (LotID, CustomerID, CommodityID, InitialQty, CurrentBalanceQty, ArrivalDate, "
            "ExpiryDate, ProductionBatchNumber, QualityStatus, ReceiptNumber, ReceivedByID) "
            "VALUES (:id, :c, :m, :q, :q, :arr, :ex, :b, 'Pending', :rec, :u)",
            id=lot_id, c=d.get("c"), m=d.get("m"), q=qty, arr=day(d.get("arr")), ex=day(d.get("exp"), True),
            b=d.get("b") or None, rec=receipt, u=session["u"]["id"])
    return jsonify(message=f"Lot {lot_id} registered, receipt {receipt} issued.")


@app.post("/api/allocations")
@need("Admin", "WarehouseOperator")
def add_allocation():
    d = request.get_json() or {}
    qty = number(d.get("q"), "Quantity")
    with db.tx() as c:  # capacity rules are enforced by trg_allocation_limits
        al_id = f"AL{db.next_id(c, 'seq_alloc')}"
        c.execute("INSERT INTO Allocation (AllocationID, LotID, ChamberID, AllocatedQuantity) "
                  "VALUES (:id, :l, :c, :q)", id=al_id, l=d.get("l"), c=d.get("c"), q=qty)
    return jsonify(message=f"Allocation {al_id} saved: {qty:g} placed in {d.get('c')}.")


@app.post("/api/temperature")
@need("Admin", "WarehouseOperator")
def add_temperature():
    d = request.get_json() or {}
    temp = number(d.get("t"), "Temperature")
    try:
        ts = datetime.strptime((d.get("ts") or "")[:16], "%Y-%m-%dT%H:%M")
    except ValueError:
        raise ValueError("Invalid date/time")
    with db.tx() as c:
        log_id = f"TL{db.next_id(c, 'seq_temp')}"
        c.execute("INSERT INTO TemperatureLog (LogID, ChamberID, RecordedTimestamp, TemperatureCelsius, RecordedByID) "
                  "VALUES (:id, :c, :ts, :t, :u)", id=log_id, c=d.get("c"), ts=ts, t=temp, u=session["u"]["id"])
        c.execute("SELECT CommodityAffected, OptTempMinC, OptTempMaxC FROM vw_temperature_deviation "
                  "WHERE LogID = :id AND ComplianceStatus = 'DEVIATION'", id=log_id)
        dev = c.fetchone()
    if dev:
        return jsonify(warn=True, message=f"Logged with DEVIATION: {temp:g}°C is outside "
                                          f"{float(dev[1]):g} to {float(dev[2]):g}°C for {dev[0]}.")
    return jsonify(message=f"Reading {log_id} logged within range.")


@app.post("/api/inspections")
@need("Admin", "WarehouseOperator")
def add_inspection():
    d = request.get_json() or {}
    score = int(number(d.get("s"), "Score"))
    with db.tx() as c:
        ins_id = f"IN{db.next_id(c, 'seq_insp')}"
        c.execute("INSERT INTO Inspection (InspectionID, LotID, InspectorID, ConditionScore, Remarks) "
                  "VALUES (:id, :l, :u, :s, :r)", id=ins_id, l=d.get("l"), u=session["u"]["id"], s=score,
                  r=(d.get("r") or None))
    return jsonify(message=f"Inspection {ins_id} recorded (score {score}).")


@app.post("/api/invoices")
@need("Admin", "BillingClerk")
def add_invoice():
    d = request.get_json() or {}
    start, end = day(d.get("s")), day(d.get("e"))
    days = (end - start).days + 1
    if days < 1:
        raise ValueError("Period end cannot be before period start")
    with db.tx() as c:
        c.execute("SELECT l.CustomerID, l.CurrentBalanceQty, co.CurrentRatePerUOMPerDay, co.UOM FROM Lot l "
                  "JOIN Commodity co ON co.CommodityID = l.CommodityID WHERE l.LotID = :l", l=d.get("l"))
        row = c.fetchone()
        if not row:
            raise ValueError("Unknown lot")
        cust, bal, daily, uom = row[0], float(row[1]), float(row[2]), row[3]
        rate = round(daily * days, 2)  # duration-based tariff: daily rate x days stored
        inv_id = f"IV{db.next_id(c, 'seq_inv')}"
        number_ = f"INV-2026-{int(inv_id[2:]):03d}"
        c.execute("INSERT INTO Invoice (InvoiceID, CustomerID, LotID, InvoiceNumber, StartDate, EndDate, "
                  "QuantityBilled, RateApplied) VALUES (:id, :c, :l, :n, :s, :e, :q, :r)",
                  id=inv_id, c=cust, l=d.get("l"), n=number_, s=start, e=end, q=bal, r=rate)
    return jsonify(message=f"{number_}: {bal:g} {uom} × {rate:g} ({days} days @ {daily:g}/day) = {bal * rate:,.2f}")


@app.post("/api/payments")
@need("Admin", "BillingClerk")
def add_payment():
    d = request.get_json() or {}
    amt = number(d.get("a"), "Amount")
    with db.tx() as c:  # chk_inv_paid rejects overpayment; trg_invoice_status updates Status
        c.execute("UPDATE Invoice SET AmountPaid = AmountPaid + :a, PaymentDate = SYSDATE, "
                  "PaymentMethod = :m, ReceivedByID = :u WHERE InvoiceID = :i",
                  a=amt, m=d.get("m"), u=session["u"]["id"], i=d.get("i"))
        if c.rowcount == 0:
            raise ValueError("Unknown invoice")
        c.execute("SELECT InvoiceNumber, Status FROM Invoice WHERE InvoiceID = :i", i=d.get("i"))
        num, status = c.fetchone()
    return jsonify(message=f"Payment recorded. {num} is now {status}.")


@app.post("/api/releases")
@need("Admin")
def add_release():
    d = request.get_json() or {}
    qty = number(d.get("q"), "Quantity")
    if qty <= 0:
        raise ValueError("Quantity must be greater than zero")
    with db.tx() as c:  # trg_release checks balance + receipt date and updates the lot balance
        c.execute("SELECT ReleasedQuantity, LotID FROM Allocation WHERE AllocationID = :a", a=d.get("a"))
        row = c.fetchone()
        if not row:
            raise ValueError("Unknown allocation")
        c.execute("UPDATE Allocation SET ReleasedQuantity = :q, ReleaseDate = :dt, ApprovedByID = :u "
                  "WHERE AllocationID = :a", q=float(row[0]) + qty, dt=day(d.get("d")),
                  u=session["u"]["id"], a=d.get("a"))
        c.execute("SELECT CurrentBalanceQty FROM Lot WHERE LotID = :l", l=row[1])
        bal = float(c.fetchone()[0])
    return jsonify(message=f"Released {qty:g} from {d.get('a')}. Lot {row[1]} balance is now {bal:g}.")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 5000)), debug=os.environ.get("FLASK_DEBUG") == "1")
