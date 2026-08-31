-- Sales & Weather | MySQL 8 | see README.md for the full pipeline order.
-- 06 - Query optimization: EXPLAIN ANALYZE diagnostics, composite and covering indexes.

-- ================================================================================
-- PERFORMANCE OPTIMIZATION: Sales Analysis under Clear Weather Conditions
--
-- GOAL:
--   to analyze the average sales per region specifically when the weather is 
--   described as 'sky is clear'. This helps assess if sales perform better 
--   in sunny, favorable conditions.
--
-- CHALLENGE:
--   The original query performs a full index scan on `sales_weather_clean`, 
--   evaluating thousands of rows but using only a portion (43%) of them, 
--   resulting in unnecessary resource usage and slower performance.
--
-- STRATEGY:
--   Use `EXPLAIN ANALYZE` to assess query cost and identify inefficiencies.
--   Then improve performance by creating targeted indexes.
-- ================================================================================

-- STEP 1: Performance Diagnostics with EXPLAIN ANALYZE
EXPLAIN ANALYZE
SELECT /*+ SET_VAR(max_execution_time=30000) */
    region,
    AVG(sales) AS avg_sales
FROM sales_data.sales_weather_clean
WHERE weather_description = 'sky is clear'
GROUP BY region;

-- SAMPLE PLAN OUTPUT:
-- -> Group aggregate: avg(sales_weather_clean.sales)
--    (cost=411 rows=4) (actual time=7.96..12.5 rows=4 loops=1)
--     -> Filter: (weather_description = 'sky is clear')
--        (cost=376 rows=352) (actual time=2.07..12.1 rows=1563 loops=1)
--         -> Index scan on sales_weather_clean using idx_region
--            (cost=376 rows=3515) (actual time=1.99..11.5 rows=3616 loops=1)

-- INTERPRETATION:
--   Although an index is used (`idx_region`), it's not selective enough.
--   The table reads over 3,600 rows but keeps only 1,563 (~43%) — not efficient.

-- STEP 2: Create a Composite Index to Improve Filtering Efficiency
--   This index helps by covering both the `weather_description` used in WHERE 
--   and the `region` used in GROUP BY.

CREATE INDEX idx_weather_region ON sales_weather_clean (weather_description, region);

-- FURTHER OPTIMIZATION:
--   Add `sales` to the index if you're aggregating it directly,
--   enabling index-only scans in some DBMS.

CREATE INDEX idx_weather_region_sales ON sales_weather_clean 
(weather_description, region, sales);

-- STEP 3: Run the Original Query Again After Index Creation
--   Expecting faster performance now due to the better use of filtered index.

EXPLAIN ANALYZE
SELECT 
    region,
    AVG(sales) AS avg_sales
FROM sales_weather_clean
WHERE weather_description = 'sky is clear'
GROUP BY region;

-- STEP 4: Force the Index (Optional - only if the DBMS does not pick the new index automatically)

-- This query hints to MySQL to use the index we just created
EXPLAIN ANALYZE
SELECT /*+ INDEX(swc idx_weather_region) */
    region,
    AVG(sales) AS avg_sales
FROM sales_weather_clean swc
WHERE weather_description = 'sky is clear'
GROUP BY region;

-- OPTIONAL: Create a View for Reusability
-- You could encapsulate this analysis in a view for further reporting

CREATE OR REPLACE VIEW avg_sales_by_clear_weather AS
SELECT 
    region,
    AVG(sales) AS avg_sales
FROM sales_weather_clean
WHERE weather_description = 'sky is clear'
GROUP BY region;

-- Now this is accessible via:
SELECT * FROM avg_sales_by_clear_weather;

