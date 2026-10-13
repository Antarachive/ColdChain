-- Sample data. Run as COLDSTORAGE after 01_schema.sql.
-- Demo logins: admin_user/admin123, op_user1/op123, bill_user1/bill123, greenfields/cust123
SET DEFINE OFF

INSERT INTO Customer (CustomerID, Name, ContactPerson, Phone, Email, Address, City, TaxID_GSTIN, RegDate)
VALUES ('C1','GreenFields Agro Ltd','Amit Verma','+919876543210','contact@greenfields.com','Gachibowli','Hyderabad','36AABCG1234F1Z5',DATE '2026-01-10');
INSERT INTO Customer (CustomerID, Name, ContactPerson, Phone, Email, Address, City, TaxID_GSTIN, RegDate)
VALUES ('C2','MediCorp Pharma','Dr. Sneha Reddy','+919123456789','logistics@medicorp.com','Banjara Hills','Hyderabad','36AABCM5678G1Z2',DATE '2026-01-15');
INSERT INTO Customer (CustomerID, Name, ContactPerson, Phone, Email, Address, City, TaxID_GSTIN, RegDate)
VALUES ('C3','Deccan Dairy Farms','Vijay Singh','+919988776655','ops@deccandairy.com','Kukatpally','Hyderabad','36AABCD9012H1Z8',DATE '2026-01-20');

-- Passwords are PBKDF2-SHA256 hashes (werkzeug): admin123 / op123 / bill123 / cust123
INSERT INTO SystemUser (UserID, Username, PasswordHash, FullName, Email, RoleName, Status, CustomerID)
VALUES ('U1','admin_user','pbkdf2:sha256:1000000$cSNhJ1n5DsIaHVQF$5aaeb170920e23287324b8acaff1a3c65f997f51f80efa2d62f47027139840f3','Ramesh Kumar','ramesh@coldstorage.com','Admin','Active',NULL);
INSERT INTO SystemUser (UserID, Username, PasswordHash, FullName, Email, RoleName, Status, CustomerID)
VALUES ('U2','op_user1','pbkdf2:sha256:1000000$z3SEYv33TgjUEwyC$ee2188c1797354a16aec182b139567388c4ccec14616358643cb7e0b29226c60','Suresh Patel','suresh@coldstorage.com','WarehouseOperator','Active',NULL);
INSERT INTO SystemUser (UserID, Username, PasswordHash, FullName, Email, RoleName, Status, CustomerID)
VALUES ('U3','op_user2','pbkdf2:sha256:1000000$z3SEYv33TgjUEwyC$ee2188c1797354a16aec182b139567388c4ccec14616358643cb7e0b29226c60','Kavita Rao','kavita@coldstorage.com','WarehouseOperator','Active',NULL);
INSERT INTO SystemUser (UserID, Username, PasswordHash, FullName, Email, RoleName, Status, CustomerID)
VALUES ('U4','bill_user1','pbkdf2:sha256:1000000$erdA8eKhfU1XPdgP$3607493a0e4ef47eac43c598a69818a3f8832a2a862d7e12a715904c1b1272a7','Priya Sharma','priya@coldstorage.com','BillingClerk','Active',NULL);
INSERT INTO SystemUser (UserID, Username, PasswordHash, FullName, Email, RoleName, Status, CustomerID)
VALUES ('U5','greenfields','pbkdf2:sha256:1000000$5qKJCGjYQ1aTfQK7$87df423818636e8da33d9fffdf2db9126162777fbb9e0331a539c17dc4ce4a83','GreenFields Agro Ltd','portal@greenfields.com','Customer','Active','C1');

INSERT INTO Commodity VALUES ('CM1','Fresh Kashmiri Apples','Produce',-1,4,'Kgs',2.50);
INSERT INTO Commodity VALUES ('CM2','COVID-19 Vaccines','Pharma',2,8,'Units',5.00);
INSERT INTO Commodity VALUES ('CM3','Fresh Milk (Bulk)','Dairy',0,4,'Litres',1.75);

