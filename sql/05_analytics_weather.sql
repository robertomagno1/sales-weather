-- Sales & Weather | MySQL 8 | see README.md for the full pipeline order.
-- 05 - Analytics Q11-Q19: product/sub-category performance conditioned on weather.

-- ============================================================================
-- QUERY 11: Sub-Category Product Performance by Weather Type
-- PURPOSE:
--   This query analyzes how different weather conditions influence product 
--   performance at the sub-category level. By combining sales and weather data, 
--   we can identify which sub-categories perform best under specific 
--   weather descriptions (like :  "Rain", "Sunny", and more ....)
--
--   This kind of analysis can support data-driven decisions like:
--     - targeted promotions based on forecasted weather
--     - optimizing inventory during certain climate conditions
--     - identifying product trends tied to seasonal weather
-- ============================================================================

SELECT 
    w.description AS weather_type,          -- Describes the weather condition (e.g., "Cloudy", "Clear")
    o.sub_category,                         -- Product sub-category from sales data
    COUNT(*) AS order_count,                -- Number of orders in this sub-category under this weather type
    SUM(o.quantity) AS total_units,         -- Total quantity of units sold
    ROUND(SUM(o.sales), 2) AS total_sales   -- Total sales amount, rounded to 2 decimals
FROM 
    sales_data.orders_raw_view o            -- View of the cleaned orders table
JOIN (
    -- Subquery extracts only relevant columns from the weather dataset
    SELECT date, city, description 
    FROM sales_data.weather_condition
) w 
    ON o.order_date_proper = w.date         -- Match by date
    AND o.city = w.city                     -- Match by city
GROUP BY 
    w.description,                          -- Group by weather type
    o.sub_category                          -- And by product sub-category
ORDER BY 
    total_sales DESC                        -- Prioritize by highest-selling sub-categories
LIMIT 10;                                   -- Return only the top 10 combinations





-- ============================================================================
-- QUERY 12: Category-Level Product Performance by Weather Type
-- PURPOSE:
--   This query extends the analysis of product sales by weather condition, 
--   focusing on higher-level product categories (as : Furniture, Technology).
--
--   While Query 11 analyzed sub-categories, here we generalize to observe 
--   broader trends—such as whether entire product categories perform better 
--   under certain weather types.
--
--   This is useful to:
--     - Assess demand shifts by weather at the category level
--     - Identify weather-related purchasing behavior on a macro scale
--     - Guide strategic planning for marketing and logistics
-- ============================================================================

SELECT 
    w.description,                  
    o.category,                     -- High-level product category 
    COUNT(*) AS orders,             -- Number of transactions (rows) matching the condition
    SUM(o.quantity) AS items_sold   -- Total quantity sold across all orders
FROM 
    sales_data.orders_raw_view o,   -- Main view containing cleaned order data
    (
        SELECT date, city, description 
        FROM sales_data.weather_condition
    ) w                             -- Inline subquery to extract weather info by date and city
WHERE 
    o.order_date_proper = w.date    -- Match sales with weather by date
    AND o.city = w.city             -- Match by city
GROUP BY 
    w.description, o.category       -- Group by weather condition and product category
ORDER BY 
    items_sold DESC;                -- Show categories with highest unit sales first
    
    
    

-- ============================================================================
-- QUERY 13: Top 5 Best-Selling Products per Weather Condition
-- PURPOSE:
--   This query identifies the top 5 products (in terms of total sales) 
--   for each distinct weather condition. It helps answer questions like:
--     - What do people buy most often when it's sunny, rainy, or foggy?
--     - Are there product trends tied to specific weather patterns?
--
--   The goal is to uncover weather-based purchasing preferences 
--   at the product level, useful for seasonal marketing or inventory planning.
--
--   This is accomplished using a window function (RANK) to assign 
--   product rankings within each weather group.
-- ============================================================================

SELECT *
FROM (
    SELECT 
        weather_description,                          -- e.g., "Clear sky", "Rain", etc.
        product_name,                                 -- Full name of the product
        category,                                     -- High-level product category
        sub_category,                                 -- More granular product category
        SUM(sales) AS total_sales,                    -- Total revenue for the product
        SUM(quantity) AS total_quantity,              -- Number of units sold
        RANK() OVER (
            PARTITION BY weather_description 
            ORDER BY SUM(sales) DESC
        ) AS rank_within_weather                      -- Rank products within each weather group
    FROM sales_data.sales_weather_clean
    WHERE weather_description IS NOT NULL             -- Exclude records without weather info
    GROUP BY 
        weather_description, product_name, 
        category, sub_category
) ranked_products
WHERE rank_within_weather <= 5                         -- Filter to top 5 products per weather type
ORDER BY 
    weather_description, total_sales DESC;            -- Final sorted output for clarity
    
    
