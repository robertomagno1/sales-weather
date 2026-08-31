-- Sales & Weather | MySQL 8 | see README.md for the full pipeline order.
-- 02 - ETL: weather view/table and the date-parsed join between orders and weather.

-- =======================================================================
-- SECTION: Weather Data Integration and Join with Sales Orders
-- DESCRIPTION:
--   In this section, we consolidate weather data from multiple sources—
--   temperature, humidity, and description—into a single structure.
--   This enables us to  join weather conditions correctly with sales data 
--   and perform analysis based on both weather and sales factors.
-- =======================================================================

-- Here we start creating a combined view (for quick reference) that joins weather components
-- Note: This query could be turned into a materialized table if performance is needed
-- CREATE VIEW sales_data.combined_weather AS
SELECT 
    t.date,
    t.city,
    t.temperature,
    h.humidity,
    d.description
FROM 
    sales_data.temperature t
JOIN 
    sales_data.humidity h ON t.date = h.date AND t.city = h.city
JOIN 
    sales_data.description d ON t.date = d.date AND t.city = h.city;

-- Create a materialized version of the above using LEFT JOINs
-- Purpose: Ensure we don't lose temperature rows even if humidity or description is missing
CREATE TABLE combined_weather1 AS
SELECT 
    t.city,
    t.date,
    t.temperature,
    h.humidity,
    d.description
FROM 
    temperature t
LEFT JOIN 
    humidity h ON t.city = h.city AND t.date = h.date
LEFT JOIN 
    description d ON t.city = d.city AND t.date = d.date;

-- Count how many records we successfully aggregated into the combined table
SELECT COUNT(*) FROM combined_weather1;

-- Benchmark query performance
-- This helps us evaluate how efficiently queries run on the combined table
EXPLAIN ANALYZE SELECT * FROM combined_weather1;




-- =======================================================================
-- SECTION: Join Sales with Weather
-- DESCRIPTION:
--   Here, we create a new table `sales_weather` by joining weather data
--   to sales orders using city and date. Since order dates are stored
--   as strings in the `orders_raw` table, we convert them on the fly.
--   This join enables advanced sales analysis based on daily weather.
-- =======================================================================

CREATE TABLE sales_weather AS 
SELECT 
  o.*, 
  w.temperature, 
  w.humidity, 
  w.description
FROM 
  sales_data.orders_raw o
INNER JOIN sales_data.weather_condition w 
  ON STR_TO_DATE(o.order_date, '%d/%m/%y') = w.date  -- Convert string to date for accurate join
  AND o.city = w.city;

-- Performance Check: Time it takes to read from the full joined table
EXPLAIN ANALYZE SELECT * FROM sales_weather;  -- ~0.15 sec

-- How many rows were generated from the join?
SELECT COUNT(*) FROM sales_weather;  -- Good to validate row integrity



