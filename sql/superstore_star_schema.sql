/* ================================================
SUPERSTORE STAR SCHEMA — MySQL build script
Method: Staging table -> Dimension tables -> Fact table Author: built step-by-step. 
   ================================================ */

/* STEP 0: Database */

CREATE DATABASE IF NOT EXISTS superstore_dw;
USE superstore_dw;

/* STEP 1: STAGING TABLE
   Purpose: land the CSV exactly as it is, zero transformation. */

DROP TABLE IF EXISTS stg_superstore;
CREATE TABLE stg_superstore (
    row_id        INT,
    order_id      VARCHAR(20),
    order_date    DATE,
    ship_date     DATE,
    ship_mode     VARCHAR(20),
    customer_id   VARCHAR(20),
    customer_name VARCHAR(100),
    segment       VARCHAR(20),
    country       VARCHAR(50),
    city          VARCHAR(50),
    state         VARCHAR(50),
    postal_code   VARCHAR(10),
    region        VARCHAR(20),
    product_id    VARCHAR(20),
    category      VARCHAR(30),
    sub_category  VARCHAR(30),
    product_name  VARCHAR(255),
    sales         DECIMAL(10,4),
    quantity      INT,
    discount      DECIMAL(4,2),
    profit        DECIMAL(10,4)
);

/* STEP 2: LOAD THE CSV — using LOAD DATA LOCAL INFILE */

LOAD DATA LOCAL INFILE '/path/to/Sample_-_Superstore.csv'
INTO TABLE stg_superstore
CHARACTER SET latin1
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 ROWS
(row_id, order_id, @order_date, @ship_date, ship_mode, customer_id,
 customer_name, segment, country, city, state, postal_code, region,
 product_id, category, sub_category, product_name, sales, quantity,
 discount, profit)
SET
    order_date = STR_TO_DATE(@order_date, '%m/%d/%Y'),
    ship_date  = STR_TO_DATE(@ship_date,  '%m/%d/%Y');

/* Must return 9994 */

SELECT COUNT(*) AS staging_row_count FROM stg_superstore;
/* Must return 0 */
SELECT COUNT(*) FROM stg_superstore WHERE order_date IS NULL OR ship_date IS NULL;


/* ================================================
STEP 3: DIM_DATE
Rule: a Power BI date table must be CONTINUOUS — every single calendar day between your earliest and latest date, even days with zero sales.
   ================================================= */

DROP TABLE IF EXISTS dim_date;
CREATE TABLE dim_date (
    `date`       DATE PRIMARY KEY,
    year         INT,
    quarter      INT,
    month        INT,
    month_name   VARCHAR(10),
    day          INT,
    day_name     VARCHAR(10),
    week_of_year INT,
    is_weekend   TINYINT
);

/* Allow enough recursion for a multi year date range */

SET SESSION cte_max_recursion_depth = 10000;

INSERT INTO dim_date (`date`)
WITH RECURSIVE date_range AS (
    SELECT (SELECT MIN(order_date) FROM stg_superstore) AS dt
    UNION ALL
    SELECT dt + INTERVAL 1 DAY
    FROM date_range
    WHERE dt + INTERVAL 1 DAY <= (SELECT MAX(ship_date) FROM stg_superstore)
)
SELECT dt FROM date_range;

/* Populate the descriptive columns after the fact (cheaper than computing them row by row during the recursive insert) */

UPDATE dim_date
SET
    year         = YEAR(`date`),
    quarter      = QUARTER(`date`),
    month        = MONTH(`date`),
    month_name   = MONTHNAME(`date`),
    day          = DAY(`date`),
    day_name     = DAYNAME(`date`),
    week_of_year = WEEK(`date`, 3),
    is_weekend   = CASE WHEN DAYOFWEEK(`date`) IN (1,7) THEN 1 ELSE 0 END;


/* =============================================
STEP 4: DIM_PRODUCT
Product ID is NOT a reliable unique key. 
The same Product ID occasionally appears with a different Product Name due to data entry inconsistency in the source file. If product_id is assigned as the primary key,the INSERT will throw a duplicate key error or silently drop rows.
Fix: surrogate key (product_key, auto incrementing int) as the real primary key. product_id stays as a plain attribute.
   ============================================== */
DROP TABLE IF EXISTS dim_product;
CREATE TABLE dim_product (
    product_key  INT AUTO_INCREMENT PRIMARY KEY,
    product_id   VARCHAR(20),
    product_name VARCHAR(255),
    category     VARCHAR(30),
    sub_category VARCHAR(30)
);

INSERT INTO dim_product (product_id, product_name, category, sub_category)
SELECT DISTINCT product_id, product_name, category, sub_category
FROM stg_superstore;

/* Run this query to audit variants — expect a non zero count */

SELECT product_id, COUNT(DISTINCT product_name) AS name_variants
FROM stg_superstore
GROUP BY product_id
HAVING COUNT(DISTINCT product_name) > 1;


/* ==============================================
   STEP 5: DIM_CUSTOMER

   =============================================== */

