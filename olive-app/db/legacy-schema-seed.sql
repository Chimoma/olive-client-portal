-- ---------------------------------------------------------------------------
-- Legacy database schema and seed data. Run this against
-- olive-legacy-db-instance BEFORE running the DMS migration task, so there
-- is real data for DMS to migrate into olive-db-instance.
--
-- Usage:
--   sqlcmd -S <olive-legacy-db endpoint> -U olive_admin -P <password> -i legacy-schema-seed.sql
-- ---------------------------------------------------------------------------

IF DB_ID('olive_legacy') IS NULL
    CREATE DATABASE olive_legacy;
GO

USE olive_legacy;
GO

IF OBJECT_ID('dbo.Customers', 'U') IS NOT NULL
    DROP TABLE dbo.Customers;
GO

CREATE TABLE dbo.Customers (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    Email NVARCHAR(150) NOT NULL,
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

INSERT INTO dbo.Customers (Name, Email, CreatedAt) VALUES
    ('Ada Okafor',      'ada.okafor@oliveclientmail.com',      '2023-01-15'),
    ('Bello Musa',      'bello.musa@oliveclientmail.com',      '2023-03-22'),
    ('Chidinma Eze',    'chidinma.eze@oliveclientmail.com',    '2023-05-09'),
    ('David Adeyemi',   'david.adeyemi@oliveclientmail.com',   '2023-07-30'),
    ('Efe Ighodalo',    'efe.ighodalo@oliveclientmail.com',    '2023-09-11'),
    ('Fatima Bello',    'fatima.bello@oliveclientmail.com',    '2024-01-04'),
    ('Gbenga Adisa',    'gbenga.adisa@oliveclientmail.com',    '2024-02-18'),
    ('Halima Sule',     'halima.sule@oliveclientmail.com',     '2024-04-06'),
    ('Ibrahim Yusuf',   'ibrahim.yusuf@oliveclientmail.com',   '2024-06-25'),
    ('Joy Nwachukwu',   'joy.nwachukwu@oliveclientmail.com',   '2024-08-13');
GO

SELECT COUNT(*) AS SeededCustomerRows FROM dbo.Customers;
GO
