/*
Project: Bank of America deposit market share in Arkansas campus counties
Stage 1: Creating the project database and the staging schema
*/

USE master;
GO

-- DB_ID returns NULL when no database has that name, so the check is safe to repeat.
IF DB_ID('ArkansasBankStudy') IS NULL
    CREATE DATABASE ArkansasBankStudy;
GO

-- Switching into the new database so every command below runs inside it.
USE ArkansasBankStudy;
GO

-- Creating the staging schema (a labeled folder for raw landing tables).
-- SCHEMA_ID returns NULL when the schema does not exist yet.
-- CREATE SCHEMA must be the only statement in its batch, so EXEC runs it as a separate text command and keeps the IF check working.
IF SCHEMA_ID('stg') IS NULL
    EXEC('CREATE SCHEMA stg');
GO

-- Quick proof that the setup worked. 
SELECT DB_NAME() AS current_database;
SELECT name AS schema_name FROM sys.schemas WHERE name = 'stg';
GO

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 2a: Creating the raw staging table with the first 7 columns.  The 7 columns are the mandatory FDIC columns that identify one branch in one year.
USE ArkansasBankStudy;
GO

-- If the table already exists, drop it so this script can be run again.
-- WARNING: dropping deletes any data inside, so only run this before loading files.
IF OBJECT_ID('stg.SOD_Raw', 'U') IS NOT NULL
    DROP TABLE stg.SOD_Raw;
GO

CREATE TABLE stg.SOD_Raw (
   
    [YEAR]      VARCHAR(10),  -- Snapshot year. Longest value in the files is 4 characters. Square brackets around the name keep SQL Server from confusing it with its YEAR function.
    CERT        VARCHAR(10), -- FDIC certificate number, the bank key (Bank of America is 3510). Longest is 5.
    NAMEFULL    VARCHAR(150),   -- Full legal bank name. Longest is 58 characters, so 150 leaves lots of room.
    ADDRESBR    VARCHAR(150),    -- Branch street address. Longest is 55 characters.
    BRNUM       VARCHAR(10),   -- Branch number within one bank. Not unique across banks. Longest is 4.
    UNINUMBR    VARCHAR(15),   -- FDIC unique branch ID. Blank for some branches in 2010 only (66 rows), which is fine in a text column. Longest is 6 characters.
    STALPBR     VARCHAR(5)     -- Branch state abbreviation. Always AR in the raw files. Longest is 2.
);
GO

-- Proof check: list the columns SQL Server just created, in order.
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'stg' AND TABLE_NAME = 'SOD_Raw'
ORDER BY ORDINAL_POSITION;
GO

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 2b: Adding columns 8 to 14 (bank level fields) to the staging table.
-- ALTER TABLE ... ADD appends new columns after the existing ones, so the table order keeps matching the CSV file order.
USE ArkansasBankStudy;
GO

ALTER TABLE stg.SOD_Raw ADD
   
    ASSET       VARCHAR(20),   -- Total assets of the bank, in thousands of dollars. Longest value is 10.
    BKCLASS     VARCHAR(10),   -- Institution class code, such as a national bank or a state bank. Longest is 2.
    CITY        VARCHAR(60),   -- City of the bank's headquarters, not the branch. Longest is 17.
    DENOVO      VARCHAR(5),    -- New bank flag (1 means a newly chartered bank). Longest is 1.
    DEPSUM      VARCHAR(20),   -- The bank's total deposits. In 2026 it is filled only on the main office row, so never use it for market share. Longest is 8.
    RSSDID      VARCHAR(15),   -- Federal Reserve ID for the bank. A join key to other datasets. Longest is 7.
    STALP       VARCHAR(5);    -- State abbreviation of the bank's headquarters. Useful for spotting out of state banks. Longest is 2.
GO

-- Proof check: the table should now have 14 columns, ending with STALP.
SELECT ORDINAL_POSITION, COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'stg' AND TABLE_NAME = 'SOD_Raw'
ORDER BY ORDINAL_POSITION;
GO

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 2c: Adding columns 15 to 29 (branch level fields) to the staging table.
-- Order matches the CSV file, which the bulk load will rely on.
USE ArkansasBankStudy;
GO

ALTER TABLE stg.SOD_Raw ADD
  
    BKMO                    VARCHAR(5),    -- Main office flag (1 means the main office of the bank). Longest is 1.
    BRSERTYP                VARCHAR(10),    -- Branch service type code. Longest is 2.
    CITYBR                  VARCHAR(80),    -- City where the branch sits, as reported by the bank. Longest is 25.
    CNTYNAMB                VARCHAR(60),    -- County name of the branch. Longest is 12.
    DEPSUMBR                VARCHAR(20),    -- Branch deposits .in thousands of dollars, which makes it the market share column.
    MSABR                   VARCHAR(10),    -- Metropolitan area code. 0 means no metro area. Longest is 5.  
    MSANAMB                 VARCHAR(150),  -- Metropolitan area name. Blank for many rural branches. Longest is 40
    NAMEBR                  VARCHAR(200),      -- Branch name. Longest is 63 characters.
    SIMS_ACQUIRED_DATE      VARCHAR(40),   -- Date the branch joined its current bank, often through a merger.  Blank for many branches. Longest is 22, so a time may be attached.
    SIMS_ESTABLISHED_DATE   VARCHAR(40),    -- Date the branch was first opened. Same text format as above.
    SIMS_LATITUDE           VARCHAR(40),   -- Branch latitude as text. Blank for some older branches. Longest is 16
    SIMS_LONGITUDE          VARCHAR(40),   -- Branch longitude as text. Longest is 17.
    STCNTYBR                VARCHAR(10),    -- State plus county FIPS code. The leading zero is already missing in the file, so values have 4 digits. After padding, it becomes the county join key.
    STNAMEBR                VARCHAR(40),   -- State name of the branch. Longest is 8.
    ZIPBR                   VARCHAR(15);   -- Five digit ZIP code of the branch.
GO

-- Proof check: the table should now have 29 columns, ending with ZIPBR.
SELECT ORDINAL_POSITION, COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'stg' AND TABLE_NAME = 'SOD_Raw'
ORDER BY ORDINAL_POSITION;
GO

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 2d: Adding the last 3 columns (positions 30 to 32), the holding company fields.
-- After this step the table has all 32 columns, in the same order as the CSV files.
USE ArkansasBankStudy;
GO

ALTER TABLE stg.SOD_Raw ADD
    
    HCTMULT     VARCHAR(10),  -- Flag for a multi bank holding company. Text values, longest is 4 characters.
    NAMEHCR     VARCHAR(200),    -- Name of the top holding company. Blank when the bank has none. Longest value is 68 characters.
    RSSDHCR     VARCHAR(15);   -- Federal Reserve ID of the top holding company. 0 when there is none. Longest is 7 characters. Join key for holding company roll ups.
GO

-- Proof check 1: the table should now have exactly 32 columns.
SELECT COUNT(*) AS column_count
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'stg' AND TABLE_NAME = 'SOD_Raw';
GO

-- Proof check 2: the last rows of the column list should be 30, 31, and 32.
SELECT ORDINAL_POSITION, COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'stg' AND TABLE_NAME = 'SOD_Raw'
ORDER BY ORDINAL_POSITION;
GO

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 3a: Loading all 17 yearly files (2010 to 2026) into the staging table.
USE ArkansasBankStudy;
GO

DECLARE @folder NVARCHAR(260) = N'C:\Bank of America\Raw Data\'; --- Folder that holds the CSV files. 
DECLARE @year    INT = 2010;      -- first year to load
DECLARE @file    NVARCHAR(400);   -- full path of the current file
DECLARE @rowterm NVARCHAR(10);    -- how rows end in the current file
DECLARE @sql     NVARCHAR(MAX);   -- the BULK INSERT command, built as text

-- Starting from an empty table so a rerun never doubles the rows.
TRUNCATE TABLE stg.SOD_Raw;

