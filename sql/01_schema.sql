-- ============================================================================
-- COLD STORAGE COMMODITY & CHAMBER MANAGEMENT SYSTEM  -  Oracle 19c / 21c / 23ai
-- 9-table 3NF schema, integrity constraints, sequences and business-rule triggers
-- Run as COLDSTORAGE:  @01_schema.sql
-- ============================================================================

CREATE TABLE Customer (
    CustomerID    VARCHAR2(10)  PRIMARY KEY,
    Name          VARCHAR2(100) NOT NULL,
    ContactPerson VARCHAR2(80),
    Phone         VARCHAR2(20),
    Email         VARCHAR2(80)  UNIQUE,
    Address       VARCHAR2(150),
    City          VARCHAR2(50),
    TaxID_GSTIN   VARCHAR2(20)  UNIQUE,
    RegDate       DATE DEFAULT SYSDATE NOT NULL
);

-- Role is folded in as RoleName. CustomerID links a portal login to its customer (Customer role only).
CREATE TABLE SystemUser (
    UserID       VARCHAR2(10)  PRIMARY KEY,
    Username     VARCHAR2(30)  NOT NULL UNIQUE,
    PasswordHash VARCHAR2(200) NOT NULL,
    FullName     VARCHAR2(80)  NOT NULL,
    Email        VARCHAR2(80)  NOT NULL UNIQUE,
    RoleName     VARCHAR2(30)  NOT NULL,
    Status       VARCHAR2(10)  DEFAULT 'Active' NOT NULL,
    CustomerID   VARCHAR2(10)  REFERENCES Customer(CustomerID),
    CONSTRAINT chk_user_role     CHECK (RoleName IN ('Admin','WarehouseOperator','BillingClerk','Customer')),
    CONSTRAINT chk_user_status   CHECK (Status IN ('Active','Inactive')),
    CONSTRAINT chk_user_customer CHECK (RoleName <> 'Customer' OR CustomerID IS NOT NULL)
);

-- Rate is folded in as CurrentRatePerUOMPerDay.
CREATE TABLE Commodity (
    CommodityID             VARCHAR2(10) PRIMARY KEY,
    Name                    VARCHAR2(80) NOT NULL,
    Category                VARCHAR2(30),
    OptTempMinC             NUMBER(5,2)  NOT NULL,
    OptTempMaxC             NUMBER(5,2)  NOT NULL,
    UOM                     VARCHAR2(10) NOT NULL,
    CurrentRatePerUOMPerDay NUMBER(8,2)  NOT NULL,
    CONSTRAINT chk_comm_temp CHECK (OptTempMaxC >= OptTempMinC),
    CONSTRAINT chk_comm_rate CHECK (CurrentRatePerUOMPerDay > 0)
);

-- Location is folded in as WarehouseName / ZoneCode.
CREATE TABLE Chamber (
    ChamberID       VARCHAR2(10) PRIMARY KEY,
    WarehouseName   VARCHAR2(80) NOT NULL,
    ZoneCode        VARCHAR2(20) NOT NULL,
    ChamberName     VARCHAR2(50) NOT NULL,
    Type            VARCHAR2(20) NOT NULL,
    TotalCapacityM3 NUMBER(10,2) NOT NULL,
    TotalCapacityKg NUMBER(10,2) NOT NULL,
    Status          VARCHAR2(20) DEFAULT 'Active' NOT NULL,
    CONSTRAINT chk_chamber_type   CHECK (Type IN ('Chilled','Frozen','Ambient')),
    CONSTRAINT chk_chamber_cap    CHECK (TotalCapacityM3 > 0 AND TotalCapacityKg > 0),
    CONSTRAINT chk_chamber_status CHECK (Status IN ('Active','Under Maintenance'))
);