INSERT INTO Chamber (ChamberID, WarehouseName, ZoneCode, ChamberName, Type, TotalCapacityM3, TotalCapacityKg, Status)
VALUES ('CH1','Main Warehouse Block 1','ZONE-A','Chamber-A1','Chilled',500,10000,'Active');
INSERT INTO Chamber (ChamberID, WarehouseName, ZoneCode, ChamberName, Type, TotalCapacityM3, TotalCapacityKg, Status)
VALUES ('CH2','Pharma Vault Block 2','ZONE-B','Chamber-B1','Frozen',200,4000,'Active');
INSERT INTO Chamber (ChamberID, WarehouseName, ZoneCode, ChamberName, Type, TotalCapacityM3, TotalCapacityKg, Status)
VALUES ('CH3','Main Warehouse Block 1','ZONE-A','Chamber-A2','Chilled',300,6000,'Active');

-- Lots start with balance = initial quantity; the release trigger lowers LT1/LT3 below.
INSERT INTO Lot (LotID, CustomerID, CommodityID, InitialQty, CurrentBalanceQty, ArrivalDate, ExpiryDate, ProductionBatchNumber, QualityStatus, ReceiptNumber, ReceivedByID)
VALUES ('LT1','C1','CM1',5000,5000,DATE '2026-02-01',DATE '2026-06-01','BATCH-APP-01','Approved','REC-2026-001','U2');
INSERT INTO Lot (LotID, CustomerID, CommodityID, InitialQty, CurrentBalanceQty, ArrivalDate, ExpiryDate, ProductionBatchNumber, QualityStatus, ReceiptNumber, ReceivedByID)
VALUES ('LT2','C2','CM2',1000,1000,DATE '2026-02-10',DATE '2026-08-10','BATCH-VAC-09','Approved','REC-2026-002','U2');
INSERT INTO Lot (LotID, CustomerID, CommodityID, InitialQty, CurrentBalanceQty, ArrivalDate, ExpiryDate, ProductionBatchNumber, QualityStatus, ReceiptNumber, ReceivedByID)
VALUES ('LT3','C1','CM1',3000,3000,DATE '2026-03-01',DATE '2026-05-15','BATCH-APP-02','Approved','REC-2026-003','U3');
INSERT INTO Lot (LotID, CustomerID, CommodityID, InitialQty, CurrentBalanceQty, ArrivalDate, ExpiryDate, ProductionBatchNumber, QualityStatus, ReceiptNumber, ReceivedByID)
VALUES ('LT4','C3','CM3',2000,2000,DATE '2026-03-05',DATE '2026-03-20','BATCH-MLK-04','Pending','REC-2026-004','U3');
INSERT INTO Lot (LotID, CustomerID, CommodityID, InitialQty, CurrentBalanceQty, ArrivalDate, ExpiryDate, ProductionBatchNumber, QualityStatus, ReceiptNumber, ReceivedByID)
VALUES ('LT5','C2','CM2',500,500,TRUNC(SYSDATE)-10,TRUNC(SYSDATE)+120,'BATCH-VAC-20','Approved','REC-2026-005','U2');
INSERT INTO Lot (LotID, CustomerID, CommodityID, InitialQty, CurrentBalanceQty, ArrivalDate, ExpiryDate, ProductionBatchNumber, QualityStatus, ReceiptNumber, ReceivedByID)
VALUES ('LT6','C3','CM3',800,800,TRUNC(SYSDATE)-45,TRUNC(SYSDATE)+10,'BATCH-MLK-11','Approved','REC-2026-006','U3');
INSERT INTO Lot (LotID, CustomerID, CommodityID, InitialQty, CurrentBalanceQty, ArrivalDate, ExpiryDate, ProductionBatchNumber, QualityStatus, ReceiptNumber, ReceivedByID)
VALUES ('LT7','C1','CM1',1200,1200,TRUNC(SYSDATE)-90,TRUNC(SYSDATE)+30,'BATCH-APP-30','Approved','REC-2026-007','U2');