WHILE @year <= 2026               -- repeat once per year, 2010 through 2026
BEGIN
    -- Building the file name, such as C:\Bank of America\Raw Data\SOD_CustomDownload_2010_06_30.csv
    SET @file = @folder + N'SOD_CustomDownload_' + CAST(@year AS NVARCHAR(4)) + N'_06_30.csv';

    -- 2010 to 2025 files end each row with a line feed only (hex 0a).
    -- The 2026 file ends each row with a carriage return plus a line feed (hex 0d0a).
    SET @rowterm = CASE WHEN @year = 2026 THEN N'0x0d0a' ELSE N'0x0a' END;

    -- The progress shows in the Messages tab, so a failure points to the exact file.
    PRINT N'Loading ' + @file + N' with row ending ' + @rowterm;

    -- Options: CSV quoting rules, skip the header, Unicode text,
    -- commas between values, and the row ending chosen above.
    SET @sql = N'BULK INSERT stg.SOD_Raw FROM ''' + @file + N''' WITH ('
             + N'FORMAT = ''CSV'', FIELDQUOTE = ''"'', FIRSTROW = 2, '
             + N'CODEPAGE = ''65001'', FIELDTERMINATOR = '','', '
             + N'ROWTERMINATOR = ''' + @rowterm + N''');';

    EXEC sys.sp_executesql @sql; 

    SET @year = @year + 1;        -- moving to the next year
END;
GO

 -- Check 1: expect 23057 rows in total.
SELECT COUNT(*) AS total_rows FROM stg.SOD_Raw; 

-- Check 2: compare each year's row count with the count from your files. Every status should say OK.
WITH expected AS (                                                      
    SELECT * FROM (VALUES
        ('2010',1483),('2011',1484),('2012',1447),('2013',1442),('2014',1388),
        ('2015',1365),('2016',1354),('2017',1346),('2018',1345),('2019',1334),
        ('2020',1330),('2021',1294),('2022',1286),('2023',1286),('2024',1286),
        ('2025',1291),('2026',1296)
    ) AS e(yr, expected_rows)
),
actual AS (
    SELECT [YEAR] AS yr, COUNT(*) AS actual_rows
    FROM stg.SOD_Raw
    GROUP BY [YEAR]
)
SELECT e.yr, e.expected_rows, a.actual_rows,
       CASE WHEN a.actual_rows = e.expected_rows THEN 'OK' ELSE 'CHECK' END AS status
FROM expected e
LEFT JOIN actual a ON a.yr = e.yr
ORDER BY e.yr;

-- Check 3: expect 0. A nonzero count means a stray character, such as a hidden carriage return, is stuck to the last column.
SELECT COUNT(*) AS bad_rssdhcr FROM stg.SOD_Raw WHERE RSSDHCR LIKE '%[^0-9]%';

-- Check 4: expect 0. Any other year would mean a wrong file was loaded.
SELECT COUNT(*) AS rows_outside_study FROM stg.SOD_Raw
WHERE [YEAR] NOT BETWEEN '2010' AND '2026';

-- Check 5: Bank of America in 2026. Expect 16 rows and 6211181 deposits
-- (thousands of dollars), matching the calculation from the raw file.
-- TRY_CAST makes the text a number for this sum only. The column stays text.
SELECT COUNT(*) AS boa_rows,
       SUM(TRY_CAST(DEPSUMBR AS BIGINT)) AS boa_deposits_thousands
FROM stg.SOD_Raw
WHERE CERT = '3510' AND [YEAR] = '2026';

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 4a: profiling the raw staging table before cleaning anything.
USE ArkansasBankStudy;
GO

-- Check 1: how long are the county codes? The FDIC dropped the leading zero,
-- so I expect length 4 on every row. 
SELECT LEN(STCNTYBR) AS code_length, COUNT(*) AS row_count
FROM stg.SOD_Raw
GROUP BY LEN(STCNTYBR)
ORDER BY code_length;

-- Check 2: blank branch IDs by year. 
-- A blank can be stored as NULL or as empty text, so the first column counts
-- NULLs and the second counts empty text. Both matter for the cleaning step.
SELECT [YEAR],
       SUM(CASE WHEN UNINUMBR IS NULL THEN 1 ELSE 0 END) AS null_uninumbr,
       SUM(CASE WHEN UNINUMBR = '' THEN 1 ELSE 0 END)    AS empty_text_uninumbr
FROM stg.SOD_Raw
GROUP BY [YEAR]
ORDER BY [YEAR];
GO

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 4b: Building the clean, typed table from the raw staging table.
-- The raw table stg.SOD_Raw is only read here and never changed.
USE ArkansasBankStudy;
GO

-- Create a schema (folder) called cln for cleaned objects.
IF SCHEMA_ID('cln') IS NULL
    EXEC('CREATE SCHEMA cln');
GO

-- The cln.SOD_Branch table is derived data, so it is safe to drop and rebuild at any time.
IF OBJECT_ID('cln.SOD_Branch', 'U') IS NOT NULL
    DROP TABLE cln.SOD_Branch;
GO

-- NULLIF(LTRIM(RTRIM(x)), '') trims spaces and turns empty text into NULL,
-- so NULL and empty text are treated the same way everywhere below.
SELECT
    -- Identity columns
    TRY_CAST([YEAR] AS INT)                                AS sod_year,
    TRY_CAST(CERT AS INT)                                  AS cert,
    NULLIF(LTRIM(RTRIM(NAMEFULL)), '')                     AS bank_name,
    TRY_CAST(BRNUM AS INT)                                 AS brnum,
    TRY_CAST(NULLIF(LTRIM(RTRIM(UNINUMBR)), '') AS INT)    AS uninumbr,

    -- Branch key: use the FDIC unique ID when it exists, otherwise build one
    -- from the bank number and branch number, such as C33538_2.
    CAST(CASE WHEN NULLIF(LTRIM(RTRIM(UNINUMBR)), '') IS NOT NULL
              THEN LTRIM(RTRIM(UNINUMBR))
              ELSE 'C' + LTRIM(RTRIM(CERT)) + '_' + LTRIM(RTRIM(BRNUM))
         END AS VARCHAR(30))                               AS branch_key,

    -- Flag that shows which kind of key each row got.
    CAST(CASE WHEN NULLIF(LTRIM(RTRIM(UNINUMBR)), '') IS NOT NULL
              THEN 'FDIC_ID' ELSE 'CERT_BRNUM'
         END AS VARCHAR(12))                               AS key_source,

    -- Branch location
    NULLIF(LTRIM(RTRIM(NAMEBR)), '')                       AS branch_name,
    NULLIF(LTRIM(RTRIM(ADDRESBR)), '')                     AS branch_address,
    NULLIF(LTRIM(RTRIM(CITYBR)), '')                       AS branch_city,
    NULLIF(LTRIM(RTRIM(CNTYNAMB)), '')                     AS county_name,

    -- County code padded to five digits: 5119 becomes 05119.
    CAST(RIGHT('00000' + LTRIM(RTRIM(STCNTYBR)), 5) AS CHAR(5)) AS county_fips,
    NULLIF(LTRIM(RTRIM(ZIPBR)), '')                        AS zip,

    -- Branch deposits in thousands of dollars: the market share column.
    TRY_CAST(DEPSUMBR AS BIGINT)                           AS deposits_k,

    -- Branch details
    NULLIF(LTRIM(RTRIM(BKMO)), '')                         AS main_office_flag,
    NULLIF(LTRIM(RTRIM(BRSERTYP)), '')                     AS service_type,
    NULLIF(LTRIM(RTRIM(MSABR)), '')                        AS msa_code,
    NULLIF(LTRIM(RTRIM(MSANAMB)), '')                      AS msa_name,

    -- Dates arrive as text such as 9/14/2009. Keep only the text before the first
    -- space (in case a time is attached), then read it as month/day/year (style 101).
    TRY_CONVERT(DATE,
        LEFT(NULLIF(LTRIM(RTRIM(SIMS_ESTABLISHED_DATE)), ''),
             CHARINDEX(' ', NULLIF(LTRIM(RTRIM(SIMS_ESTABLISHED_DATE)), '') + ' ') - 1),
        101)                                               AS established_date,
    TRY_CONVERT(DATE,
        LEFT(NULLIF(LTRIM(RTRIM(SIMS_ACQUIRED_DATE)), ''),
             CHARINDEX(' ', NULLIF(LTRIM(RTRIM(SIMS_ACQUIRED_DATE)), '') + ' ') - 1),
        101)                                               AS acquired_date,

    -- Map coordinates. DECIMAL(11,8) keeps all the decimals in the file.
    TRY_CAST(NULLIF(LTRIM(RTRIM(SIMS_LATITUDE)), '')  AS DECIMAL(11,8)) AS latitude,
    TRY_CAST(NULLIF(LTRIM(RTRIM(SIMS_LONGITUDE)), '') AS DECIMAL(11,8)) AS longitude,

    -- Bank level context. Bank deposits in DEPSUM are filled only on some rows,
    -- so never use that column for market share.
    TRY_CAST(ASSET AS BIGINT)                              AS bank_assets_k,
    NULLIF(LTRIM(RTRIM(BKCLASS)), '')                      AS bank_class,
    NULLIF(LTRIM(RTRIM(CITY)), '')                         AS bank_hq_city,
    NULLIF(LTRIM(RTRIM(STALP)), '')                        AS bank_hq_state,
    TRY_CAST(DEPSUM AS BIGINT)                             AS bank_total_deposits_k,
    TRY_CAST(NULLIF(LTRIM(RTRIM(RSSDID)), '') AS INT)      AS rssd_id,
    NULLIF(LTRIM(RTRIM(DENOVO)), '')                       AS denovo_flag,

    -- Holding company fields. A holding company ID of 0 means there is none.
    NULLIF(LTRIM(RTRIM(NAMEHCR)), '')                      AS holding_company,
    TRY_CAST(NULLIF(LTRIM(RTRIM(RSSDHCR)), '') AS INT)     AS holding_company_rssd,
    NULLIF(LTRIM(RTRIM(HCTMULT)), '')                      AS multi_bank_holding
INTO cln.SOD_Branch
FROM stg.SOD_Raw;
GO

-- Check 1: expect 23057 rows, the same as staging.
SELECT COUNT(*) AS clean_rows FROM cln.SOD_Branch;

-- Check 2: conversion failures. Every count should be 0.
SELECT SUM(CASE WHEN sod_year    IS NULL THEN 1 ELSE 0 END) AS bad_year,
       SUM(CASE WHEN cert        IS NULL THEN 1 ELSE 0 END) AS bad_cert,
       SUM(CASE WHEN brnum       IS NULL THEN 1 ELSE 0 END) AS bad_brnum,
       SUM(CASE WHEN deposits_k  IS NULL THEN 1 ELSE 0 END) AS bad_deposits,
       SUM(CASE WHEN county_fips IS NULL THEN 1 ELSE 0 END) AS bad_county
FROM cln.SOD_Branch;

-- Check 3: county codes. Expect only the 05 prefix, with the lowest code near 05001
-- and the highest near 05149.
SELECT LEFT(county_fips, 2) AS state_prefix, COUNT(*) AS row_count,
       MIN(county_fips) AS lowest_code, MAX(county_fips) AS highest_code
FROM cln.SOD_Branch
GROUP BY LEFT(county_fips, 2);

-- Check 4: branch keys. Expect 66 CERT_BRNUM rows, all in 2010, and the rest FDIC_ID.
SELECT sod_year, key_source, COUNT(*) AS row_count
FROM cln.SOD_Branch
WHERE key_source = 'CERT_BRNUM' OR sod_year = 2026
GROUP BY sod_year, key_source
ORDER BY sod_year, key_source;

-- Check 5: duplicate keys within one year. Expect 0 rows returned.
SELECT sod_year, branch_key, COUNT(*) AS copies
FROM cln.SOD_Branch
GROUP BY sod_year, branch_key
HAVING COUNT(*) > 1;

-- Check 6: Bank of America in 2026. Expect 16 rows and 6211181, same as before.
SELECT COUNT(*) AS boa_rows, SUM(deposits_k) AS boa_deposits_thousands
FROM cln.SOD_Branch
WHERE cert = 3510 AND sod_year = 2026;

-- Check 7: date conversion. Each pair of numbers should match, which proves
-- no date text failed to convert.
SELECT
    (SELECT COUNT(*) FROM stg.SOD_Raw
      WHERE NULLIF(LTRIM(RTRIM(SIMS_ESTABLISHED_DATE)), '') IS NOT NULL) AS raw_established,
    (SELECT COUNT(established_date) FROM cln.SOD_Branch)                 AS clean_established,
    (SELECT COUNT(*) FROM stg.SOD_Raw
      WHERE NULLIF(LTRIM(RTRIM(SIMS_ACQUIRED_DATE)), '') IS NOT NULL)    AS raw_acquired,
    (SELECT COUNT(acquired_date) FROM cln.SOD_Branch)                    AS clean_acquired;
GO

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 4c: exploratory data analysis (EDA) on cln.SOD_Branch.
-- Everything in 4c only READS data. Nothing is changed here.
-- Run 4c BEFORE 4d, so you see the mess before the cleaning removes it.
USE ArkansasBankStudy;
GO

-- ============================================================
-- Part 1: what does the data look like?
-- ============================================================

-- 1a: one row per year. LAG looks at the previous year's row so we can see change.
-- NULLIF(...,0) stops a divide by zero error if a prior value is ever 0.
WITH yr AS (
    SELECT sod_year,
           COUNT(*)                   AS branch_rows,
           COUNT(DISTINCT cert)       AS banks,
           COUNT(DISTINCT county_fips) AS counties,
           SUM(deposits_k)            AS deposits_k
    FROM cln.SOD_Branch
    GROUP BY sod_year
)
SELECT sod_year, branch_rows, banks, counties, deposits_k,
       branch_rows - LAG(branch_rows) OVER (ORDER BY sod_year) AS rows_vs_prior_year,
       CAST(100.0 * (deposits_k - LAG(deposits_k) OVER (ORDER BY sod_year))
            / NULLIF(LAG(deposits_k) OVER (ORDER BY sod_year), 0) AS DECIMAL(6,1)) AS deposit_growth_pct
FROM yr
ORDER BY sod_year;

-- 1b: the single largest branch in each year.
-- ROW_NUMBER restarts at 1 for every year (PARTITION BY) and ranks by deposits.
WITH ranked AS (
    SELECT sod_year, bank_name, branch_city, deposits_k,
           ROW_NUMBER() OVER (PARTITION BY sod_year ORDER BY deposits_k DESC) AS rn
    FROM cln.SOD_Branch
)
SELECT sod_year, bank_name, branch_city, deposits_k
FROM ranked
WHERE rn = 1
ORDER BY sod_year;

-- 1c: service types, with how many rows report zero deposits.
SELECT service_type,
       COUNT(*)                                          AS row_count,
       SUM(CASE WHEN deposits_k = 0 THEN 1 ELSE 0 END)   AS zero_deposit_rows,
       SUM(deposits_k)                                   AS deposits_k
FROM cln.SOD_Branch
GROUP BY service_type
ORDER BY row_count DESC;

-- 1d: missing values by year. Each column counts the NULLs in that field.
-- Read it across years: a field that jumps to all NULL in one year is a data change.
SELECT sod_year,
       SUM(CASE WHEN branch_name      IS NULL THEN 1 ELSE 0 END) AS null_branch_name,
       SUM(CASE WHEN branch_address   IS NULL THEN 1 ELSE 0 END) AS null_address,
       SUM(CASE WHEN branch_city      IS NULL THEN 1 ELSE 0 END) AS null_city,
       SUM(CASE WHEN zip              IS NULL THEN 1 ELSE 0 END) AS null_zip,
       SUM(CASE WHEN latitude         IS NULL THEN 1 ELSE 0 END) AS null_latitude,
       SUM(CASE WHEN established_date IS NULL THEN 1 ELSE 0 END) AS null_established,
       SUM(CASE WHEN msa_code         IS NULL THEN 1 ELSE 0 END) AS null_msa,
       SUM(CASE WHEN holding_company  IS NULL THEN 1 ELSE 0 END) AS null_holding_co
FROM cln.SOD_Branch
GROUP BY sod_year
ORDER BY sod_year;
GO

-- ============================================================
-- Part 2: duplicate and consistency checks (before cleaning)
-- ============================================================

-- Check 1: duplicate branch_key inside one year. Expect 0 rows.
SELECT sod_year, branch_key, COUNT(*) AS copies
FROM cln.SOD_Branch
GROUP BY sod_year, branch_key
HAVING COUNT(*) > 1;

-- Check 2: fully identical rows (same values in every key field). Expect 0 rows.
SELECT sod_year, branch_key, cert, branch_name, branch_address, branch_city,
       zip, county_fips, deposits_k, COUNT(*) AS copies
FROM cln.SOD_Branch
GROUP BY sod_year, branch_key, cert, branch_name, branch_address, branch_city,
         zip, county_fips, deposits_k
HAVING COUNT(*) > 1;

-- Check 3: different branch_keys but same bank, year, address and city.
-- Shared addresses are NOT errors by themselves (a bank can run two offices in one building),
-- so we flag them and keep them. Expect 105 groups and 248 rows.
WITH g AS (
    SELECT sod_year, cert, branch_address, branch_city, COUNT(*) AS rows_in_group
    FROM cln.SOD_Branch
    WHERE branch_address IS NOT NULL
    GROUP BY sod_year, cert, branch_address, branch_city
    HAVING COUNT(*) > 1
)
SELECT COUNT(*) AS groups_found, SUM(rows_in_group) AS rows_involved
FROM g;

-- Check 4: same test for Bank of America only. Expect 0 groups.
SELECT sod_year, branch_address, branch_city, COUNT(*) AS copies
FROM cln.SOD_Branch
WHERE cert = 3510 AND branch_address IS NOT NULL
GROUP BY sod_year, branch_address, branch_city
HAVING COUNT(*) > 1;

-- Check 5: zero deposit rows. Expect 1178 rows, about 5.11 percent.
SELECT SUM(CASE WHEN deposits_k = 0 THEN 1 ELSE 0 END) AS zero_deposit_rows,
       CAST(100.0 * SUM(CASE WHEN deposits_k = 0 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS pct_of_rows
FROM cln.SOD_Branch;

-- Check 6: banks whose name changed over the years (mergers, renames, case).
-- Expect 169 banks in total and 49 with more than one name.
SELECT COUNT(*) AS banks,
       SUM(CASE WHEN names > 1 THEN 1 ELSE 0 END) AS banks_with_name_changes
FROM (SELECT cert, COUNT(DISTINCT bank_name) AS names
      FROM cln.SOD_Branch
      GROUP BY cert) t;

-- Check 7: double spaces inside text. Expect 8 addresses and 24 branch names.
SELECT SUM(CASE WHEN branch_address LIKE '%  %' THEN 1 ELSE 0 END) AS addresses_with_double_space,
       SUM(CASE WHEN branch_name    LIKE '%  %' THEN 1 ELSE 0 END) AS names_with_double_space
FROM cln.SOD_Branch;

-- Check 8: city names written in more than one way (De Queen versus DeQueen).
-- We compare the names after removing spaces, periods and apostrophes and ignoring case.
-- Expect 6 rows.
SELECT UPPER(REPLACE(REPLACE(REPLACE(branch_city, ' ', ''), '.', ''), '''', '')) AS city_key,
       branch_city, COUNT(*) AS row_count
