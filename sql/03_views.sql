-- The seven report views used by the application (Reports screen) and by the Review 2 demo.
CREATE OR REPLACE VIEW vw_chamber_occupancy AS
SELECT c.ChamberID, c.ChamberName, c.WarehouseName, c.Type, c.TotalCapacityKg,
       NVL(SUM(CASE WHEN a.Status = 'Active' THEN a.AllocatedQuantity - a.ReleasedQuantity END), 0) AS OccupiedKg,
       ROUND(100 * NVL(SUM(CASE WHEN a.Status = 'Active' THEN a.AllocatedQuantity - a.ReleasedQuantity END), 0)
             / c.TotalCapacityKg, 1) AS OccupancyPct
FROM Chamber c LEFT JOIN Allocation a ON a.ChamberID = c.ChamberID
GROUP BY c.ChamberID, c.ChamberName, c.WarehouseName, c.Type, c.TotalCapacityKg;

CREATE OR REPLACE VIEW vw_lot_ageing AS
SELECT lo.LotID, lo.CustomerID, cu.Name AS CustomerName, co.Name AS CommodityName,
       lo.ArrivalDate, lo.ExpiryDate,
       TRUNC(SYSDATE) - TRUNC(lo.ArrivalDate) AS DaysInStorage,
       lo.CurrentBalanceQty,
       CASE WHEN lo.ExpiryDate IS NOT NULL AND lo.ExpiryDate < TRUNC(SYSDATE) THEN 'Expired'
            WHEN TRUNC(SYSDATE) - TRUNC(lo.ArrivalDate) > 60 THEN 'Ageing > 60 days'
            WHEN TRUNC(SYSDATE) - TRUNC(lo.ArrivalDate) > 30 THEN 'Ageing 30-60 days'
            ELSE 'Fresh (< 30 days)' END AS AgeingBucket
FROM Lot lo JOIN Customer cu ON cu.CustomerID = lo.CustomerID
            JOIN Commodity co ON co.CommodityID = lo.CommodityID
WHERE lo.CurrentBalanceQty > 0
ORDER BY DaysInStorage DESC;

-- Each reading is checked against every commodity actively stored in that chamber at that time.
CREATE OR REPLACE VIEW vw_temperature_deviation AS
SELECT DISTINCT t.LogID, t.ChamberID, ch.ChamberName, t.RecordedTimestamp, t.TemperatureCelsius,
       co.Name AS CommodityAffected, co.OptTempMinC, co.OptTempMaxC,
       CASE WHEN t.TemperatureCelsius < co.OptTempMinC OR t.TemperatureCelsius > co.OptTempMaxC
            THEN 'DEVIATION' ELSE 'OK' END AS ComplianceStatus
FROM TemperatureLog t
JOIN Chamber ch    ON ch.ChamberID = t.ChamberID
JOIN Allocation al ON al.ChamberID = t.ChamberID AND al.Status = 'Active'
                  AND al.AllocationDate <= TRUNC(t.RecordedTimestamp)
JOIN Lot lo        ON lo.LotID = al.LotID
JOIN Commodity co  ON co.CommodityID = lo.CommodityID;

CREATE OR REPLACE VIEW vw_customer_stock AS
SELECT cu.CustomerID, cu.Name AS CustomerName, co.Name AS CommodityName,
       COUNT(lo.LotID) AS ActiveLots, SUM(lo.CurrentBalanceQty) AS TotalStockOnHand, co.UOM
FROM Customer cu JOIN Lot lo ON lo.CustomerID = cu.CustomerID
                 JOIN Commodity co ON co.CommodityID = lo.CommodityID
WHERE lo.CurrentBalanceQty > 0
GROUP BY cu.CustomerID, cu.Name, co.Name, co.UOM;

CREATE OR REPLACE VIEW vw_releases AS
SELECT a.AllocationID, lo.LotID, cu.CustomerID, cu.Name AS CustomerName, co.Name AS CommodityName,
       ch.ChamberName, a.ReleasedQuantity, a.ReleaseDate, su.FullName AS ApprovedByName,
       TRUNC(a.ReleaseDate) - TRUNC(lo.ArrivalDate) AS DaysHeldBeforeRelease
FROM Allocation a JOIN Lot lo ON lo.LotID = a.LotID
                  JOIN Customer cu ON cu.CustomerID = lo.CustomerID
                  JOIN Commodity co ON co.CommodityID = lo.CommodityID
                  JOIN Chamber ch ON ch.ChamberID = a.ChamberID
                  LEFT JOIN SystemUser su ON su.UserID = a.ApprovedByID
WHERE a.ReleasedQuantity > 0;

CREATE OR REPLACE VIEW vw_billing AS
SELECT i.InvoiceID, i.InvoiceNumber, i.CustomerID, cu.Name AS CustomerName, i.StartDate, i.EndDate,
       i.TotalAmount, i.AmountPaid, i.TotalAmount - i.AmountPaid AS AmountDue, i.Status
FROM Invoice i JOIN Customer cu ON cu.CustomerID = i.CustomerID;

CREATE OR REPLACE VIEW vw_revenue_by_month AS
SELECT TO_CHAR(PaymentDate, 'YYYY-MM') AS RevenueMonth, COUNT(*) AS PaymentCount, SUM(AmountPaid) AS RevenueCollected
FROM Invoice WHERE PaymentDate IS NOT NULL
GROUP BY TO_CHAR(PaymentDate, 'YYYY-MM')
ORDER BY RevenueMonth;