INSERT INTO Allocation (AllocationID, LotID, ChamberID, AllocatedQuantity, AllocationDate) VALUES ('AL1','LT1','CH1',5000,DATE '2026-02-01');
INSERT INTO Allocation (AllocationID, LotID, ChamberID, AllocatedQuantity, AllocationDate) VALUES ('AL2','LT2','CH2',1000,DATE '2026-02-10');
INSERT INTO Allocation (AllocationID, LotID, ChamberID, AllocatedQuantity, AllocationDate) VALUES ('AL3','LT3','CH3',3000,DATE '2026-03-01');
INSERT INTO Allocation (AllocationID, LotID, ChamberID, AllocatedQuantity, AllocationDate) VALUES ('AL4','LT4','CH1',2000,DATE '2026-03-05');

-- Two recorded releases (trg_release reduces Lot.CurrentBalanceQty: LT1 -> 4500, LT3 -> 2000)
UPDATE Allocation SET ReleasedQuantity = 500,  ReleaseDate = DATE '2026-02-15', ApprovedByID = 'U1' WHERE AllocationID = 'AL1';
UPDATE Allocation SET ReleasedQuantity = 1000, ReleaseDate = DATE '2026-03-10', ApprovedByID = 'U1' WHERE AllocationID = 'AL3';

INSERT INTO TemperatureLog VALUES ('TL1','CH1',TIMESTAMP '2026-02-02 08:00:00',2.50,'U2');
INSERT INTO TemperatureLog VALUES ('TL2','CH2',TIMESTAMP '2026-02-02 08:30:00',4.00,'U2');
INSERT INTO TemperatureLog VALUES ('TL3','CH1',TIMESTAMP '2026-02-03 08:00:00',3.80,'U2');
INSERT INTO TemperatureLog VALUES ('TL4','CH1',TIMESTAMP '2026-02-04 08:00:00',6.50,'U3');
INSERT INTO TemperatureLog VALUES ('TL5','CH3',TIMESTAMP '2026-03-02 09:00:00',1.20,'U3');
INSERT INTO TemperatureLog VALUES ('TL6','CH2',TIMESTAMP '2026-02-05 08:30:00',9.10,'U2');
INSERT INTO TemperatureLog VALUES ('TL7','CH1',TIMESTAMP '2026-03-06 08:00:00',3.00,'U3');
INSERT INTO TemperatureLog VALUES ('TL8','CH3',TIMESTAMP '2026-03-10 09:00:00',5.10,'U3');

INSERT INTO Inspection VALUES ('IN1','LT1',DATE '2026-02-05','U2',5,'Good firmness, zero condensation or spoilage noted.');
INSERT INTO Inspection VALUES ('IN2','LT2',DATE '2026-02-12','U3',5,'Cold chain unbroken, packaging intact.');
INSERT INTO Inspection VALUES ('IN3','LT3',DATE '2026-03-04','U2',4,'Minor surface bruising on outer crates.');
INSERT INTO Inspection VALUES ('IN4','LT1',DATE '2026-03-01','U3',3,'Slight softening observed on 2% of stock.');

-- Invoices: fully paid, partially paid, unpaid. TotalAmount is computed; Status is set by trg_invoice_status.
INSERT INTO Invoice (InvoiceID, CustomerID, LotID, InvoiceNumber, GeneratedDate, StartDate, EndDate, QuantityBilled, RateApplied, AmountPaid, PaymentDate, PaymentMethod, ReceivedByID)
VALUES ('IV1','C1','LT1','INV-2026-001',DATE '2026-02-15',DATE '2026-02-01',DATE '2026-02-15',5000,2.50,12500,DATE '2026-02-16','Bank Transfer','U4');
INSERT INTO Invoice (InvoiceID, CustomerID, LotID, InvoiceNumber, GeneratedDate, StartDate, EndDate, QuantityBilled, RateApplied, AmountPaid, PaymentDate, PaymentMethod, ReceivedByID)
VALUES ('IV2','C2','LT2','INV-2026-002',DATE '2026-03-01',DATE '2026-02-10',DATE '2026-03-01',1000,5.00,3000,DATE '2026-03-05','UPI','U4');
INSERT INTO Invoice (InvoiceID, CustomerID, LotID, InvoiceNumber, GeneratedDate, StartDate, EndDate, QuantityBilled, RateApplied, AmountPaid)
VALUES ('IV3','C1','LT3','INV-2026-003',DATE '2026-03-15',DATE '2026-03-01',DATE '2026-03-15',3000,2.50,0);

COMMIT;
