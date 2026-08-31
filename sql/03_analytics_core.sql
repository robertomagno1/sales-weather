-- Sales & Weather | MySQL 8 | see README.md for the full pipeline order.
-- 03 - Analytics Q1-Q10: distributions, regional aggregates, window-function rankings.

-- =======================================================================
-- QUERY 1: Temperature and Humidity Distribution per City
-- Purpose: Understand average climate conditions in each city.
-- =======================================================================
SELECT 
    City,                               
    AVG(temperature) AS avg_temp,       -- return the average temperature in that city
    AVG(humidity) AS avg_humidity       -- // average humidity in that city
FROM 
    sales_weather                       -- from the source table (combining sales and weather data)
GROUP BY 
    City;                               -- Grouping results per city

-- =======================================================================
-- QUERY 2: Average Sales by Region and City
-- Purpose: Identify cities and regions with the highest average sales.
-- =======================================================================
SELECT 
    Region,                             
    City,                               
    AVG(Sales) AS avg_sales             --  average sales amount for each city
FROM 
    sales_weather
GROUP BY 
    Region, City;                       -- Grouping by both region and city

-- =======================================================================
-- QUERY 3: Total Sales and Profit by Region and State
-- Purpose: Rank regions/states by overall sales and profit.
-- =======================================================================
SELECT 
    Region,                             
    State,                             
    SUM(Sales) AS Total_Sales,          -- total sales value in the state
    SUM(Profit) AS Total_Profit         -- total profit generated in the state
FROM 
    sales_weather
GROUP BY 
    Region, State                       -- aggregating by region and state
ORDER BY 
    Total_Sales DESC;                   -- sorted to show highest sales first
    
    
-- =======================================================================
-- QUERY 4: Most Profitable Customers
-- Purpose: Identify which customers generated the highest total profit.
-- =======================================================================
SELECT 
    Customer_ID,                        
    Customer_Name,                      
    SUM(Profit) AS Total_Profit         -- total profit generated from all "customer" purchases
FROM 
    sales_weather
GROUP BY 
    Customer_ID, Customer_Name          -- grouping to aggregate profit by customer
ORDER BY 
    Total_Profit DESC;                  -- sorting to get the most profitable customers at the top


-- =======================================================================
-- QUERY 5: Most Profitable Customers (with Sales Insight)
-- Purpose: Extended version of Query 4, including total sales alongside profit.
-- =======================================================================
SELECT 
    Customer_ID,                        
    Customer_Name,                     
    SUM(Sales) AS Total_Sales,          -- return the total value of purchases made by the customer
    SUM(Profit) AS Total_Profit         -- return the corresponding profit generated
FROM 
    sales_weather
GROUP BY 
    Customer_ID, Customer_Name          -- aggregated by customer
ORDER BY 
    Total_Profit DESC;                  -- customers ranked by profit


-- =======================================================================
-- QUERY 6: Product Performance by Segment, Category, and Sub-Category
-- Purpose: Analyze how different product types perform within each market segment.
-- =======================================================================
SELECT 
    Segment,                            
    Category,                           
    Sub_Category,                       
    COUNT(Order_ID) AS Number_of_Orders, -- number of orders placed for this sub-category
    SUM(Sales) AS Total_Sales,          -- return the total sales revenue
    SUM(Profit) AS Total_Profit         -- // total profit from these products
FROM 
    sales_weather
GROUP BY 
    Segment, Category, Sub_Category     -- aggregating at 3 levels: segment > category > sub-category
ORDER BY 
    Segment, Total_Sales DESC;          -- sorting results by segment and top-selling items
    
    

-- =======================================================================
-- QUERY 7: Weather Conditions on High-Sales Days
-- Purpose: Identify what kind of weather was present in cities on days
--          when total sales exceeded $1000.
--          this helps explore potential correlations between good weather
--          and increased purchasing activity.
-- =======================================================================


SELECT DISTINCT 
    o.city,                            -- name of the city where the sales occurred
    o.order_date,                      -- original order date (still in string format here)
    d.description                      -- weather description on that day (Clear, Rainy)
FROM 
    sales_data.orders_raw o            -- sales data (raw, unoptimized)
JOIN 
    sales_data.description d           -- weather descriptions table
    ON o.city = d.city                 -- match data by city
    AND STR_TO_DATE(o.order_date, '%m/%d/%Y') = d.date  
                                       -- convert order_date string to DATE and match with weather date
GROUP BY 
    o.city, o.order_date, d.description  
                                       -- grouping now  to allow aggregation for HAVING clause
HAVING 
    SUM(o.sales) > 1000;               -- filtered to only include days with total sales > $1000



-- =======================================================================
-- QUERY 8: Top-Selling Products on Sunny Days per Region
-- Purpose:
--   This query identifies the single best-selling product (by total sales)
--   for each region, but only considering days where the weather was sunny 
--   (specifically: "sky is clear").
--
--   It uses Common Table Expressions (CTEs) and a window function to rank 
--   products within each region.
-- =======================================================================

