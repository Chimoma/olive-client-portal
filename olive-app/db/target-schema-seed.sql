-- ---------------------------------------------------------------------------
-- OPTIONAL: run this directly against olive-db-instance if you want to
-- smoke-test the app's /api/customers endpoint BEFORE running the DMS
-- migration. Once DMS runs (Step 10 in README), it will create/populate
-- this same table automatically from olive-legacy-db - you would not run
-- both in that case, since DMS full-load will do this for you.
-- ---------------------------------------------------------------------------

USE olive;
GO

IF OBJECT_ID('dbo.Customers', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Customers (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        Name NVARCHAR(100) NOT NULL,
        Email NVARCHAR(150) NOT NULL,
        CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );

    INSERT INTO dbo.Customers (Name, Email, CreatedAt) VALUES
        ('Ada Okafor', 'ada.okafor@oliveclientmail.com', '2023-01-15'),
        ('Bello Musa', 'bello.musa@oliveclientmail.com', '2023-03-22'),
        ('Chidinma Eze', 'chidinma.eze@oliveclientmail.com', '2023-05-09');
END
GO