-- ============================================================================
-- QUERY 14: Most Profitable Temperature and Humidity Combinations
-- PURPOSE:
--   This query investigates which specific combinations of temperature and 
--   humidity are associated with the highest total sales and profits.
--
--   The goal is to determine whether certain climate conditions are more 
--   conducive to increased purchasing behavior, which can be highly valuable 
--   for marketing, supply chain, or retail strategy planning.
--
-- STRATEGY:
--   - We round temperature and humidity to whole numbers to create manageable 
--     buckets (e.g., 22.4°C and 22.6°C both round to 22°C).
--   - We count the number of orders per unique (temp, humidity) pair.
--   - We calculate both total sales and total profit per group.
--   - We sort results by ⁠ total_sales ⁠ in descending order to find the best-performing ranges.
-- ============================================================================

SELECT 
    ROUND(temperature, 0) AS temp_rounded,       -- Round temperature to nearest integer
    ROUND(humidity, 0) AS humidity_rounded,      -- Round humidity to nearest integer
    COUNT(*) AS num_orders,                      -- Number of sales transactions in this climate
    SUM(sales) AS total_sales,                   -- Total revenue generated
    SUM(profit) AS total_profit                  -- Total profit generated
FROM sales_data.sales_weather_clean
WHERE 
    temperature IS NOT NULL AND 
    humidity IS NOT NULL                         -- Filter out any incomplete climate data
GROUP BY 
    temp_rounded, 
    humidity_rounded                             -- Group by each (temperature, humidity) pair
ORDER BY 
    total_sales DESC                             -- Show most profitable combinations first
LIMIT 100;                                       -- Limit to top 100 rows for readability


-- temperature from 268 to 299 , humidity from 48 to 86 


-- ============================================================================
-- QUERY 15: Weather Conditions for the Best-Performing Product
-- PURPOSE:
--   This query identifies the best-selling product (based on total sales),
--   and then analyzes the average weather conditions (temperature, humidity,
--   and description) under which it was sold.
--
--   The goal is to discover possible weather-related trends or correlations 
--   for the top-performing product. This is useful for forecasting, 
--   targeted promotions, or climate-aware stock management.
-- ============================================================================

-- STEP 1: Identify the best-selling product overall
WITH best_seller AS (
    SELECT product_name
    FROM sales_data.sales_weather_clean
    GROUP BY product_name
    ORDER BY SUM(sales) DESC  -- Order products by total sales (descending)
    LIMIT 1                   -- Pick the top 1 product
)

-- STEP 2: Analyze average weather for the best-seller
SELECT 
    b.product_name,                            -- Return the product name (from CTE)
    AVG(temperature) AS avg_temp,              -- Average temperature during its sales
    AVG(humidity) AS avg_humidity,             -- Average humidity during its sales
    weather_description,                       -- Weather description (e.g. clear sky, rain)
    COUNT(*) AS order_count,                   -- Number of orders placed for the product
    SUM(sales) AS total_sales                  -- Total sales value for this product
FROM sales_data.sales_weather_clean s
JOIN best_seller b 
  ON s.product_name = b.product_name           -- Only include rows for the best-selling product
WHERE 
    temperature IS NOT NULL AND 
    humidity IS NOT NULL                       -- Filter out incomplete weather data
GROUP BY 
    b.product_name, 
    weather_description                        -- Analyze by weather description
ORDER BY 
    total_sales DESC;                          -- Highlight the most profitable weather types



-- ============================================================================
-- QUERY 16: Top Cities for Sales Under Favorable Weather Conditions
--
-- OBJECTIVE:
--   This query identifies the cities where the highest volume of sales occurred 
--   under what we define as "optimal" weather conditions:
--     - Temperature between 268K and 299K (~ -5°C to ~26°C)
--     - Humidity between 48% and 86%
--
--   The goal is to determine which cities and product categories perform best
--   in comfortable weather. These insights are valuable for marketing,
--   local promotions, and weather-aware demand forecasting.
-- ============================================================================

SELECT 
    city,                                 -- Name of the city where the sale happened
    category,                             -- Broad product category (e.g., Technology, Furniture)
    sub_category,                         -- More detailed product grouping
    SUM(sales) AS total_sales,            -- Total revenue generated under these conditions
    SUM(profit) AS total_profit,          -- Total profit generated
    COUNT(*) AS num_orders                -- Number of transactions made
FROM sales_data.sales_weather_clean
WHERE temperature BETWEEN 268 AND 299     -- Filter for the "optimal" temperature range
  AND humidity BETWEEN 48 AND 86          -- Filter for the "optimal" humidity range