-- 1: Define CTE 'sunny_orders' to filter sales only on sunny days
WITH sunny_orders AS (
    SELECT 
        o.region,                          -- geographic region of the order
        o.product_name,                    
        SUM(o.sales) AS total_sales        -- return the aggregate sales per product and region
    FROM 
        sales_data.orders_raw o
    JOIN 
        sales_data.description d           -- join with weather description
        ON o.city = d.city                 -- match them ON: city
        AND STR_TO_DATE(o.order_date, '%m/%d/%Y') = d.date
                                           -- convert string date and match with weather date
    WHERE 
        d.description LIKE '%sky is clear%'  -- here we only consider "sunny" days
    GROUP BY 
        o.region, o.product_name           -- finally group by region and product for aggregation
),

-- 2: here we rank products within each region based on total_sales
ranked_products AS (
    SELECT 
        *,  -- All fields from sunny_orders
        RANK() OVER (
            PARTITION BY region 
            ORDER BY total_sales DESC
        ) AS rnk                          -- ranking products within each region (1 = top seller)
    FROM 
        sunny_orders
)

-- 3: now selecting only the top product per region (rank 1)
SELECT 
    region, 
    product_name, 
    total_sales
FROM 
    ranked_products
WHERE 
    rnk = 1;                              -- keeping only the top-selling product per region
    
    


-- =======================================================================
-- QUERY 9: Customers whose average profit is below the regional average
-- Purpose:
--   This query identifies customers whose average order profit is 
--   lower than the average profit for their region.
--
--   It uses two Common Table Expressions (CTEs):
--   1. To compute the average profit per region.
--   2. To compute the average profit per customer.
--   Then it compares them to find underperforming customers.
-- =======================================================================

-- 1: CTE to calculate the average profit per region
WITH regional_avg_profit AS (
    SELECT 
        region,                               -- Geographic region
        AVG(profit) AS avg_profit_region      -- Average profit in that region
    FROM 
        sales_data.orders_raw
    GROUP BY 
        region                                -- One row per region
),

-- 2: CTE to calculate the average profit per customer (within their region)
customer_avg_profit AS (
    SELECT 
        customer_id,                          -- Unique identifier for the customer
        customer_name,                        -- Full name of the customer
        region,                               -- Region the customer belongs to
        AVG(profit) AS avg_profit_customer    -- Customer's average profit per order
    FROM 
        sales_data.orders_raw
    GROUP BY 
        customer_id, customer_name, region    -- Grouping to avoid duplicates
)

-- 3: Final selection of underperforming customers
SELECT 
    c.customer_id,                           
    c.customer_name,                          
    c.region,                                 
    c.avg_profit_customer                     
FROM 
    customer_avg_profit c                     
JOIN 
    regional_avg_profit r 
    ON c.region = r.region                    -- joining with regional averages
WHERE 
    c.avg_profit_customer < r.avg_profit_region
											
											  -- filter: customers earning below the regional average
ORDER BY 
    avg_profit_region DESC;                   -- soredt by region's profit (most profitable at top)


-- =======================================================================
-- QUERY 10: Monthly Sales and Average Temperature per City (Year: 2014)
-- Purpose:
--   This query analyzes how sales and temperatures fluctuate monthly
--   in different cities during the year 2014. 
--   It combines sales and weather data using a common date and location,
--   and computes total monthly sales and average temperature per city.
--
--   It is useful for identifying seasonal trends and weather-related 
--   influences on sales.
-- =======================================================================

-- 1: Create a CTE to extract monthly metrics
WITH monthly_data AS (
    SELECT 
        o.city,                                             
        MONTH(STR_TO_DATE(o.order_date, '%m/%d/%Y')) AS month,  
                                                             -- Extract numeric month from string-formatted date
        SUM(o.sales) AS total_sales,                         -- Total sales in that month
        AVG(t.temperature) AS avg_temp                       -- Average temperature in that month
    FROM 
        sales_data.orders_raw o
    JOIN 
        sales_data.temperature t                             -- join with temperature data
        ON o.city = t.city                                   -- match by city
        AND STR_TO_DATE(o.order_date, '%m/%d/%Y') = t.date   -- now convert and match order date with temperature date
    WHERE 
        YEAR(STR_TO_DATE(o.order_date, '%m/%d/%Y')) = 2014    -- filter only for the year 2014
    GROUP BY 
        o.city, MONTH(STR_TO_DATE(o.order_date, '%m/%d/%Y'))  -- group by city and month
)

-- 2: Select from the CTE and order the result
SELECT 
    *                                                       -- showing all columns: city, month, total_sales, avg_temp
FROM 
    monthly_data
ORDER BY 
    city, month;                                            -- sorted alphabetically by city and chronologically by month
    
    
 
 
 
 
 