DROP TABLE IF EXISTS dim_customer;
CREATE TABLE dim_customer (
    customer_key  INT AUTO_INCREMENT PRIMARY KEY,
    customer_id   VARCHAR(20),
    customer_name VARCHAR(100),
    segment       VARCHAR(20)
);

INSERT INTO dim_customer (customer_id, customer_name, segment)
SELECT DISTINCT customer_id, customer_name, segment
FROM stg_superstore;


/* ============================================
STEP 6: DIM_GEOGRAPHY_CITY
Grain = one row per distinct city/state/country combination.
An earlier version of this table included postal_code in the DISTINCT, which produced multiple rows per city (Chicago alone had 3 — one per ZIP),because ZIP level detail was not required for the analytical metrics.
   =============================================== */

DROP TABLE IF EXISTS dim_geography_city;
CREATE TABLE dim_geography_city (
    geography_key INT AUTO_INCREMENT PRIMARY KEY,
    country       VARCHAR(50),
    region        VARCHAR(20),
    state         VARCHAR(50),
    city          VARCHAR(50)
);

INSERT INTO dim_geography_city (country, region, state, city)
SELECT DISTINCT country, region, state, city
FROM stg_superstore;

/* Verify the grain is clean before downstream joins — must return 0 rows. */
SELECT country, region, state, city, COUNT(*)
FROM dim_geography_city
GROUP BY country, region, state, city
HAVING COUNT(*) > 1;


/* ==============================================
   STEP 7: FACT_SALES
Grain = one row per Row ID (one line item per order), matching the source exactly.
order_date and ship_date BOTH reference dim_date. This is a "role playing dimension" - one dimension table serving two different roles in the fact table. 
In Power BI, only ONE of these relationships can be active at a time; the inactive one needs USERELATIONSHIP() in DAX or a second, duplicated date
table (dim_ship_date) to keep both active simultaneously.
   ================================================ */

DROP TABLE IF EXISTS fact_sales;
CREATE TABLE fact_sales (
    row_id        INT PRIMARY KEY,
    order_id      VARCHAR(20),
    order_date    DATE,
    ship_date     DATE,
    ship_mode     VARCHAR(20),
    customer_key  INT,
    product_key   INT,
    geography_key INT,
    sales         DECIMAL(10,4),
    quantity      INT,
    discount      DECIMAL(4,2),
    profit        DECIMAL(10,4),
    FOREIGN KEY (order_date)    REFERENCES dim_date(`date`),
    FOREIGN KEY (ship_date)     REFERENCES dim_date(`date`),
    FOREIGN KEY (customer_key)  REFERENCES dim_customer(customer_key),
    FOREIGN KEY (product_key)   REFERENCES dim_product(product_key),
    FOREIGN KEY (geography_key) REFERENCES dim_geography_city(geography_key)
);

/* Populate by joining staging back to each dimension to resolve the surrogate keys. Every JOIN condition matches on the Same combination of columns used to build that dimension's DISTINCT. */

INSERT INTO fact_sales (
    row_id, order_id, order_date, ship_date, ship_mode,
    customer_key, product_key, geography_key,
    sales, quantity, discount, profit
)
SELECT
    s.row_id, s.order_id, s.order_date, s.ship_date, s.ship_mode,
    c.customer_key, p.product_key, g.geography_key,
    s.sales, s.quantity, s.discount, s.profit
FROM stg_superstore s
JOIN dim_customer c
    ON c.customer_id = s.customer_id AND c.segment = s.segment
JOIN dim_product p
    ON p.product_id = s.product_id
   AND p.product_name = s.product_name
   AND p.category = s.category
   AND p.sub_category = s.sub_category
JOIN dim_geography_city g
    ON g.country = s.country AND g.region = s.region
   AND g.state = s.state AND g.city = s.city;


/* ==============================================
   STEP 8: VERIFY — Data Integrity Validation
   ============================================== */

/* Row counts must match staging exactly (9994) */

SELECT
    (SELECT COUNT(*) FROM stg_superstore) AS staging_rows,
    (SELECT COUNT(*) FROM fact_sales)     AS fact_rows;

/* Zero orphan rows expected — if any of these return > 0, a JOIN condition above requires review */

SELECT COUNT(*) FROM stg_superstore s
LEFT JOIN dim_customer c ON c.customer_id = s.customer_id AND c.segment = s.segment
WHERE c.customer_key IS NULL;

SELECT COUNT(*) FROM stg_superstore s
LEFT JOIN dim_product p ON p.product_id = s.product_id AND p.product_name = s.product_name
WHERE p.product_key IS NULL;

SELECT COUNT(*) FROM stg_superstore s
LEFT JOIN dim_geography_city g
    ON g.country = s.country AND g.region = s.region
   AND g.state = s.state AND g.city = s.city
WHERE g.geography_key IS NULL;

/* Total sales must match between staging and fact to confirm no rows were dropped or duplicated during execution */

SELECT
    (SELECT ROUND(SUM(sales),2) FROM stg_superstore) AS staging_total_sales,
    (SELECT ROUND(SUM(sales),2) FROM fact_sales)     AS fact_total_sales;