GROUP BY city, category, sub_category     -- Group results by city and product type
ORDER BY total_sales DESC                 -- Rank by highest revenue
LIMIT 10;                                 -- Show only the top 10 best-performing results




-- ============================================================================
-- QUERY 17: Weather vs Sub-Category Performance
--
-- OBJECTIVE:
--   This query investigates the relationship between different weather 
--   conditions (e.g., clear sky, rain) and the performance of specific 
--   product sub-categories.
--
--   By analyzing which sub-categories perform best under certain weather 
--   descriptions, this insight can be used for:
--     - Weather-driven marketing campaigns
--     - Demand forecasting based on climate
--     - Strategic stocking of weather-sensitive products
-- ============================================================================

SELECT 
    weather_description,                     -- Type of weather (e.g., Rain, Clear Sky)
    sub_category,                            -- Specific product sub-category (e.g., Chairs, Phones)
    AVG(temperature) AS avg_temp,            -- Average temperature during sales of this sub-category
    AVG(humidity) AS avg_humidity,           -- Average humidity during those sales
    SUM(sales) AS total_sales,               -- Total revenue generated for this sub-category
    COUNT(*) AS num_orders                   -- Number of orders placed under this weather condition
FROM sales_data.sales_weather_clean
GROUP BY 
    weather_description,                     -- Group by weather type
    sub_category                             -- And by product sub-category
ORDER BY 
    total_sales DESC                         -- Focus on the highest-selling combinations
LIMIT 20;                                    -- Show top 20 most successful weather/sub-category pairs





-- ============================================================================
-- QUERY 18: Sales Analysis by Region and City in High Humidity Conditions
--
-- OBJECTIVE:
--   This query investigates how sales behave in locations where humidity 
--   exceeds 70%. By grouping data by region, city, category, and sub-category,
--   we can identify:
--     - Which cities and regions remain profitable under humid weather
--     - Which product types (at category and sub-category level) are in demand
--     - Potential regional trends for weather-adaptive sales strategy
--
-- USE CASES:
--   This is useful for:
--     - Adjusting inventory and logistics in tropical or coastal areas
--     - Targeting ads for weather-specific products (e.g., fans, moisture-proof goods)
--     - Understanding how humidity affects customer behavior
-- ============================================================================

SELECT 
    region,                                  -- geographical region (e.g., West, South)
    city,                                    -- Specific city name
    category,                                -- Product category (e.g., Furniture, Technology)
    sub_category,                            -- More specific product classification
    COUNT(*) AS num_orders,                  -- return thr total number of orders in these conditions
    SUM(quantity) AS total_quantity,         -- // total quantity of items sold
    SUM(sales) AS total_sales                -- // total sales value for each city/category combo
FROM sales_data.sales_weather_clean
WHERE humidity > 70                          -- Only include records with high humidity
GROUP BY 
    region, city, category, sub_category     -- Grouping by location and product type
ORDER BY 
    region, city, total_sales DESC;          -- Sort results by region, city, and descending sales
    


-- ============================================================================
-- QUERY 19: Sales Performance Under Ideal Weather Conditions
--
-- OBJECTIVE:
--   This query identifies the best-selling product categories and sub-categories 
--   in regions and cities that experience what are considered "ideal" weather conditions:
--     - Temperature between 226K and 299K (~ -47°C to 25.8°C) 
--     - Humidity between 50% and 60%
--
--   These ranges are used as proxies for temperate weather—neither too hot 
--   nor too humid—ideal for encouraging shopping or logistics.
--
-- USE CASES:
--   - Determine how mild weather conditions affect consumer behavior
--   - Understand if certain regions perform better due to climate
--   - Guide seasonal marketing campaigns or promotions
-- ============================================================================

SELECT 
    region,                                   
    category,                                 --  ( Office Supplies)
    sub_category,                             -- ( Binders, Chairs)
    COUNT(*) AS num_orders,                   -- return the number of orders in "ideal" weather
    SUM(sales) AS total_sales,                -- // total sales in monetary value
    ROUND(AVG(temperature), 1) AS avg_temp,   -- // average temperature rounded to 1 decimal
    ROUND(AVG(humidity), 1) AS avg_humidity   -- // average humidity rounded to 1 decimal
FROM sales_data.sales_weather_clean
WHERE 
    temperature BETWEEN 226 AND 299           -- Ideal temperature range in Kelvin
  AND humidity BETWEEN 50 AND 60              -- Ideal humidity range
GROUP BY 
    region, city, category, sub_category      -- Group by location and product details
ORDER BY 
    total_sales DESC;                         -- Focus on the most profitable combinations first
    
    
    

