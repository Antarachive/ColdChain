-- Deliberately breaks each business rule; every block should print "rejected". Evidence for Table 15.
-- Run after 01-03:  @04_rule_tests.sql
SET SERVEROUTPUT ON SIZE UNLIMITED

BEGIN  -- TC-01 allocation above lot balance (LT4 is fully allocated)
  INSERT INTO Allocation (AllocationID, LotID, ChamberID, AllocatedQuantity) VALUES ('AL90','LT4','CH3',500);
  DBMS_OUTPUT.PUT_LINE('TC-01 NOT REJECTED');
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('TC-01 rejected: ' || SQLERRM);
END;
/
BEGIN  -- TC-02 allocation above chamber capacity (CH2 has 3000 kg free; lot has enough balance)
  INSERT INTO Lot (LotID, CustomerID, CommodityID, InitialQty, CurrentBalanceQty, ReceiptNumber, ReceivedByID)
  VALUES ('LT99','C3','CM3',5000,5000,'REC-TEST-99','U2');
  INSERT INTO Allocation (AllocationID, LotID, ChamberID, AllocatedQuantity) VALUES ('AL91','LT99','CH2',3500);
  DBMS_OUTPUT.PUT_LINE('TC-02 NOT REJECTED');
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('TC-02 rejected: ' || SQLERRM);
END;
/
BEGIN  -- TC-03 release above allocated quantity (AL2 holds 1000)
  UPDATE Allocation SET ReleasedQuantity = 1500, ReleaseDate = SYSDATE WHERE AllocationID = 'AL2';
  DBMS_OUTPUT.PUT_LINE('TC-03 NOT REJECTED');
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('TC-03 rejected: ' || SQLERRM);
END;
/
BEGIN  -- TC-04 release dated before the lot was received
  UPDATE Allocation SET ReleasedQuantity = 100, ReleaseDate = DATE '2026-01-01' WHERE AllocationID = 'AL2';
  DBMS_OUTPUT.PUT_LINE('TC-04 NOT REJECTED');
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('TC-04 rejected: ' || SQLERRM);
END;
/
BEGIN  -- TC-05 impossible sensor reading
  INSERT INTO TemperatureLog VALUES ('TL90','CH1',SYSTIMESTAMP,150,'U2');
  DBMS_OUTPUT.PUT_LINE('TC-05 NOT REJECTED');
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('TC-05 rejected: ' || SQLERRM);
END;
/
BEGIN  -- TC-06 payment above invoice total (IV3 total is 7500)
  UPDATE Invoice SET AmountPaid = 9000 WHERE InvoiceID = 'IV3';
  DBMS_OUTPUT.PUT_LINE('TC-06 NOT REJECTED');
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('TC-06 rejected: ' || SQLERRM);
END;
/
ROLLBACK;