-- Receipt is folded in (ReceiptNumber, ReceivedByID); ArrivalDate doubles as the receipt date.
-- CurrentBalanceQty is a cached value maintained by trg_release (never written by the app).
CREATE TABLE Lot (
    LotID                 VARCHAR2(10) PRIMARY KEY,
    CustomerID            VARCHAR2(10) NOT NULL REFERENCES Customer(CustomerID),
    CommodityID           VARCHAR2(10) NOT NULL REFERENCES Commodity(CommodityID),
    InitialQty            NUMBER(10,2) NOT NULL,
    CurrentBalanceQty     NUMBER(10,2) NOT NULL,
    ArrivalDate           DATE DEFAULT SYSDATE NOT NULL,
    ExpiryDate            DATE,
    ProductionBatchNumber VARCHAR2(40),
    QualityStatus         VARCHAR2(20) DEFAULT 'Pending' NOT NULL,
    ReceiptNumber         VARCHAR2(30) NOT NULL UNIQUE,
    ReceivedByID          VARCHAR2(10) NOT NULL REFERENCES SystemUser(UserID),
    CONSTRAINT chk_lot_qty     CHECK (InitialQty > 0),
    CONSTRAINT chk_lot_balance CHECK (CurrentBalanceQty >= 0 AND CurrentBalanceQty <= InitialQty),
    CONSTRAINT chk_lot_dates   CHECK (ExpiryDate IS NULL OR ExpiryDate >= ArrivalDate),
    CONSTRAINT chk_lot_quality CHECK (QualityStatus IN ('Pending','Approved','Quarantined'))
);

-- Release is folded in (ReleasedQuantity, ReleaseDate, ApprovedByID).
CREATE TABLE Allocation (
    AllocationID      VARCHAR2(10) PRIMARY KEY,
    LotID             VARCHAR2(10) NOT NULL REFERENCES Lot(LotID),
    ChamberID         VARCHAR2(10) NOT NULL REFERENCES Chamber(ChamberID),
    AllocatedQuantity NUMBER(10,2) NOT NULL,
    AllocationDate    DATE DEFAULT SYSDATE NOT NULL,
    ReleasedQuantity  NUMBER(10,2) DEFAULT 0 NOT NULL,
    ReleaseDate       DATE,
    ApprovedByID      VARCHAR2(10) REFERENCES SystemUser(UserID),
    Status            VARCHAR2(20) DEFAULT 'Active' NOT NULL,
    CONSTRAINT chk_alloc_qty      CHECK (AllocatedQuantity > 0),
    CONSTRAINT chk_alloc_released CHECK (ReleasedQuantity >= 0 AND ReleasedQuantity <= AllocatedQuantity),
    CONSTRAINT chk_alloc_status   CHECK (Status IN ('Active','Released'))
);

CREATE TABLE TemperatureLog (
    LogID              VARCHAR2(10) PRIMARY KEY,
    ChamberID          VARCHAR2(10) NOT NULL REFERENCES Chamber(ChamberID),
    RecordedTimestamp  TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    TemperatureCelsius NUMBER(5,2) NOT NULL,
    RecordedByID       VARCHAR2(10) NOT NULL REFERENCES SystemUser(UserID),
    CONSTRAINT chk_temp_range CHECK (TemperatureCelsius BETWEEN -60 AND 60),
    CONSTRAINT uq_temp_reading UNIQUE (ChamberID, RecordedTimestamp)
);

CREATE TABLE Inspection (
    InspectionID   VARCHAR2(10) PRIMARY KEY,
    LotID          VARCHAR2(10) NOT NULL REFERENCES Lot(LotID),
    InspectionDate DATE DEFAULT SYSDATE NOT NULL,
    InspectorID    VARCHAR2(10) NOT NULL REFERENCES SystemUser(UserID),
    ConditionScore NUMBER(1)    NOT NULL,
    Remarks        VARCHAR2(300),
    CONSTRAINT chk_cond_score CHECK (ConditionScore BETWEEN 1 AND 5)
);

