-- Sales & Weather | MySQL 8 | see README.md for the full pipeline order.
-- 04 - Target model: typed columns, NOT NULL/CHECK constraints, 7 secondary indexes,
--      data-quality checks (duplicate row_id, NULLs) and order-line grain rationale.

-- ============================================================================
-- DATE FORMAT OPTIMIZATION: Adding Permanent DATE Columns to orders_raw Table
-- Purpose:
--   The original dataset stored dates as strings (VARCHAR), which is inefficient
--   and problematic for date operations (like filtering, joins, ordering).
-- 
--   This block adds proper DATE columns and populates them using STR_TO_DATE,
--   which allows optimized and error-proof queries on temporal data.
-- ============================================================================

-- Add a new column for properly formatted order dates
ALTER TABLE sales_data.orders_raw 
ADD COLUMN order_date_proper DATE;

-- Populate the new column by converting existing string dates 
-- Format used: '%d/%m/%y' (example: '25/12/14' → 2014-12-25)
UPDATE sales_data.orders_raw 
SET order_date_proper = STR_TO_DATE(order_date, '%d/%m/%y');

-- Add a new column for proper ship dates as well
ALTER TABLE orders_raw 
ADD COLUMN ship_date_proper DATE;

-- [CORRECTION] Remove mistakenly named column (if created during tests)
ALTER TABLE orders_raw
DROP COLUMN shiop_date_proper;

-- Populate the new shipping date column by converting the string-based field
UPDATE orders_raw 
SET ship_date_proper = STR_TO_DATE(ship_date, '%d/%m/%y');


-- View the updated records to verify proper date conversion
SELECT * 
FROM sales_data.orders_raw;

-- ============================================================================
-- VIEW CREATION: Simplified and Cleaned Orders View
-- Purpose:
--   This view exposes only clean and necessary fields from the raw orders table,
--   using the newly formatted date columns for reliable analysis and joins.
--   It's useful for analysts to work on clean data without affecting raw inputs.
-- ============================================================================

CREATE OR REPLACE VIEW sales_data.orders_raw_view AS
SELECT 
    row_id,
    order_id,
    order_date_proper,          -- Clean and properly typed order date
    ship_date_proper,           -- Clean and properly typed shipping date
    ship_mode,
    customer_id,
    customer_name,
    segment,
    country,
    city,
    state,
    postal_code,
    region,
    product_id,
    category,
    sub_category,
    product_name,
    sales,
    quantity,
    discount,
    profit
FROM 
    sales_data.orders_raw;

UPDATE orders_raw 
SET ship_date_proper = STR_TO_DATE(ship_date, '%d/%m/%y');





-- ============================================================================
-- TABLE: sales_weather_clean
-- PROJECT: Sales + Weather Data Integration
-- PURPOSE:
--   This table is an optimized, cleaned, and enriched version of the original 
--   sales-weather joined dataset. It is designed to enable faster, more reliable 
--   analytical queries by ensuring:
--     - Correct data types (of course :  proper DATE fields)
--     - Integrity constraints for data consistency
--     - Strategic indexes for performance optimization
-- ============================================================================

CREATE TABLE IF NOT EXISTS sales_data.sales_weather_clean (
    row_id VARCHAR(50) NOT NULL,                  -- Internal row identifier
    order_id VARCHAR(50) NOT NULL,                -- Sales order ID (can repeat for multi-product orders , in this case see up...)
    order_date DATE NOT NULL,                     -- Properly formatted order date
    ship_date DATE,                               -- Properly formatted shipping date
    ship_mode VARCHAR(50),                        -- Shipping method (as:  Standard Class)
    customer_id VARCHAR(50) NOT NULL,             -- Unique customer identifier
    customer_name VARCHAR(100) NOT NULL,          -- Full name of the customer
    segment VARCHAR(50),                          -- Customer segment (like  Consumer, Corporate)
    country VARCHAR(50) NOT NULL,                 -- Country of customer (assumed to be consistent)
    city VARCHAR(50) NOT NULL,                    -- City of customer (used to join with weather data)
    state VARCHAR(50),                            -- State/Province
    postal_code VARCHAR(20),                      -- Postal code (supports international formats)
    region VARCHAR(50),                           -- Region classification
    product_id VARCHAR(50) NOT NULL,              -- Unique product identifier
    category VARCHAR(50),                         -- Product category (e.g., Office Supplies)
    sub_category VARCHAR(50),                     -- More specific product category
    product_name VARCHAR(200),                    -- Product full name
    sales DECIMAL(10,2) NOT NULL,                 -- Total sales amount
    quantity INT NOT NULL CHECK (quantity > 0),   -- Quantity must be > 0
    discount DECIMAL(5,2) CHECK (discount >= 0 AND discount <= 1),  -- Discount percentage (0 to 1)
    profit DECIMAL(10,2),                         -- Profit from this transaction

    -- Weather-related attributes
    temperature DECIMAL(10,2),                    -- recorded temperature on the order date
    humidity DECIMAL(10,2),                       -- Recorded humidity on the order date
    weather_description VARCHAR(50),              -- Textual weather condition ( for example :  "Sky is Clear")

    -- PERFORMANCE OPTIMIZATION: Adding indexes for frequent filters and joins
    INDEX idx_order_id (order_id),
    INDEX idx_customer (customer_id),
    INDEX idx_product (product_id),
    INDEX idx_city (city),
    INDEX idx_order_date (order_date),
    INDEX idx_state (state),
    INDEX idx_region (region)
);

