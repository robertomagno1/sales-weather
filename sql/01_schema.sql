-- Sales & Weather | MySQL 8 | see README.md for the full pipeline order.
-- 01 - Schema: staging table for orders, weather tables with composite PKs and indexes.

-- =====================================================================================
-- PROJECT: Sales & Weather Analysis
-- DATABASE: sales1 
-- DESCRIPTION: 
--   This project integrates two distinct datasets—sales data and 
--   weather conditions—with the goal of enabling insightful queries 
--   that correlate weather patterns with sales performance.
--   
--   The primary objective is to understand how different weather 
--   conditions impact sales, such as whether rainy days reduce 
--   customer purchases, or if certain products sell more in specific 
--   weather scenarios.
--
--   This part of the schema defines the `orders` table, which contains 
--   detailed sales records including customer information, product 
--   details, and transactional metrics.
--
--   A separate `weather` table will later be introduced and linked 
--   to this table via shared temporal (and potentially geographic) 
--   fields like `order_date` and `city` or `state`, allowing us 
--   to perform meaningful joins and analyses.
-- =====================================================================================



-- Create the project database if it doesn't already exist
CREATE DATABASE IF NOT EXISTS sales_data;

-- Create the raw orders table to hold imported sales data: 
CREATE TABLE IF NOT EXISTS sales_data.orders_raw (
    row_id INT,  -- Internal unique identifier for each row
    order_id VARCHAR(50),  -- Unique order code (may repeat if multiple items in one order; see below...)
    order_date VARCHAR(20),   -- Stored as string for format compatibility during import, (see below for optimization ...)
    ship_date VARCHAR(20),   -- Same as above for shipping date
    ship_mode VARCHAR(50),  -- How the order was shipped (first and  Standard Class)
    customer_id VARCHAR(50),  -- Unique ID for each customer
    customer_name VARCHAR(100),  -- Full name of the customer
    segment VARCHAR(50),  -- Market segment (like :  Consumer, Corporate)
    country VARCHAR(50),  -- Customer country
    city VARCHAR(50),  -- Customer city (we will use it for joining with weather data)
    state VARCHAR(50),  -- Customer state/province
    postal_code VARCHAR(20),  -- String format compatibility
    region VARCHAR(50),  -- Sales region (e.g., West, South)
    product_id VARCHAR(50),  -- Unique identifier for the product
    category VARCHAR(50),  -- Main product category
    sub_category VARCHAR(50),  -- More specific sub-category
    product_name VARCHAR(200),  -- Full descriptive name of the product
    sales DECIMAL(10,2),  -- Amount of money from the sale
    quantity INT,  -- Number of items sold
    discount DECIMAL(5,2),  -- Discount applied (0.2 for 20%)
    profit DECIMAL(10,2)  -- Profit from the transaction
);



-- =======================================================================
-- SECTION: Weather Table Creation and Uniqueness Check for Order IDs
-- DESCRIPTION:
--   This section begins with a query to inspect the raw sales orders and
--   to verify whether the ⁠ order_id ⁠ can be used as a unique primary key.
--   It turns out that multiple products can be sold under the same order,
--   so ⁠ order_id ⁠ cannot be unique in this context.
--
--   Then, we create three key tables that store weather data:
--     1. temperature
--     2. humidity
--     3. description
--   Each table uses a composite primary key based on ⁠ date ⁠ and ⁠ city ⁠,
--   allowing for accurate matching between weather records and sales events.
--   Indexes are added to improve query performance during joins and filtering.


-- =======================================================================



-- Inspect the contents of the raw orders
SELECT * FROM sales1.orders_raw;

-- Check for non-unique order_ids
-- This reveals whether a single order ID may appear more than once
-- (e.g., when a customer buys multiple items in one purchase)
-- PRIMARY KEYS must be UNIQUE and NOT NULL, so we validate this here
SELECT order_id, COUNT(*) AS cnt
FROM sales_data.sales_weather
GROUP BY order_id
HAVING cnt > 1
ORDER BY cnt DESC;


-- =======================================================================
-- Temperature Table : 
-- Captures daily average temperature data for each city
-- Composite key ensures uniqueness for (date, city) combinations
-- Indexes support fast lookup by city or date
-- =======================================================================

CREATE TABLE temperature (
    date DATE NOT NULL,
    city VARCHAR(50) NOT NULL,
    temperature DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (date, city),
    INDEX idx_city (city),
    INDEX idx_date (date)
);

-- Humidity Table : 
-- Stores relative humidity readings per city per day
-- Same structure and indexing strategy as the temperature table
CREATE TABLE humidity (
    date DATE NOT NULL,
    city VARCHAR(50) NOT NULL,
    humidity DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (date, city),
    INDEX idx_city (city),
    INDEX idx_date (date)
);

-- Weather Description Table : 
-- Records qualitative descriptions like 'Sunny', 'Rainy', etc.
-- Follows same schema structure for consistency
CREATE TABLE description (
    date DATE NOT NULL,
    city VARCHAR(50) NOT NULL,
    description VARCHAR(50),
    PRIMARY KEY (date, city),
    INDEX idx_city (city),
    INDEX idx_date (date)
);