-- InvoiceLineItem and Payment are folded in: one lot and one running payment total per invoice.
-- TotalAmount is a VIRTUAL (computed) column, so it can never drift from its inputs.
CREATE TABLE Invoice (
    InvoiceID      VARCHAR2(10) PRIMARY KEY,
    CustomerID     VARCHAR2(10) NOT NULL REFERENCES Customer(CustomerID),
    LotID          VARCHAR2(10) NOT NULL REFERENCES Lot(LotID),
    InvoiceNumber  VARCHAR2(30) NOT NULL UNIQUE,
    GeneratedDate  DATE DEFAULT SYSDATE NOT NULL,
    StartDate      DATE NOT NULL,
    EndDate        DATE NOT NULL,
    QuantityBilled NUMBER(10,2) NOT NULL,
    RateApplied    NUMBER(10,2) NOT NULL,
    TotalAmount    NUMBER(14,2) GENERATED ALWAYS AS (QuantityBilled * RateApplied) VIRTUAL,
    AmountPaid     NUMBER(14,2) DEFAULT 0 NOT NULL,
    PaymentDate    DATE,
    PaymentMethod  VARCHAR2(20),
    ReceivedByID   VARCHAR2(10) REFERENCES SystemUser(UserID),
    Status         VARCHAR2(20) DEFAULT 'Draft' NOT NULL,
    CONSTRAINT chk_inv_period CHECK (EndDate >= StartDate),
    CONSTRAINT chk_inv_qty    CHECK (QuantityBilled > 0 AND RateApplied > 0),
    CONSTRAINT chk_inv_paid   CHECK (AmountPaid >= 0 AND AmountPaid <= QuantityBilled * RateApplied),
    CONSTRAINT chk_inv_method CHECK (PaymentMethod IS NULL OR PaymentMethod IN ('Cash','Bank Transfer','Cheque','UPI')),
    CONSTRAINT chk_inv_status CHECK (Status IN ('Draft','Paid','Partially Paid','Overdue'))
);

-- Indexes on frequently searched columns
CREATE INDEX idx_lot_customer     ON Lot(CustomerID);
CREATE INDEX idx_lot_commodity    ON Lot(CommodityID);
CREATE INDEX idx_lot_expiry       ON Lot(ExpiryDate);
CREATE INDEX idx_alloc_lot        ON Allocation(LotID, Status);
CREATE INDEX idx_alloc_chamber    ON Allocation(ChamberID, Status);
CREATE INDEX idx_temp_chamber_ts  ON TemperatureLog(ChamberID, RecordedTimestamp);
CREATE INDEX idx_insp_lot_date    ON Inspection(LotID, InspectionDate);
CREATE INDEX idx_inv_cust_status  ON Invoice(CustomerID, Status);
CREATE INDEX idx_inv_lot          ON Invoice(LotID);

-- Sequences used by the application for new IDs (they start after the seed data)
CREATE SEQUENCE seq_lot   START WITH 8 NOCACHE;
CREATE SEQUENCE seq_rec   START WITH 8 NOCACHE;
CREATE SEQUENCE seq_alloc START WITH 5 NOCACHE;
CREATE SEQUENCE seq_temp  START WITH 9 NOCACHE;
CREATE SEQUENCE seq_insp  START WITH 5 NOCACHE;
CREATE SEQUENCE seq_inv   START WITH 4 NOCACHE;

-- ============================================================================
-- RULE 1: ALLOCATION WITHIN CAPACITY (lot balance and chamber kg capacity)
-- Oracle forbids a row trigger from querying its own table (ORA-04091), so this is a
-- COMPOUND trigger: rows are collected per row and validated once AFTER STATEMENT.
-- ============================================================================
CREATE OR REPLACE TRIGGER trg_allocation_limits
FOR INSERT ON Allocation
COMPOUND TRIGGER
    TYPE t_row IS RECORD (
        alloc_id Allocation.AllocationID%TYPE,
        lot_id   Allocation.LotID%TYPE,
        ch_id    Allocation.ChamberID%TYPE,
        qty      Allocation.AllocatedQuantity%TYPE);
    TYPE t_tab IS TABLE OF t_row INDEX BY PLS_INTEGER;
    g_rows t_tab;
    g_n    PLS_INTEGER := 0;

    BEFORE EACH ROW IS
    BEGIN
        g_n := g_n + 1;
        g_rows(g_n).alloc_id := :NEW.AllocationID;
        g_rows(g_n).lot_id   := :NEW.LotID;
        g_rows(g_n).ch_id    := :NEW.ChamberID;
        g_rows(g_n).qty      := :NEW.AllocatedQuantity;
    END BEFORE EACH ROW;

    AFTER STATEMENT IS
        v_bal NUMBER; v_used NUMBER; v_cap NUMBER;
    BEGIN
        FOR i IN 1 .. g_n LOOP
            SELECT CurrentBalanceQty INTO v_bal FROM Lot WHERE LotID = g_rows(i).lot_id;
            SELECT NVL(SUM(AllocatedQuantity), 0) INTO v_used FROM Allocation
             WHERE LotID = g_rows(i).lot_id AND Status = 'Active' AND AllocationID <> g_rows(i).alloc_id;
            IF v_used + g_rows(i).qty > v_bal THEN
                RAISE_APPLICATION_ERROR(-20001, 'Allocation of ' || TO_CHAR(g_rows(i).qty, 'FM9999999990.00')
                    || ' exceeds lot balance (' || TO_CHAR(v_bal - v_used, 'FM9999999990.00')
                    || ') for LotID ' || g_rows(i).lot_id);
            END IF;

            SELECT TotalCapacityKg INTO v_cap FROM Chamber WHERE ChamberID = g_rows(i).ch_id;
            SELECT NVL(SUM(AllocatedQuantity - ReleasedQuantity), 0) INTO v_used FROM Allocation
             WHERE ChamberID = g_rows(i).ch_id AND Status = 'Active' AND AllocationID <> g_rows(i).alloc_id;
            IF v_used + g_rows(i).qty > v_cap THEN
                RAISE_APPLICATION_ERROR(-20002, 'Allocation of ' || TO_CHAR(g_rows(i).qty, 'FM9999999990.00')
                    || ' exceeds chamber capacity (' || TO_CHAR(v_cap - v_used, 'FM9999999990.00')
                    || ') for ChamberID ' || g_rows(i).ch_id);
            END IF;
        END LOOP;
    END AFTER STATEMENT;