-- ============================================================================
-- POPULATE TABLE: Load Cleaned and Formatted Data
-- PURPOSE:
--   We populate the new optimized table from the temporary table ⁠ sales_weather ⁠,
--   making sure to convert the ⁠ order_date ⁠ and ⁠ ship_date ⁠ from string to DATE format,
--   and rename the weather field to a more readable name (⁠ weather_description ⁠).
-- ============================================================================

INSERT INTO sales_data.sales_weather_clean (
    row_id,
    order_id,
    order_date,
    ship_date,
    ship_mode,
    customer_id,
    customer_name,
    segment,
    country,
    city,
    state,
    postal_code,
    region,
    product_id,
    category,
    sub_category,
    product_name,
    sales,
    quantity,
    discount,
    profit,
    temperature,
    humidity,
    weather_description
)
SELECT 
    row_id,
    order_id,
    STR_TO_DATE(order_date, '%d/%m/%y'),    -- Convert string to proper DATE for querying
    STR_TO_DATE(ship_date, '%d/%m/%y'),     -- Same for shipping date
    ship_mode,
    customer_id,
    customer_name,
    segment,
    country,
    city,
    state,
    postal_code,
    region,
    product_id,
    category,
    sub_category,
    product_name,
    sales,
    quantity,
    discount,
    profit,
    temperature,
    humidity,
    description AS weather_description       -- Renaming for clarity
FROM sales_data.sales_weather;





-- ============================================================================
-- DATA VALIDATION & CLEANING: sales_weather_clean
-- PURPOSE:
--   This section focuses on verifying data quality within the optimized table 
--   ⁠ sales_weather_clean ⁠. The goals are:
--     1. Identify and handle duplicate records (for ⁠row_id ⁠)
--     2. Ensure there are no NULLs in critical columns like ⁠ row_id ⁠
--     3. Investigate why ⁠ order_id ⁠ cannot be used as a PRIMARY KEY
-- ============================================================================

--   1: Check for duplicate row_id values
--    While ⁠ row_id ⁠ should ideally be unique, this check helps confirm if 
--    accidental duplication has occurred ( due to joins or multiple inserts).
SELECT 
    row_id, 
    COUNT(*) AS duplicate_count
FROM sales_data.sales_weather_clean
GROUP BY row_id
HAVING COUNT(*) > 1
LIMIT 10;

-- INSIGHT: Only 2 duplicate row_ids were found.
--    These should be manually reviewed and removed if necessary to ensure data consistency.

--   2: Check for NULL values in the ⁠ row_id ⁠ field
--    We want to confirm that all rows have a valid row identifier.
SELECT COUNT(*) 
FROM sales_data.sales_weather_clean 
WHERE row_id IS NULL;

-- RESULT: Zero NULL values were found. This means all rows have valid identifiers.

--  3: Remove the specific rows identified as duplicates
--    (Note: Not shown here, but you would use DELETE with a WHERE condition 
--    or use ROW_NUMBER in a CTE to retain only the first instance.)

-- ============================================================================
-- PERFORMANCE TEST: Evaluate execution speed of full table scan
--    The goal is to ensure that our optimizations (indexing) are effective.
-- ============================================================================

-- Measure the execution plan and timing for a full table read
EXPLAIN ANALYZE SELECT * FROM sales_weather_clean;

-- Example Result: 0.08 sec (previous version without indexes took nearly twice as long)

-- Quick check: How many rows are in the optimized table?
SELECT COUNT(*) FROM sales_weather_clean;

-- ============================================================================
-- 🔍 BONUS VALIDATION: Why ⁠ order_id ⁠ cannot be UNIQUE
-- CONTEXT:
--   In a real sales system, a single order (order_id) may contain multiple products.
--   Therefore, order_id can repeat across rows — it's not a good candidate for PRIMARY KEY.
-- ============================================================================

-- Check how many order_ids appear more than once
SELECT 
    order_id, 
    COUNT(*) AS cnt
FROM sales_data.sales_weather
GROUP BY order_id
HAVING cnt > 1
ORDER BY cnt DESC;

-- RESULT: Many order_ids appear multiple times.
--    Example: An order with 3 different items will result in 3 separate rows,
--    all sharing the same ⁠ order_id ⁠ but differing in ⁠ product_id ⁠ and details.
--    ➤ This is why we avoided setting ⁠ order_id ⁠ as a UNIQUE constraint or PRIMARY KEY.