FROM cln.SOD_Branch
WHERE UPPER(REPLACE(REPLACE(REPLACE(branch_city, ' ', ''), '.', ''), '''', ''))
      IN (SELECT UPPER(REPLACE(REPLACE(REPLACE(branch_city, ' ', ''), '.', ''), '''', ''))
          FROM cln.SOD_Branch
          GROUP BY UPPER(REPLACE(REPLACE(REPLACE(branch_city, ' ', ''), '.', ''), '''', ''))
          HAVING COUNT(DISTINCT branch_city) > 1)
GROUP BY branch_city
ORDER BY city_key, branch_city;
GO

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 4d: Standardizing the text and adding helper columns to cln.SOD_Branch.
-- Stage 4d CHANGES cln.SOD_Branch. It never touches stg.SOD_Raw.
-- If you rebuild cln.SOD_Branch with Stage 4b, rerun 4d and 4e after it.
USE ArkansasBankStudy;
GO

-- Drop the foreign key first (if Stage 4e created it), because a table
-- that another table points to cannot be dropped or rebuilt.
IF OBJECT_ID('cln.FK_SOD_Bank', 'F') IS NOT NULL
    ALTER TABLE cln.SOD_Branch DROP CONSTRAINT FK_SOD_Bank;
GO

-- Step 1: collapse repeated spaces into one space.
-- The trick: turn every space into '<>', delete every '><' (that removes the
-- pairs in the middle of a run), then turn the leftover '<>' back into one space.
UPDATE cln.SOD_Branch
SET branch_address = REPLACE(REPLACE(REPLACE(branch_address, ' ', '<>'), '><', ''), '<>', ' ')
WHERE branch_address LIKE '%  %';

UPDATE cln.SOD_Branch
SET branch_name = REPLACE(REPLACE(REPLACE(branch_name, ' ', '<>'), '><', ''), '<>', ' ')
WHERE branch_name LIKE '%  %';

UPDATE cln.SOD_Branch
SET bank_name = REPLACE(REPLACE(REPLACE(bank_name, ' ', '<>'), '><', ''), '<>', ' ')
WHERE bank_name LIKE '%  %';

-- Step 2: one spelling for the three cities that appear in more than one form.
-- The comparison ignores spaces and case, so every variant is caught.
UPDATE cln.SOD_Branch
SET branch_city = 'De Queen'
WHERE UPPER(REPLACE(branch_city, ' ', '')) = 'DEQUEEN' AND branch_city <> 'De Queen';

UPDATE cln.SOD_Branch
SET branch_city = 'De Witt'
WHERE UPPER(REPLACE(branch_city, ' ', '')) = 'DEWITT' AND branch_city <> 'De Witt';

UPDATE cln.SOD_Branch
SET branch_city = 'White Hall'
WHERE UPPER(REPLACE(branch_city, ' ', '')) = 'WHITEHALL' AND branch_city <> 'White Hall';
GO

-- Step 3: a lookup table with ONE current name per bank (cert).
-- ROW_NUMBER ranks each bank's rows from newest year to oldest; rn = 1 is the latest name.
IF OBJECT_ID('cln.Bank', 'U') IS NOT NULL
    DROP TABLE cln.Bank;
GO

WITH latest AS (
    SELECT cert, bank_name,
           ROW_NUMBER() OVER (PARTITION BY cert ORDER BY sod_year DESC) AS rn
    FROM cln.SOD_Branch
)
SELECT CAST(cert AS INT) AS cert,
       CAST(bank_name AS VARCHAR(200)) AS bank_name
INTO cln.Bank
FROM latest
WHERE rn = 1;
GO

-- A bank must be unique and never empty, so cert becomes the primary key.
-- The NOT NULL change and the key now sit in separate batches.
-- SQL Server reads a whole batch before running it, so in one batch it still
-- sees cert as nullable when it checks the key (Msg 8111).
ALTER TABLE cln.Bank ALTER COLUMN cert INT NOT NULL;
GO

ALTER TABLE cln.Bank ADD CONSTRAINT PK_Bank PRIMARY KEY (cert);
GO

-- Step 4: fix names that arrive in ALL CAPS.
-- COLLATE Latin1_General_CS_AS makes the comparison case sensitive.
-- Without it, SQL Server treats 'Peoples Bank' and 'PEOPLES BANK' as the same text
-- and the WHERE would match rows that are already correct.
UPDATE cln.Bank SET bank_name = 'Community State Bank'
WHERE bank_name COLLATE Latin1_General_CS_AS = 'COMMUNITY STATE BANK';

UPDATE cln.Bank SET bank_name = 'Encore Bank'
WHERE bank_name COLLATE Latin1_General_CS_AS = 'ENCORE BANK';

UPDATE cln.Bank SET bank_name = 'Peoples Bank'
WHERE bank_name COLLATE Latin1_General_CS_AS = 'PEOPLES BANK';
GO

-- Step 5: three helper columns. The column must exist before an UPDATE can use it,
-- so each ALTER and its UPDATE sit in separate batches (separated by GO).
IF COL_LENGTH('cln.SOD_Branch', 'bank_name_std') IS NULL
    ALTER TABLE cln.SOD_Branch ADD bank_name_std VARCHAR(200) NULL;
IF COL_LENGTH('cln.SOD_Branch', 'is_zero_deposit') IS NULL
    ALTER TABLE cln.SOD_Branch ADD is_zero_deposit BIT NULL;
IF COL_LENGTH('cln.SOD_Branch', 'records_at_address') IS NULL
    ALTER TABLE cln.SOD_Branch ADD records_at_address INT NULL;
GO

-- bank_name_std: the one current name for the bank, pulled from cln.Bank.
UPDATE b
SET b.bank_name_std = k.bank_name
FROM cln.SOD_Branch b
JOIN cln.Bank k ON k.cert = b.cert;

-- is_zero_deposit: 1 when the branch reports zero deposits, so reports can filter it.
UPDATE cln.SOD_Branch
SET is_zero_deposit = CASE WHEN deposits_k = 0 THEN 1 ELSE 0 END;

-- records_at_address: how many rows share the same bank, year, address and city.
-- A value above 1 means a shared building, flagged and kept, not deleted.
WITH c AS (
    SELECT sod_year, branch_key,
           COUNT(*) OVER (PARTITION BY sod_year, cert, branch_address, branch_city) AS n
    FROM cln.SOD_Branch
)
UPDATE b
SET b.records_at_address = c.n
FROM cln.SOD_Branch b
JOIN c ON c.sod_year = b.sod_year AND c.branch_key = b.branch_key;
GO

-- ---------------- Proof checks for 4d ----------------

-- Check 1: row count unchanged. Expect 23057.
SELECT COUNT(*) AS clean_rows FROM cln.SOD_Branch;

-- Check 2: double spaces left. Expect 0 and 0.
SELECT SUM(CASE WHEN branch_address LIKE '%  %' THEN 1 ELSE 0 END) AS addresses_left,
       SUM(CASE WHEN branch_name    LIKE '%  %' THEN 1 ELSE 0 END) AS names_left
FROM cln.SOD_Branch;

-- Check 3: cities still spelled two ways. Expect 0 rows.
SELECT UPPER(REPLACE(branch_city, ' ', '')) AS city_key, COUNT(DISTINCT branch_city) AS spellings
FROM cln.SOD_Branch
GROUP BY UPPER(REPLACE(branch_city, ' ', ''))
HAVING COUNT(DISTINCT branch_city) > 1;

-- Check 4: every row has a standard bank name. Expect 0.
SELECT COUNT(*) AS rows_missing_std_name
FROM cln.SOD_Branch WHERE bank_name_std IS NULL;

-- Check 5: one name per bank. Both numbers must match.
SELECT (SELECT COUNT(*) FROM cln.Bank)                   AS banks_in_lookup,
       (SELECT COUNT(DISTINCT cert) FROM cln.SOD_Branch) AS banks_in_branch_table;

-- Check 6: helper columns. Expect 1178 zero deposit rows and 248 rows sharing an address.
SELECT SUM(CAST(is_zero_deposit AS INT)) AS zero_deposit_rows,
       SUM(CASE WHEN records_at_address > 1 THEN 1 ELSE 0 END) AS rows_sharing_address
FROM cln.SOD_Branch;

-- Check 7: Bank of America 2026 must not move. Expect 16 rows and 6211181.
SELECT COUNT(*) AS boa_rows, SUM(deposits_k) AS boa_deposits_thousands
FROM cln.SOD_Branch
WHERE cert = 3510 AND sod_year = 2026;
GO

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 4e: lock the rules into the table with keys.
-- A primary key means "no two rows may share this ID". A foreign key means
-- "every cert here must exist in cln.Bank". The database now enforces both.
USE ArkansasBankStudy;
GO

-- A key column cannot allow NULL, so tighten the three columns first.
ALTER TABLE cln.SOD_Branch ALTER COLUMN sod_year   INT         NOT NULL;
ALTER TABLE cln.SOD_Branch ALTER COLUMN branch_key VARCHAR(30) NOT NULL;
ALTER TABLE cln.SOD_Branch ALTER COLUMN cert       INT         NOT NULL;
GO

-- One row per branch per year.
ALTER TABLE cln.SOD_Branch
    ADD CONSTRAINT PK_SOD_Branch PRIMARY KEY (sod_year, branch_key);

-- Every branch row must point to a real bank.
ALTER TABLE cln.SOD_Branch
    ADD CONSTRAINT FK_SOD_Bank FOREIGN KEY (cert) REFERENCES cln.Bank (cert);
GO

-- Proof test: try to insert a duplicate and watch the database refuse it.
-- The insert runs inside a transaction that is rolled back, so no data changes.
BEGIN TRANSACTION;
BEGIN TRY
    INSERT INTO cln.SOD_Branch
    SELECT TOP 1 * FROM cln.SOD_Branch;   -- copy of an existing row = duplicate key
    PRINT 'PROBLEM: the duplicate was accepted. The primary key is not working.';
END TRY
BEGIN CATCH
    -- Expect error 2627 (violation of PRIMARY KEY), which is the success message here.
    PRINT 'GOOD: duplicate refused. Error ' + CAST(ERROR_NUMBER() AS VARCHAR(10))
          + ': ' + ERROR_MESSAGE();
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO

-- Final proof: row count and Bank of America must still match.
SELECT COUNT(*) AS clean_rows FROM cln.SOD_Branch;                      -- 23057
SELECT COUNT(*) AS boa_rows, SUM(deposits_k) AS boa_deposits_thousands
FROM cln.SOD_Branch WHERE cert = 3510 AND sod_year = 2026;               -- 16 and 6211181
GO

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 5a: build the lookup table of the 13 campus counties.

USE ArkansasBankStudy;
GO

-- Create the table only if it does not exist yet.
IF OBJECT_ID('cln.CampusCounty', 'U') IS NULL
    CREATE TABLE cln.CampusCounty (
        county_fips CHAR(5)      NOT NULL PRIMARY KEY,  -- five digit code, the join key
        county_name VARCHAR(40)  NOT NULL,              -- label for reports only
        campuses    VARCHAR(200) NOT NULL               -- campuses in the county
    );
GO

-- Insert each county only when its code is missing, so a rerun adds nothing twice.
INSERT INTO cln.CampusCounty (county_fips, county_name, campuses)
SELECT v.county_fips, v.county_name, v.campuses
FROM (VALUES
    ('05143', 'Washington',   'UA Fayetteville'),
    ('05119', 'Pulaski',      'UA Little Rock; UAMS; UA Pulaski Technical College'),
    ('05131', 'Sebastian',    'UA Fort Smith'),
    ('05069', 'Jefferson',    'UA Pine Bluff'),
    ('05043', 'Drew',         'UA Monticello'),
    ('05107', 'Phillips',     'Phillips Community College'),
    ('05057', 'Hempstead',    'UA Hope Texarkana'),
    ('05063', 'Independence', 'UA Batesville'),
    ('05133', 'Sevier',       'Cossatot Community College'),
    ('05029', 'Conway',       'UA Morrilton'),
    ('05113', 'Polk',         'UA Rich Mountain'),
    ('05123', 'St. Francis',  'UA East Arkansas'),
    ('05009', 'Boone',        'North Arkansas College')
) AS v (county_fips, county_name, campuses)
WHERE NOT EXISTS (SELECT 1 FROM cln.CampusCounty c WHERE c.county_fips = v.county_fips);
GO

-- Check 1: expect 13 rows.
SELECT COUNT(*) AS campus_counties FROM cln.CampusCounty;

-- Check 2: compare my county names with the names in the FDIC data for the same code.
-- Each county should appear once, with both names matching. A county that appears
-- twice means the FDIC spelled the name two ways across years, which is harmless
-- because we join by code.
SELECT c.county_fips,
       c.county_name AS my_name,
       d.county_name AS fdic_name
FROM cln.CampusCounty c
LEFT JOIN (SELECT DISTINCT county_fips, county_name FROM cln.SOD_Branch) d
       ON d.county_fips = c.county_fips
ORDER BY c.county_fips, d.county_name;

-- Check 3: sanity view of 2026. Every county should show branches and deposits,
-- and Pulaski (Little Rock) should be the largest. Deposits are in thousands of dollars.
SELECT c.county_name,
       COUNT(*)         AS branches,
       SUM(b.deposits_k) AS total_deposits_k
FROM cln.SOD_Branch b
JOIN cln.CampusCounty c ON c.county_fips = b.county_fips
WHERE b.sod_year = 2026
GROUP BY c.county_name
ORDER BY total_deposits_k DESC;
GO

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 5b: market share and rank views.
USE ArkansasBankStudy;
GO

-- View 1: one row per bank, county, and year, for ALL Arkansas counties.
-- Market share is calculated at the bank level (FDIC certificate number).
-- CREATE OR ALTER lets you run this script again without errors.
CREATE OR ALTER VIEW cln.vw_BankCountyYear AS
WITH bank_county AS (
    -- Step 1: add up each bank's branches within a county and year.
    SELECT sod_year,
           county_fips,
           MAX(county_name)   AS county_name,   -- one name per code, so MAX only picks it
           cert,
           MAX(bank_name_std) AS bank_name,     -- one current name per bank (from Stage 4d)
           COUNT(*)           AS branches,
           SUM(deposits_k)    AS deposits_k     -- thousands of dollars
    FROM cln.SOD_Branch
    GROUP BY sod_year, county_fips, cert
),
with_total AS (
    -- Step 2: put the county total on every row. The window sum adds up all banks
    -- in the same county and year without collapsing the rows.
    SELECT sod_year, county_fips, county_name, cert, bank_name, branches, deposits_k,
           SUM(deposits_k) OVER (PARTITION BY sod_year, county_fips) AS county_total_k
    FROM bank_county
)
-- Step 3: share and rank. NULLIF stops a divide by zero if a county total is 0.
SELECT sod_year, county_fips, county_name, cert, bank_name, branches,
       deposits_k, county_total_k,
       CAST(100.0 * deposits_k / NULLIF(county_total_k, 0) AS DECIMAL(7,3)) AS market_share_pct,
       RANK() OVER (PARTITION BY sod_year, county_fips
                    ORDER BY deposits_k DESC) AS deposit_rank   -- 1 is the largest bank
FROM with_total;
GO

-- View 2: Bank of America (certificate 3510) in the 13 campus counties, every year.
-- CROSS JOIN builds every county and year combination, and the LEFT JOIN fills in
-- Bank of America's numbers. Where it has no branch, branches and deposits
-- show 0 and the rank stays NULL.
CREATE OR ALTER VIEW cln.vw_BoA_CampusCounty AS
SELECT y.sod_year,
       c.county_fips,
       c.county_name,
       COALESCE(v.branches, 0)         AS boa_branches,
       COALESCE(v.deposits_k, 0)       AS boa_deposits_k,
       COALESCE(v.market_share_pct, 0) AS boa_share_pct,
       v.deposit_rank                  AS boa_rank
FROM cln.CampusCounty c
CROSS JOIN (SELECT DISTINCT sod_year FROM cln.SOD_Branch) y
LEFT JOIN cln.vw_BankCountyYear v
       ON v.sod_year    = y.sod_year
      AND v.county_fips = c.county_fips
      AND v.cert        = 3510;
GO

-- Check 1: expect 8733 rows (one per bank, county, and year).
SELECT COUNT(*) AS view_rows FROM cln.vw_BankCountyYear;

-- Check 2: shares in each county and year should add up to about 100.
-- Expect both numbers within 0.05 of 100.
SELECT MIN(total_share) AS lowest_total, MAX(total_share) AS highest_total
FROM (SELECT SUM(market_share_pct) AS total_share
      FROM cln.vw_BankCountyYear
      GROUP BY sod_year, county_fips) x;

-- Check 3: top 5 banks in Pulaski County, 2026. Bank of America should rank 2nd.
SELECT TOP 5 cert, bank_name, branches, deposits_k, county_total_k,
       market_share_pct, deposit_rank
FROM cln.vw_BankCountyYear
WHERE sod_year = 2026 AND county_fips = '05119'
ORDER BY deposit_rank;

-- Check 4: Bank of America in each campus county, 2010 versus 2026.
SELECT county_name, sod_year, boa_branches, boa_deposits_k, boa_share_pct, boa_rank
FROM cln.vw_BoA_CampusCounty
WHERE sod_year IN (2010, 2026)
ORDER BY county_name, sod_year;
GO

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 5c: Bank of America trend and share gainers in the campus counties.
USE ArkansasBankStudy;
GO

-- View: every bank's share in the first and last year, for the 13 campus counties.
-- FULL OUTER JOIN keeps banks that exist in only one of the two years
-- (a new entrant, or a bank that left), and COALESCE turns the missing side into 0.
CREATE OR ALTER VIEW cln.vw_ShareChange AS
WITH first_yr AS (SELECT MIN(sod_year) AS yr FROM cln.SOD_Branch),
     last_yr  AS (SELECT MAX(sod_year) AS yr FROM cln.SOD_Branch),
start_share AS (
    SELECT v.county_fips, v.county_name, v.cert, v.bank_name, v.market_share_pct
    FROM cln.vw_BankCountyYear v
    JOIN cln.CampusCounty c ON c.county_fips = v.county_fips   -- campus counties only
    WHERE v.sod_year = (SELECT yr FROM first_yr)
),
end_share AS (
    SELECT v.county_fips, v.county_name, v.cert, v.bank_name, v.market_share_pct
    FROM cln.vw_BankCountyYear v
    JOIN cln.CampusCounty c ON c.county_fips = v.county_fips
    WHERE v.sod_year = (SELECT yr FROM last_yr)
)
SELECT COALESCE(e.county_fips, s.county_fips) AS county_fips,
       COALESCE(e.county_name, s.county_name) AS county_name,
       COALESCE(e.cert,        s.cert)        AS cert,
       COALESCE(e.bank_name,   s.bank_name)   AS bank_name,   -- the latest name wins
       COALESCE(s.market_share_pct, 0)        AS share_start_pct,
       COALESCE(e.market_share_pct, 0)        AS share_end_pct,
       -- Change in percentage points, not percent. Going from 25 to 17.6 is minus 7.4 points.
       CAST(COALESCE(e.market_share_pct, 0) - COALESCE(s.market_share_pct, 0)
            AS DECIMAL(7,3))                  AS share_change_pts
FROM start_share s
FULL OUTER JOIN end_share e
       ON e.county_fips = s.county_fips AND e.cert = s.cert;
GO

-- Result 1: Bank of America by year in every campus county where it ever had a branch.
-- The subquery finds those counties, so nothing is typed by hand.
-- Expect 85 rows (5 counties times 17 years).
SELECT county_name, sod_year, boa_branches, boa_deposits_k, boa_share_pct, boa_rank
FROM cln.vw_BoA_CampusCounty
WHERE county_fips IN (SELECT county_fips
                      FROM cln.vw_BoA_CampusCounty
                      GROUP BY county_fips
                      HAVING MAX(boa_branches) > 0)
ORDER BY county_name, sod_year;

-- Result 2: Bank of America's own change in share, 2010 to 2026, by county.
SELECT county_name, share_start_pct, share_end_pct, share_change_pts
FROM cln.vw_ShareChange
WHERE cert = 3510
ORDER BY share_change_pts;

-- Result 3: the three biggest share gainers in each of those counties.
-- ROW_NUMBER numbers the banks from biggest gain to smallest inside each county.
WITH ranked AS (
    SELECT county_name, bank_name, share_start_pct, share_end_pct, share_change_pts,
           ROW_NUMBER() OVER (PARTITION BY county_fips
                              ORDER BY share_change_pts DESC) AS gain_rank
    FROM cln.vw_ShareChange
    WHERE county_fips IN (SELECT county_fips
                          FROM cln.vw_BoA_CampusCounty
                          GROUP BY county_fips
                          HAVING MAX(boa_branches) > 0)
)
SELECT county_name, gain_rank, bank_name, share_start_pct, share_end_pct, share_change_pts
FROM ranked
WHERE gain_rank <= 3
ORDER BY county_name, gain_rank;
GO

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 6a: statewide benchmark for Bank of America (certificate 3510).
USE ArkansasBankStudy;
GO

-- View 1: Bank of America across ALL of Arkansas, one row per year.
-- The rank must be calculated across every bank BEFORE we filter to Bank of America,
-- so the CTE ranks all banks and the final SELECT keeps only certificate 3510.
CREATE OR ALTER VIEW cln.vw_BoA_Statewide AS
WITH bank_state AS (
    -- Add up each bank's branches and deposits across the whole state and year.
    SELECT sod_year, cert,
           COUNT(*)        AS branches,
           SUM(deposits_k) AS deposits_k      -- thousands of dollars
    FROM cln.SOD_Branch
    GROUP BY sod_year, cert
),
with_total AS (
    SELECT sod_year, cert, branches, deposits_k,
           SUM(deposits_k) OVER (PARTITION BY sod_year) AS state_total_k,
           RANK() OVER (PARTITION BY sod_year ORDER BY deposits_k DESC) AS state_rank
    FROM bank_state
)
SELECT sod_year,
       branches    AS boa_branches,
       deposits_k  AS boa_deposits_k,
       state_total_k,
       CAST(100.0 * deposits_k / NULLIF(state_total_k, 0) AS DECIMAL(7,3)) AS boa_state_share_pct,
       state_rank  AS boa_state_rank
FROM with_total
WHERE cert = 3510;
GO

-- View 2: each campus county next to the statewide benchmark, every year.
-- share_gap_pts is the county share minus the state share, in percentage points.
-- The index columns divide each year's share by the first year's share (2010 equals 100).
-- NULLIF makes the index NULL where Bank of America had no share in 2010.
CREATE OR ALTER VIEW cln.vw_BoA_vs_State AS
SELECT c.sod_year,
       c.county_fips,
       c.county_name,
       c.boa_branches,
       c.boa_share_pct       AS county_share_pct,
       s.boa_state_share_pct AS state_share_pct,
       CAST(c.boa_share_pct - s.boa_state_share_pct AS DECIMAL(7,3)) AS share_gap_pts,
       CAST(100.0 * c.boa_share_pct
            / NULLIF(bc.boa_share_pct, 0) AS DECIMAL(7,1))           AS county_index,
       CAST(100.0 * s.boa_state_share_pct
            / NULLIF(bs.boa_state_share_pct, 0) AS DECIMAL(7,1))     AS state_index
FROM cln.vw_BoA_CampusCounty c
JOIN cln.vw_BoA_Statewide s
      ON s.sod_year = c.sod_year
-- bc and bs are the same views, filtered to the first study year as the baseline.
JOIN cln.vw_BoA_CampusCounty bc
      ON bc.county_fips = c.county_fips
     AND bc.sod_year = (SELECT MIN(sod_year) FROM cln.SOD_Branch)
JOIN cln.vw_BoA_Statewide bs
      ON bs.sod_year = (SELECT MIN(sod_year) FROM cln.SOD_Branch);
GO

-- Result 1: Bank of America statewide, all 17 years.
SELECT * FROM cln.vw_BoA_Statewide ORDER BY sod_year;

-- Result 2: the three counties still served, next to the state, in selected years.
SELECT county_name, sod_year, county_share_pct, state_share_pct,
       share_gap_pts, county_index, state_index
FROM cln.vw_BoA_vs_State
WHERE county_name IN ('Pulaski', 'Washington', 'Jefferson')
  AND sod_year IN (2010, 2015, 2017, 2021, 2022, 2026)
ORDER BY county_name, sod_year;

-- Result 3: how much of Bank of America's statewide deposits sit in Pulaski County.
SELECT s.sod_year,
       p.boa_deposits_k AS pulaski_boa_k,
       s.boa_deposits_k AS state_boa_k,
       CAST(100.0 * p.boa_deposits_k / s.boa_deposits_k AS DECIMAL(5,1)) AS pulaski_pct_of_state_boa
FROM cln.vw_BoA_Statewide s
JOIN cln.vw_BoA_CampusCounty p
      ON p.sod_year = s.sod_year AND p.county_fips = '05119'
WHERE s.sod_year IN (2010, 2026)
ORDER BY s.sod_year;
GO

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 6b: leave one out benchmark, "the rest of Arkansas" for each campus county.
USE ArkansasBankStudy;
GO

CREATE OR ALTER VIEW cln.vw_BoA_vs_Rest AS
WITH county_total AS (
    -- Total deposits of all banks in each county and year.
    SELECT sod_year, county_fips, SUM(deposits_k) AS county_total_k
    FROM cln.SOD_Branch
    GROUP BY sod_year, county_fips
),
rest AS (
    SELECT c.sod_year,
           c.county_fips,
           c.county_name,
           c.boa_branches,
           c.boa_share_pct AS county_share_pct,
           -- Bank of America's deposits outside the county, divided by all deposits
           -- outside the county. NULLIF avoids a divide by zero.
           CAST(100.0 * (s.boa_deposits_k - c.boa_deposits_k)
                / NULLIF(s.state_total_k - ct.county_total_k, 0)
                AS DECIMAL(7,3)) AS rest_share_pct
    FROM cln.vw_BoA_CampusCounty c
    JOIN cln.vw_BoA_Statewide s  ON s.sod_year = c.sod_year
    JOIN county_total ct         ON ct.sod_year = c.sod_year
                                AND ct.county_fips = c.county_fips
)
SELECT r.sod_year, r.county_fips, r.county_name, r.boa_branches,
       r.county_share_pct,
       r.rest_share_pct,
       CAST(r.county_share_pct - r.rest_share_pct AS DECIMAL(7,3)) AS gap_vs_rest_pts,
       -- Index: share divided by the first year's share, so 2010 equals 100.
       CAST(100.0 * r.county_share_pct / NULLIF(b.county_share_pct, 0) AS DECIMAL(7,1)) AS county_index,
       CAST(100.0 * r.rest_share_pct   / NULLIF(b.rest_share_pct, 0)   AS DECIMAL(7,1)) AS rest_index
FROM rest r
-- b is the same table filtered to the first study year, used as the baseline.
JOIN rest b ON b.county_fips = r.county_fips
           AND b.sod_year = (SELECT MIN(sod_year) FROM cln.SOD_Branch);
GO

-- Result 1: the three counties still served, against the rest of Arkansas.
SELECT county_name, sod_year, county_share_pct, rest_share_pct,
       gap_vs_rest_pts, county_index, rest_index
FROM cln.vw_BoA_vs_Rest
WHERE county_name IN ('Pulaski', 'Washington', 'Jefferson')
  AND sod_year IN (2010, 2015, 2017, 2021, 2022, 2026)
ORDER BY county_name, sod_year;

-- Result 2: 2026 index gap for each county under both benchmarks.
-- A negative number means the county fell further below its 2010 level than the benchmark.
SELECT r.county_name,
       r.county_index                              AS county_index_2026,
       s.state_index                               AS state_index_2026,
       r.rest_index                                AS rest_index_2026,
       CAST(r.county_index - s.state_index AS DECIMAL(7,1)) AS gap_vs_state,
       CAST(r.county_index - r.rest_index  AS DECIMAL(7,1)) AS gap_vs_rest
FROM cln.vw_BoA_vs_Rest r
JOIN cln.vw_BoA_vs_State s
      ON s.sod_year = r.sod_year AND s.county_fips = r.county_fips
WHERE r.sod_year = 2026
  AND r.county_name IN ('Pulaski', 'Washington', 'Jefferson')
ORDER BY r.county_name;
GO

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 6b(i) 
-- Jefferson County, 2015 to 2019: branches, deposits, share, and both indexes.
-- vw_BoA_vs_Rest holds the share and the two indexes (2010 equals 100).
-- vw_BoA_CampusCounty adds Bank of America's deposits in thousands of dollars.
SELECT r.sod_year,
       r.boa_branches,
       c.boa_deposits_k,
       r.county_share_pct,
       r.county_index,   -- Jefferson County
       r.rest_index      -- the rest of Arkansas
FROM cln.vw_BoA_vs_Rest r
JOIN cln.vw_BoA_CampusCounty c
      ON c.sod_year    = r.sod_year
     AND c.county_fips = r.county_fips
WHERE r.county_name = 'Jefferson'
  AND r.sod_year BETWEEN 2015 AND 2019
ORDER BY r.sod_year;

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 6b(ii)
-- Top four banks in Jefferson County (05069), 2016 to 2018.
-- county_total_k is every bank's deposits added together, in thousands of dollars.
-- A big jump in county_total_k, with one bank's deposits rising to match, shows who gained.
SELECT sod_year, deposit_rank, bank_name, branches,
       deposits_k, county_total_k, market_share_pct
FROM cln.vw_BankCountyYear
WHERE county_fips = '05069'
  AND sod_year IN (2016, 2017, 2018)
  AND deposit_rank <= 4
ORDER BY sod_year, deposit_rank;

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

--Stage 6b(iii)
-- Simmons Bank's three largest offices in Jefferson County (05069), 2016 to 2018.
-- ROW_NUMBER ranks offices from largest to smallest inside each year.
-- main_office_flag = 1 marks the bank's main office. A huge jump at the main office
-- suggests deposits were booked there, not gathered from new local customers.
WITH ranked AS (
    SELECT sod_year, branch_name, branch_city, main_office_flag, deposits_k,
           ROW_NUMBER() OVER (PARTITION BY sod_year ORDER BY deposits_k DESC) AS rn
    FROM cln.SOD_Branch
    WHERE county_fips = '05069'
      AND bank_name_std LIKE 'Simmons%'
      AND sod_year IN (2016, 2017, 2018)
)
SELECT sod_year, branch_name, branch_city, main_office_flag, deposits_k
FROM ranked
WHERE rn <= 3
ORDER BY sod_year, rn;


/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

--Stage 6b(iv)
-- Bank OZK's three largest offices in Pulaski County (05119), 2010, 2016 and 2026.
-- ROW_NUMBER ranks offices from largest to smallest inside each year.
-- main_office_flag = 1 marks the bank's main office. If one main office row grows
-- while the branches stay flat, deposits were booked there, as with Simmons in Jefferson.
WITH ranked AS (
    SELECT sod_year, branch_name, branch_city, main_office_flag, deposits_k,
           ROW_NUMBER() OVER (PARTITION BY sod_year ORDER BY deposits_k DESC) AS rn
    FROM cln.SOD_Branch
    WHERE county_fips = '05119'
      AND bank_name_std LIKE 'Bank OZK%'
      AND sod_year IN (2010, 2016, 2026)
)
SELECT sod_year, branch_name, branch_city, main_office_flag, deposits_k
FROM ranked
WHERE rn <= 3
ORDER BY sod_year, rn;

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

--Stage 6b(v)
-- Bank of America's share in Pulaski County (05119), with and without Bank OZK's main office.
-- county_total_k adds every bank's deposits in the county, in thousands of dollars.
-- ozk_main_k is Bank OZK's main office alone (main_office_flag = '1').
-- Subtracting it from the county total shows what the share would be without that booking.
WITH t AS (
    SELECT sod_year,
           SUM(deposits_k) AS county_total_k,
           SUM(CASE WHEN bank_name_std LIKE 'Bank OZK%' AND main_office_flag = '1'
                    THEN deposits_k ELSE 0 END) AS ozk_main_k,
           SUM(CASE WHEN cert = 3510 THEN deposits_k ELSE 0 END) AS boa_k
    FROM cln.SOD_Branch
    WHERE county_fips = '05119'
      AND sod_year IN (2010, 2016, 2026)
    GROUP BY sod_year
)
SELECT sod_year, boa_k, county_total_k, ozk_main_k,
       CAST(100.0 * boa_k / county_total_k AS DECIMAL(6,2)) AS share_all_pct,
       CAST(100.0 * boa_k / NULLIF(county_total_k - ozk_main_k, 0) AS DECIMAL(6,2)) AS share_without_ozk_main_pct
FROM t
ORDER BY sod_year;

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 7a: branch lifecycle. What happened to each branch one year later?
USE ArkansasBankStudy;
GO

CREATE OR ALTER VIEW cln.vw_BranchTransition AS
SELECT a.sod_year,                       -- the June 30 snapshot where the branch was seen
       a.branch_key, a.cert,
       a.bank_name_std AS bank_name,     -- one current name per bank (from Stage 4d)
       a.county_fips, a.county_name,
       a.branch_address, a.branch_city,
       a.deposits_k,
       b.cert          AS next_cert,     -- NULL when the branch is gone a year later
       b.bank_name_std AS next_bank_name,--same standard name for the new owner
       CASE WHEN b.branch_key IS NULL THEN 'CLOSED'          -- no row a year later
            WHEN b.cert = a.cert      THEN 'STAYED'          -- same bank, same branch
            ELSE 'SOLD_OR_MERGED'                            -- same branch, different bank
       END AS next_year_status
FROM cln.SOD_Branch a
-- LEFT JOIN keeps every row of a, even when no row of b matches.
LEFT JOIN cln.SOD_Branch b
       ON b.branch_key = a.branch_key
      AND b.sod_year   = a.sod_year + 1
-- The last snapshot has no later year to compare with.
WHERE a.sod_year < (SELECT MAX(sod_year) FROM cln.SOD_Branch)
  -- Rows with fallback keys (2010 only) cannot be tracked reliably, so they are left out.
  AND a.key_source = 'FDIC_ID';
GO

-- Result 1: Bank of America branches that did not stay, statewide, by window.
-- june_30_of is the year the branch was last seen at Bank of America.
SELECT sod_year AS june_30_of,
       sod_year + 1 AS gone_by_june_30_of,
       next_year_status,
       COUNT(*) AS branches
FROM cln.vw_BranchTransition
WHERE cert = 3510 AND next_year_status <> 'STAYED'
GROUP BY sod_year, next_year_status
ORDER BY sod_year, next_year_status;

-- Result 2: the same events in the campus counties, with addresses and the new owner.
SELECT t.county_name, t.sod_year AS june_30_of, t.next_year_status,
       t.branch_address, t.branch_city, t.deposits_k, t.next_bank_name
FROM cln.vw_BranchTransition t
JOIN cln.CampusCounty c ON c.county_fips = t.county_fips
WHERE t.cert = 3510 AND t.next_year_status <> 'STAYED'
ORDER BY t.county_name, t.sod_year;

-- Result 3: in what year did each Bank of America branch first appear? If Bank of
-- America opened nothing new, every branch shows the first study year.
WITH first_seen AS (
    SELECT branch_key, MIN(sod_year) AS first_year
    FROM cln.SOD_Branch
    WHERE cert = 3510 AND key_source = 'FDIC_ID'
    GROUP BY branch_key
)
SELECT first_year, COUNT(*) AS branches
FROM first_seen
GROUP BY first_year
ORDER BY first_year;
GO

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 7b: closure impact and Chase comparison.
USE ArkansasBankStudy;
GO

-- View: one row per county and closure window for Bank of America (certificate 3510).
CREATE OR ALTER VIEW cln.vw_ClosureImpact AS
WITH county_total AS (
    -- Total deposits of all banks in each county and year.
    SELECT sod_year, county_fips, SUM(deposits_k) AS county_total_k
    FROM cln.SOD_Branch
    GROUP BY sod_year, county_fips
),
closures AS (
    -- Add up closed branches per county and window. Only campus counties are kept,
    -- and branches with 0 deposits are skipped (likely offices that took no deposits).
    SELECT t.sod_year, t.county_fips, t.county_name,
           COUNT(*)            AS closed_branches,
           SUM(t.deposits_k)   AS closed_deposits_k
    FROM cln.vw_BranchTransition t
    JOIN cln.CampusCounty c ON c.county_fips = t.county_fips
    WHERE t.cert = 3510
      AND t.next_year_status = 'CLOSED'
      AND t.deposits_k > 0
    GROUP BY t.sod_year, t.county_fips, t.county_name
)
SELECT cl.county_name,
       cl.sod_year      AS june_30_of,          -- last snapshot with the branch open
       cl.sod_year + 1  AS gone_by_june_30_of,  -- first snapshot without it
       cl.closed_branches,
       cl.closed_deposits_k,
       -- Size of the closure relative to Bank of America's deposits in that county.
       CAST(100.0 * cl.closed_deposits_k / NULLIF(b0.boa_deposits_k, 0)
            AS DECIMAL(6,1)) AS closed_pct_of_boa_county,
       b0.boa_share_pct AS share_before,
       b1.boa_share_pct AS share_after,
       CAST(b1.boa_share_pct - b0.boa_share_pct AS DECIMAL(7,3)) AS share_change_pts,
       CAST(100.0 * (b1.boa_deposits_k - b0.boa_deposits_k)
            / NULLIF(b0.boa_deposits_k, 0) AS DECIMAL(7,1)) AS boa_deposit_change_pct,
       CAST(100.0 * (t1.county_total_k - t0.county_total_k)
            / NULLIF(t0.county_total_k, 0) AS DECIMAL(7,1)) AS county_total_change_pct
FROM closures cl
JOIN cln.vw_BoA_CampusCounty b0 ON b0.county_fips = cl.county_fips AND b0.sod_year = cl.sod_year
JOIN cln.vw_BoA_CampusCounty b1 ON b1.county_fips = cl.county_fips AND b1.sod_year = cl.sod_year + 1
JOIN county_total t0 ON t0.county_fips = cl.county_fips AND t0.sod_year = cl.sod_year
JOIN county_total t1 ON t1.county_fips = cl.county_fips AND t1.sod_year = cl.sod_year + 1;
GO

-- Result 1: all closure events in the campus counties.
SELECT * FROM cln.vw_ClosureImpact ORDER BY county_name, june_30_of;

-- Result 2: Chase (certificate 628) next to Bank of America, 2020 to 2026.
-- Where Chase has no branch, branches and share show 0 and the rank stays NULL.
SELECT b.county_name, b.sod_year,
       COALESCE(ch.branches, 0)         AS chase_branches,
       COALESCE(ch.market_share_pct, 0) AS chase_share_pct,
       ch.deposit_rank                  AS chase_rank,
       b.boa_branches, b.boa_share_pct, b.boa_rank
FROM cln.vw_BoA_CampusCounty b
LEFT JOIN cln.vw_BankCountyYear ch
       ON ch.sod_year = b.sod_year
      AND ch.county_fips = b.county_fips
      AND ch.cert = 628
WHERE b.county_name IN ('Pulaski', 'Washington', 'Jefferson')
  AND b.sod_year BETWEEN 2020 AND 2026
ORDER BY b.county_name, b.sod_year;
GO

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 8a: staging tables for the three ACS files, then a load.
USE ArkansasBankStudy;
GO

-- Folder that holds the ACS files. Keep the backslash at the end.
DECLARE @folder NVARCHAR(260) = N'C:\Bank of America\ACS\';

-- One row per ACS file: the vintage (the last year of the window) and the number of
-- variables in that file. The 2014 file has 15 variables, the other two have 27.
DECLARE @spec TABLE (vintage INT, nvars INT);
INSERT INTO @spec VALUES (2014, 15), (2019, 27), (2024, 27);

DECLARE @vintage INT, @n INT, @i INT;
DECLARE @cols NVARCHAR(MAX), @sql NVARCHAR(MAX), @tbl NVARCHAR(60), @file NVARCHAR(400);

-- A cursor visits the three rows of @spec one at a time.
DECLARE spec_cursor CURSOR FOR SELECT vintage, nvars FROM @spec;
OPEN spec_cursor;
FETCH NEXT FROM spec_cursor INTO @vintage, @n;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Table name for this file, such as stg.ACS_2014.
    SET @tbl = N'stg.ACS_' + CAST(@vintage AS NVARCHAR(4));

    -- Start the column list with the two ID columns. Everything is text in staging.
    SET @cols = N'GEO_ID VARCHAR(30), NAME VARCHAR(100)';

    -- Add an estimate column (E) and a margin of error column (M) for each variable,
    -- in the same order as the file: B05002_001E, B05002_001M, B05002_002E, and so on.
    SET @i = 1;
    WHILE @i <= @n
    BEGIN
        SET @cols = @cols
            + N', B05002_' + RIGHT('000' + CAST(@i AS NVARCHAR(3)), 3) + N'E VARCHAR(20)'
            + N', B05002_' + RIGHT('000' + CAST(@i AS NVARCHAR(3)), 3) + N'M VARCHAR(20)';
        SET @i = @i + 1;
    END;

    -- Every line in the files ends with a comma, so each line has one extra empty field.
    SET @cols = @cols + N', trailing_blank VARCHAR(5)';

    -- Rebuild the table: drop it if it exists, then create it with the column list.
    SET @sql = N'IF OBJECT_ID(''' + @tbl + N''', ''U'') IS NOT NULL DROP TABLE ' + @tbl + N'; '
             + N'CREATE TABLE ' + @tbl + N' (' + @cols + N');';
    EXEC sys.sp_executesql @sql;

    -- Build the file name. The Census files use a DOT before B05002, such as
    -- ACSDT5Y2014.B05002-Data.csv. 
    SET @file = @folder + N'ACSDT5Y' + CAST(@vintage AS NVARCHAR(4)) + N'.B05002-Data.csv';
    PRINT N'Loading ' + @file;

    -- Load the file. FIRSTROW = 3 skips line 1 (variable codes) and line 2 (labels).
    -- Rows end with a line feed (hex 0a), and every value is quoted.
    SET @sql = N'BULK INSERT ' + @tbl + N' FROM ''' + @file + N''' WITH ('
             + N'FORMAT = ''CSV'', FIELDQUOTE = ''"'', FIRSTROW = 3, '
             + N'CODEPAGE = ''65001'', FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'');';
    EXEC sys.sp_executesql @sql;

    FETCH NEXT FROM spec_cursor INTO @vintage, @n;
END;

CLOSE spec_cursor;
DEALLOCATE spec_cursor;
GO

-- Check 1: each table should have 76 rows (1 state + 75 counties) and no stray text
-- in the extra trailing column.
SELECT 2014 AS vintage, COUNT(*) AS total_rows,
       SUM(CASE WHEN GEO_ID LIKE '0500000US%' THEN 1 ELSE 0 END) AS county_rows,
       SUM(CASE WHEN GEO_ID LIKE '0400000US%' THEN 1 ELSE 0 END) AS state_rows,
       SUM(CASE WHEN trailing_blank IS NOT NULL AND trailing_blank <> '' THEN 1 ELSE 0 END) AS stray_trailing
FROM stg.ACS_2014
UNION ALL
SELECT 2019, COUNT(*),
       SUM(CASE WHEN GEO_ID LIKE '0500000US%' THEN 1 ELSE 0 END),
       SUM(CASE WHEN GEO_ID LIKE '0400000US%' THEN 1 ELSE 0 END),
       SUM(CASE WHEN trailing_blank IS NOT NULL AND trailing_blank <> '' THEN 1 ELSE 0 END)
FROM stg.ACS_2019
UNION ALL
SELECT 2024, COUNT(*),
       SUM(CASE WHEN GEO_ID LIKE '0500000US%' THEN 1 ELSE 0 END),
       SUM(CASE WHEN GEO_ID LIKE '0400000US%' THEN 1 ELSE 0 END),
       SUM(CASE WHEN trailing_blank IS NOT NULL AND trailing_blank <> '' THEN 1 ELSE 0 END)
FROM stg.ACS_2024;

-- Check 2: spot check two counties. The "not citizen" column is _015 in 2014
-- and _021 in the other two files, which is why each SELECT names its own column.
SELECT 2014 AS vintage, NAME, B05002_001E AS total_pop,
       B05002_013E AS foreign_born, B05002_015E AS not_citizen
FROM stg.ACS_2014 WHERE GEO_ID IN ('0500000US05143', '0500000US05119')
UNION ALL
SELECT 2019, NAME, B05002_001E, B05002_013E, B05002_021E
FROM stg.ACS_2019 WHERE GEO_ID IN ('0500000US05143', '0500000US05119')
UNION ALL
SELECT 2024, NAME, B05002_001E, B05002_013E, B05002_021E
FROM stg.ACS_2024 WHERE GEO_ID IN ('0500000US05143', '0500000US05119')
ORDER BY NAME, vintage;
GO

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 8b: clean ACS county table, one row per county and ACS window.
USE ArkansasBankStudy;
GO

IF OBJECT_ID('cln.ACS_County', 'U') IS NOT NULL
    DROP TABLE cln.ACS_County;
GO

WITH raw_union AS (
    -- Stack the three staging tables. Only county rows are kept (GEO_ID starts with
    -- 0500000US), so the Arkansas state row is left out. Each SELECT names its own
    -- "not a citizen" column, because the code changed between files:
    -- _015 in the 2014 file and _021 in the 2019 and 2024 files.
    SELECT 2014 AS vintage, '2010 to 2014' AS acs_window, GEO_ID, NAME,
           B05002_001E AS tp, B05002_001M AS tp_m,
           B05002_013E AS fb, B05002_013M AS fb_m,
           B05002_015E AS nc, B05002_015M AS nc_m
    FROM stg.ACS_2014 WHERE GEO_ID LIKE '0500000US%'
    UNION ALL
    SELECT 2019, '2015 to 2019', GEO_ID, NAME,
           B05002_001E, B05002_001M, B05002_013E, B05002_013M, B05002_021E, B05002_021M
    FROM stg.ACS_2019 WHERE GEO_ID LIKE '0500000US%'
    UNION ALL
    SELECT 2024, '2020 to 2024', GEO_ID, NAME,
           B05002_001E, B05002_001M, B05002_013E, B05002_013M, B05002_021E, B05002_021M
    FROM stg.ACS_2024 WHERE GEO_ID LIKE '0500000US%'
),
typed AS (
    -- Turn text into numbers. TRY_CAST returns NULL for text that is not a number,
    -- which is exactly what happens to the ***** symbol in the total population margin.
    SELECT vintage, acs_window,
           CAST(RIGHT(GEO_ID, 5) AS CHAR(5)) AS county_fips,   -- 0500000US05119 becomes 05119
           NAME AS county_name_census,
           TRY_CAST(tp   AS INT) AS total_pop,
           TRY_CAST(tp_m AS INT) AS total_pop_moe,
           TRY_CAST(fb   AS INT) AS foreign_born,
           TRY_CAST(fb_m AS INT) AS foreign_born_moe,
           TRY_CAST(nc   AS INT) AS not_citizen,
           TRY_CAST(nc_m AS INT) AS not_citizen_moe
    FROM raw_union
)
SELECT vintage, acs_window, county_fips, county_name_census,
       total_pop, total_pop_moe,
       foreign_born, foreign_born_moe,
       not_citizen, not_citizen_moe,
       -- Shares of the county population, in percent. NULLIF avoids a divide by zero.
       CAST(100.0 * foreign_born / NULLIF(total_pop, 0) AS DECIMAL(6,2)) AS foreign_born_pct,
       CAST(100.0 * not_citizen  / NULLIF(total_pop, 0) AS DECIMAL(6,2)) AS not_citizen_pct,
       -- Coefficient of variation: standard error (margin divided by 1.645) as a
       -- percent of the estimate. NULL when the estimate is 0.
       CAST(100.0 * (not_citizen_moe / 1.645) / NULLIF(not_citizen, 0)
            AS DECIMAL(7,1)) AS not_citizen_cv_pct,
       -- Reliability label, using a common rule of thumb (not an official Census cutoff).
       CAST(CASE WHEN not_citizen = 0 THEN 'Low'
                 WHEN 100.0 * (not_citizen_moe / 1.645) / not_citizen <= 15 THEN 'High'
                 WHEN 100.0 * (not_citizen_moe / 1.645) / not_citizen <= 30 THEN 'Medium'
                 ELSE 'Low' END AS VARCHAR(6)) AS not_citizen_reliability
INTO cln.ACS_County
FROM typed;
GO

-- Check 1: expect 75 counties in each of the three windows.
SELECT vintage, acs_window, COUNT(*) AS counties
FROM cln.ACS_County
GROUP BY vintage, acs_window
ORDER BY vintage;

-- Check 2: NULL counts. Expect 0 for the first five columns, and 225 for the
-- total population margin, which is always the ***** symbol.
SELECT SUM(CASE WHEN total_pop         IS NULL THEN 1 ELSE 0 END) AS null_total_pop,
       SUM(CASE WHEN foreign_born      IS NULL THEN 1 ELSE 0 END) AS null_foreign_born,
       SUM(CASE WHEN not_citizen       IS NULL THEN 1 ELSE 0 END) AS null_not_citizen,
       SUM(CASE WHEN foreign_born_moe  IS NULL THEN 1 ELSE 0 END) AS null_fb_moe,
       SUM(CASE WHEN not_citizen_moe   IS NULL THEN 1 ELSE 0 END) AS null_nc_moe,
       SUM(CASE WHEN total_pop_moe     IS NULL THEN 1 ELSE 0 END) AS null_total_moe
FROM cln.ACS_County;

-- Check 3: the 13 campus counties across the three windows.
SELECT c.county_name,
       MAX(CASE WHEN a.vintage = 2014 THEN a.foreign_born_pct END) AS fb_pct_2014,
       MAX(CASE WHEN a.vintage = 2024 THEN a.foreign_born_pct END) AS fb_pct_2024,
       MAX(CASE WHEN a.vintage = 2014 THEN a.not_citizen_pct END)  AS nc_pct_2014,
       MAX(CASE WHEN a.vintage = 2019 THEN a.not_citizen_pct END)  AS nc_pct_2019,
       MAX(CASE WHEN a.vintage = 2024 THEN a.not_citizen_pct END)  AS nc_pct_2024,
       MAX(CASE WHEN a.vintage = 2024 THEN a.not_citizen_reliability END) AS reliability_2024
FROM cln.ACS_County a
JOIN cln.CampusCounty c ON c.county_fips = a.county_fips
GROUP BY c.county_name
ORDER BY c.county_name;

-- Check 4: reliability labels for all 75 counties in 2024.
SELECT not_citizen_reliability, COUNT(*) AS counties
FROM cln.ACS_County
WHERE vintage = 2024
GROUP BY not_citizen_reliability
ORDER BY counties DESC;
GO

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 8c: one row per campus county, with Bank of America's trend and the ACS traits.
USE ArkansasBankStudy;
GO

CREATE OR ALTER VIEW cln.vw_Q4_CountyProfile AS
WITH yrs AS (
    -- First and last deposit years in the data (2010 and 2026), so nothing is typed by hand.
    SELECT MIN(sod_year) AS y0, MAX(sod_year) AS y1 FROM cln.SOD_Branch
)
SELECT c.county_fips,
       c.county_name,
       b0.boa_branches AS boa_branches_start,
       b1.boa_branches AS boa_branches_end,
       b0.boa_share_pct AS boa_share_start,
       b1.boa_share_pct AS boa_share_end,
       -- Change in percentage points.
       CAST(b1.boa_share_pct - b0.boa_share_pct AS DECIMAL(7,3)) AS boa_share_change_pts,
       -- Change as a percent of the starting share. NULL when the start is 0.
       CAST(100.0 * (b1.boa_share_pct - b0.boa_share_pct)
            / NULLIF(b0.boa_share_pct, 0) AS DECIMAL(7,1)) AS boa_share_change_pct,
       CAST(CASE WHEN b0.boa_branches = 0 AND b1.boa_branches = 0 THEN 'No branch'
                 WHEN b0.boa_branches > 0 AND b1.boa_branches = 0 THEN 'Exited'
                 ELSE 'Still present' END AS VARCHAR(14)) AS boa_status,
       -- ACS traits: the 2010 to 2014 window at the start, the 2020 to 2024 window at the end.
       a0.foreign_born_pct AS fb_pct_2014,
       a1.foreign_born_pct AS fb_pct_2024,
       a0.not_citizen_pct  AS nc_pct_2014,
       a1.not_citizen_pct  AS nc_pct_2024,
       a1.not_citizen_reliability AS nc_reliability_2024
FROM cln.CampusCounty c
CROSS JOIN yrs
JOIN cln.vw_BoA_CampusCounty b0 ON b0.county_fips = c.county_fips AND b0.sod_year = yrs.y0
JOIN cln.vw_BoA_CampusCounty b1 ON b1.county_fips = c.county_fips AND b1.sod_year = yrs.y1
JOIN cln.ACS_County a0 ON a0.county_fips = c.county_fips AND a0.vintage = 2014
JOIN cln.ACS_County a1 ON a1.county_fips = c.county_fips AND a1.vintage = 2024;
GO

-- Result 1: the full profile, sorted by Bank of America's change in share.
SELECT county_name, boa_status,
       boa_branches_start, boa_branches_end,
       boa_share_start, boa_share_end,
       boa_share_change_pts, boa_share_change_pct,
       nc_pct_2024, nc_reliability_2024
FROM cln.vw_Q4_CountyProfile
ORDER BY boa_share_change_pts;

-- Result 2: how many counties fall into each status. Expect 8, 3, and 2.
SELECT boa_status, COUNT(*) AS counties
FROM cln.vw_Q4_CountyProfile
GROUP BY boa_status
ORDER BY counties DESC;
GO

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 9a: staging table and load for the IPEDS fall enrollment file.
-- NOTE FOR READERS: the downloaded IPEDS file has no line break after its last row,
-- and SQL Server skips a final row that ends that way. One line break was added at
-- the very end of a copy of the file (the "_prepared" file). The original is untouched.
USE ArkansasBankStudy;
GO

IF OBJECT_ID('stg.IPEDS_FallEnroll', 'U') IS NOT NULL
    DROP TABLE stg.IPEDS_FallEnroll;
GO

-- Columns follow the file order. gt means grand total of all students.
-- nr means nonresident (called "Nonresident alien" until 2022 to 2023, "U.S. Nonresident" in 2024).
-- Each count is followed by its IPEDS status flag. Everything is text in staging.
CREATE TABLE stg.IPEDS_FallEnroll (
    unitid          VARCHAR(10),    -- the stable IPEDS code for each institution
    inst_name       VARCHAR(150),
    state_abbr      VARCHAR(5),
    gt_2024         VARCHAR(20), gt_2024_flag VARCHAR(5),
    nr_2024         VARCHAR(20), nr_2024_flag VARCHAR(5),
    gt_2019         VARCHAR(20), gt_2019_flag VARCHAR(5),
    nr_2019         VARCHAR(20), nr_2019_flag VARCHAR(5),
    gt_2014         VARCHAR(20), gt_2014_flag VARCHAR(5),
    nr_2014         VARCHAR(20), nr_2014_flag VARCHAR(5),
    gt_2010         VARCHAR(20), gt_2010_flag VARCHAR(5),
    nr_2010         VARCHAR(20), nr_2010_flag VARCHAR(5),
    trailing_blank  VARCHAR(5)      -- each line ends with a comma, which adds an empty field
);
GO

-- Path to the prepared copy of the IPEDS file. Notepad saved it with a .txt ending,
-- which does not matter to SQL Server. Edit this line only if the file moves or is renamed.
DECLARE @file NVARCHAR(400) = N'C:\Bank of America\IPEDS_Data\Data_11-2-2026---165_prepared.txt';
DECLARE @sql  NVARCHAR(MAX);

-- FIRSTROW = 2 skips the header line. In the prepared file, all 80 rows end with
-- a carriage return plus a line feed (hex 0d0a).
SET @sql = N'BULK INSERT stg.IPEDS_FallEnroll FROM ''' + @file + N''' WITH ('
         + N'FORMAT = ''CSV'', FIELDQUOTE = ''"'', FIRSTROW = 2, '
         + N'CODEPAGE = ''65001'', FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0d0a'');';
EXEC sys.sp_executesql @sql;
GO

-- Check 1: expect 80 rows, 80 different UnitIDs, 80 rows with AR, and 0 stray values.
-- REPLACE strips a carriage return before testing, in case one stays in the last column.
SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT unitid) AS distinct_unitids,
       SUM(CASE WHEN state_abbr = 'AR' THEN 1 ELSE 0 END) AS ar_rows,
       SUM(CASE WHEN REPLACE(ISNULL(trailing_blank, ''), CHAR(13), '') <> '' THEN 1 ELSE 0 END) AS stray_trailing
FROM stg.IPEDS_FallEnroll;

-- Check 2: blank counts by year. Expect 3 for 2024, 3 for 2019, 12 for 2014, and 15 for 2010.
SELECT SUM(CASE WHEN gt_2024 IS NULL OR gt_2024 = '' THEN 1 ELSE 0 END) AS blank_2024,
       SUM(CASE WHEN gt_2019 IS NULL OR gt_2019 = '' THEN 1 ELSE 0 END) AS blank_2019,
       SUM(CASE WHEN gt_2014 IS NULL OR gt_2014 = '' THEN 1 ELSE 0 END) AS blank_2014,
       SUM(CASE WHEN gt_2010 IS NULL OR gt_2010 = '' THEN 1 ELSE 0 END) AS blank_2010
FROM stg.IPEDS_FallEnroll;

-- Check 3: spot check three campuses.
SELECT unitid, inst_name, gt_2010, nr_2010, gt_2024, nr_2024
FROM stg.IPEDS_FallEnroll
WHERE unitid IN ('106397', '106245', '107460')
ORDER BY unitid;

-- Check 4: the last row of the file, which was dropped before the fix.
-- Expect Williams Baptist University: 517 and 42 in 2024, 631 and 9 in 2010.
SELECT unitid, inst_name, gt_2024, nr_2024, gt_2010, nr_2010
FROM stg.IPEDS_FallEnroll
WHERE unitid = '107877';
GO

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 9b: campus lookup, clean IPEDS table, county view, and the final county profile.
USE ArkansasBankStudy;
GO

-- Part 1: campus lookup. One row per campus, with its stable IPEDS UnitID and its county.
-- UA Grantham and the UA System Office are left out on purpose, and are not counted.
IF OBJECT_ID('cln.Campus', 'U') IS NOT NULL
    DROP TABLE cln.Campus;
GO

CREATE TABLE cln.Campus (
    unitid      INT         NOT NULL PRIMARY KEY,
    campus      VARCHAR(60) NOT NULL,
    county_fips CHAR(5)     NOT NULL REFERENCES cln.CampusCounty (county_fips)
);
GO

INSERT INTO cln.Campus (unitid, campus, county_fips) VALUES
    (106397, 'UA Fayetteville',             '05143'),
    (106245, 'UA Little Rock',              '05119'),
    (106263, 'UAMS',                        '05119'),
    (107664, 'UA Pulaski Technical College','05119'),
    (108092, 'UA Fort Smith',               '05131'),
    (106412, 'UA Pine Bluff',               '05069'),
    (106485, 'UA Monticello',               '05043'),
    (107619, 'Phillips Community College',  '05107'),
    (107725, 'UA Hope Texarkana',           '05057'),
    (106999, 'UA Batesville',               '05063'),
    (106795, 'Cossatot Community College',  '05133'),
    (107585, 'UA Morrilton',                '05029'),
    (107743, 'UA Rich Mountain',            '05113'),
    (106883, 'UA East Arkansas',            '05123'),
    (107460, 'North Arkansas College',      '05009');
GO

-- Part 2: clean campus by year table. The staging table has one column per year,
-- so four SELECTs (one per fall year) are stacked into rows, and text becomes numbers.
IF OBJECT_ID('cln.IPEDS_CampusYear', 'U') IS NOT NULL
    DROP TABLE cln.IPEDS_CampusYear;
GO

SELECT c.unitid, y.fall_year, y.grand_total, y.nonresident, y.nonresident_flag
INTO cln.IPEDS_CampusYear
FROM cln.Campus c
JOIN (
    SELECT TRY_CAST(unitid AS INT) AS unitid, 2010 AS fall_year,
           TRY_CAST(gt_2010 AS INT) AS grand_total, TRY_CAST(nr_2010 AS INT) AS nonresident,
           NULLIF(LTRIM(RTRIM(nr_2010_flag)), '') AS nonresident_flag
    FROM stg.IPEDS_FallEnroll
    UNION ALL
    SELECT TRY_CAST(unitid AS INT), 2014, TRY_CAST(gt_2014 AS INT), TRY_CAST(nr_2014 AS INT),
           NULLIF(LTRIM(RTRIM(nr_2014_flag)), '')
    FROM stg.IPEDS_FallEnroll
    UNION ALL
    SELECT TRY_CAST(unitid AS INT), 2019, TRY_CAST(gt_2019 AS INT), TRY_CAST(nr_2019 AS INT),
           NULLIF(LTRIM(RTRIM(nr_2019_flag)), '')
    FROM stg.IPEDS_FallEnroll
    UNION ALL
    SELECT TRY_CAST(unitid AS INT), 2024, TRY_CAST(gt_2024 AS INT), TRY_CAST(nr_2024 AS INT),
           NULLIF(LTRIM(RTRIM(nr_2024_flag)), '')
    FROM stg.IPEDS_FallEnroll
) y ON y.unitid = c.unitid;      -- the join keeps only the 15 campuses
GO

-- Part 3: county level view. Percent = summed nonresident students divided by summed
-- enrollment, so a big campus counts for more than a small one.
CREATE OR ALTER VIEW cln.vw_County_Intl AS
SELECT k.county_fips, k.county_name, y.fall_year,
       COUNT(*)           AS campuses,
       SUM(y.grand_total) AS grand_total,
       SUM(y.nonresident) AS nonresident,
       CAST(100.0 * SUM(y.nonresident) / NULLIF(SUM(y.grand_total), 0) AS DECIMAL(6,2)) AS nonresident_pct
FROM cln.IPEDS_CampusYear y
JOIN cln.Campus c        ON c.unitid = y.unitid
JOIN cln.CampusCounty k  ON k.county_fips = c.county_fips
GROUP BY k.county_fips, k.county_name, y.fall_year;
GO

-- Part 4: the final county profile, joining Bank of America's trend, the ACS traits,
-- and the IPEDS international student share for the first and last fall years.
CREATE OR ALTER VIEW cln.vw_Q4_Final AS
SELECT p.*,
       i1.campuses         AS campuses,
       i0.nonresident_pct  AS intl_pct_2010,
       i1.nonresident_pct  AS intl_pct_2024,
       i1.nonresident      AS intl_count_2024
FROM cln.vw_Q4_CountyProfile p
JOIN cln.vw_County_Intl i0 ON i0.county_fips = p.county_fips AND i0.fall_year = 2010
JOIN cln.vw_County_Intl i1 ON i1.county_fips = p.county_fips AND i1.fall_year = 2024;
GO

-- Result 1: the lookup against the IPEDS names. Expect 15 rows, with no empty ipeds_name.
SELECT c.unitid, c.campus, s.inst_name AS ipeds_name, c.county_fips
FROM cln.Campus c
LEFT JOIN stg.IPEDS_FallEnroll s ON TRY_CAST(s.unitid AS INT) = c.unitid
ORDER BY c.county_fips, c.unitid;

-- Result 2: expect 60 rows (15 campuses times 4 years) and 0 NULL values in both columns.
SELECT COUNT(*) AS campus_year_rows,
       SUM(CASE WHEN grand_total IS NULL THEN 1 ELSE 0 END) AS null_grand_total,
       SUM(CASE WHEN nonresident IS NULL THEN 1 ELSE 0 END) AS null_nonresident
FROM cln.IPEDS_CampusYear;

-- Result 3: county totals for the first and last fall years.
SELECT county_name,
       MAX(campuses) AS campuses,
       MAX(CASE WHEN fall_year = 2010 THEN nonresident     END) AS intl_2010,
       MAX(CASE WHEN fall_year = 2010 THEN grand_total     END) AS total_2010,
       MAX(CASE WHEN fall_year = 2010 THEN nonresident_pct END) AS pct_2010,
       MAX(CASE WHEN fall_year = 2024 THEN nonresident     END) AS intl_2024,
       MAX(CASE WHEN fall_year = 2024 THEN grand_total     END) AS total_2024,
       MAX(CASE WHEN fall_year = 2024 THEN nonresident_pct END) AS pct_2024
FROM cln.vw_County_Intl
GROUP BY county_name
ORDER BY county_name;

-- Result 4: the final profile, sorted by Bank of America's change in share.
SELECT county_name, boa_status, boa_share_change_pct,
       nc_pct_2024, intl_pct_2010, intl_pct_2024, intl_count_2024
FROM cln.vw_Q4_Final
ORDER BY boa_share_change_pts;
GO

/*----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/

-- Stage 10a: who serves the campus counties where Bank of America has no branch?
USE ArkansasBankStudy;
GO

-- Result 1: the top three banks by deposits in each "No branch" county, latest year.
-- The CTE picks the counties from the profile view, so the list updates itself.
WITH no_boa AS (
    SELECT county_fips
    FROM cln.vw_Q4_CountyProfile
    WHERE boa_status = 'No branch'
)
SELECT v.county_name,
       v.deposit_rank,
       v.bank_name,
       v.branches,
       v.deposits_k,              -- thousands of dollars
       v.market_share_pct
FROM cln.vw_BankCountyYear v
JOIN no_boa n ON n.county_fips = v.county_fips
WHERE v.sod_year = (SELECT MAX(sod_year) FROM cln.SOD_Branch)
  AND v.deposit_rank <= 3
ORDER BY v.county_name, v.deposit_rank;

-- Result 2: how many different banks have a branch in each of those counties,
-- in the first and last years. A falling number means fewer choices for residents.
-- The yrs CTE holds the first and last years. CROSS JOIN gives every row those two
-- values as plain columns, because COUNT cannot contain a subquery.
WITH no_boa AS (
    SELECT county_fips
    FROM cln.vw_Q4_CountyProfile
    WHERE boa_status = 'No branch'
),
yrs AS (
    SELECT MIN(sod_year) AS y0, MAX(sod_year) AS y1
    FROM cln.SOD_Branch
)
SELECT v.county_name,
       COUNT(DISTINCT CASE WHEN v.sod_year = yrs.y0 THEN v.cert END) AS banks_2010,
       COUNT(DISTINCT CASE WHEN v.sod_year = yrs.y1 THEN v.cert END) AS banks_2026
FROM cln.vw_BankCountyYear v
JOIN no_boa n ON n.county_fips = v.county_fips
CROSS JOIN yrs
GROUP BY v.county_name
ORDER BY v.county_name;
GO

/*-------------------------------------------------------------------------------The End---------------------------------------------------------------------------------------------------------------*/