END trg_allocation_limits;
/

-- ============================================================================
-- RULES 2 & 4: RELEASE WITHIN STORED BALANCE, RELEASE AFTER RECEIPT
-- Fires when ReleasedQuantity increases; also keeps Lot.CurrentBalanceQty in sync.
-- ============================================================================
CREATE OR REPLACE TRIGGER trg_release
BEFORE UPDATE OF ReleasedQuantity ON Allocation
FOR EACH ROW
WHEN (NEW.ReleasedQuantity > OLD.ReleasedQuantity)
DECLARE
    v_arrival DATE;
BEGIN
    IF :NEW.ReleasedQuantity > :NEW.AllocatedQuantity THEN
        RAISE_APPLICATION_ERROR(-20003, 'Release of ' || TO_CHAR(:NEW.ReleasedQuantity, 'FM9999999990.00')
            || ' exceeds allocated quantity (' || TO_CHAR(:NEW.AllocatedQuantity, 'FM9999999990.00')
            || ') for AllocationID ' || :NEW.AllocationID);
    END IF;

    SELECT ArrivalDate INTO v_arrival FROM Lot WHERE LotID = :NEW.LotID;
    IF :NEW.ReleaseDate IS NULL OR :NEW.ReleaseDate < v_arrival THEN
        RAISE_APPLICATION_ERROR(-20004, 'Release date must be on/after the lot receipt date ('
            || TO_CHAR(v_arrival, 'YYYY-MM-DD') || ') for AllocationID ' || :NEW.AllocationID);
    END IF;

    UPDATE Lot SET CurrentBalanceQty = CurrentBalanceQty - (:NEW.ReleasedQuantity - :OLD.ReleasedQuantity)
     WHERE LotID = :NEW.LotID;

    IF :NEW.ReleasedQuantity >= :NEW.AllocatedQuantity THEN
        :NEW.Status := 'Released';
    END IF;
END;
/

-- ============================================================================
-- RULE 3 (VALID TEMPERATURE RANGES): CHECK chk_temp_range blocks impossible sensor values;
--   readings outside a commodity's optimum are logged and flagged by vw_temperature_deviation.
-- RULE 5 (PAYMENT LIMITS): CHECK chk_inv_paid (AmountPaid <= QuantityBilled * RateApplied).
-- This trigger keeps Invoice.Status in step with the amount paid.
-- ============================================================================
CREATE OR REPLACE TRIGGER trg_invoice_status
BEFORE INSERT OR UPDATE ON Invoice
FOR EACH ROW
BEGIN
    IF :NEW.AmountPaid >= :NEW.QuantityBilled * :NEW.RateApplied THEN
        :NEW.Status := 'Paid';
    ELSIF :NEW.AmountPaid > 0 THEN
        :NEW.Status := 'Partially Paid';
    END IF;
END;
/
