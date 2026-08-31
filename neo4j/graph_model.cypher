CREATE CONSTRAINT city_name IF NOT EXISTS FOR (c:City) REQUIRE c.name IS UNIQUE;
CREATE CONSTRAINT state_name IF NOT EXISTS FOR (s:State) REQUIRE s.name IS UNIQUE;
CREATE CONSTRAINT region_name IF NOT EXISTS FOR (r:Region) REQUIRE r.name IS UNIQUE;
CREATE CONSTRAINT customer_id IF NOT EXISTS FOR (c:Customer) REQUIRE c.id IS UNIQUE;
CREATE CONSTRAINT product_id IF NOT EXISTS FOR (p:Product) REQUIRE p.id IS UNIQUE;
CREATE CONSTRAINT order_id IF NOT EXISTS FOR (o:Order) REQUIRE o.id IS UNIQUE;
CREATE CONSTRAINT weather_key IF NOT EXISTS FOR (w:Weather) REQUIRE (w.city, w.date) IS UNIQUE;





####1


:auto
CALL {
  WITH "file:///sales_final.csv" AS url
  LOAD CSV WITH HEADERS FROM url AS row

  MERGE (reg:Region {name: row.region})
  MERGE (st:State {name: row.state})
  MERGE (st)-[:IN_REGION]->(reg)

  MERGE (city:City {name: row.city})
  MERGE (city)-[:IN_STATE]->(st)

  MERGE (cust:Customer {id: row.customer_id})
    ON CREATE SET cust.name = row.customer_name, cust.segment = row.segment

  MERGE (prod:Product {id: row.product_id})
    ON CREATE SET prod.name = row.product_name,
                  prod.category = row.category,
                  prod.sub_category = row.sub_category

  MERGE (ord:Order {id: row.order_id})
    ON CREATE SET ord.date = date(row.order_date),
                  ord.sales = toFloat(row.sales),
                  ord.profit = toFloat(row.profit)
    ON MATCH SET  ord.sales = ord.sales + toFloat(row.sales),
                  ord.profit = ord.profit + toFloat(row.profit)

  MERGE (cust)-[:PLACED]->(ord)
  MERGE (ord)-[:DELIVERED_TO]->(city)
  MERGE (ord)-[:CONTAINS {qty: toInteger(row.quantity), discount: toFloat(row.discount)}]->(prod)
}
IN TRANSACTIONS OF 5000 ROWS;





####2



:auto
CALL {
  WITH "file:///description.csv" AS url
  LOAD CSV WITH HEADERS FROM url AS row
  MATCH (city:City {name: row.city})
  MERGE (w:Weather {city: row.city, date: date(row.date)})
    ON CREATE SET w.description = row.description
  MERGE (city)-[:HAS_WEATHER]->(w)
}
IN TRANSACTIONS OF 10000 ROWS;



####3 

:auto
CALL {
  WITH "file:///temperature1.csv" AS url
  LOAD CSV WITH HEADERS FROM url AS row
  MATCH (w:Weather {city: row.city, date: date(row.date)})
  SET w.temperature = toFloat(row.temperature) - 273.15
}
IN TRANSACTIONS OF 10000 ROWS;





######5 


:auto
CALL {
  WITH "file:///humidity.csv" AS url
  LOAD CSV WITH HEADERS FROM url AS row
  MATCH (w:Weather {city: row.city, date: date(row.date)})
  SET w.humidity = toFloat(row.humidity)
}
IN TRANSACTIONS OF 10000 ROWS;



🔍 Q1: Average Temperature & Humidity per City


MATCH (c:City)-[:HAS_WEATHER]->(w:Weather)
RETURN c.name AS city,
       round(avg(w.temperature), 2) AS avg_temp,
       round(avg(w.humidity), 2) AS avg_humidity
ORDER BY city;



🔍 Q2: Average Sales by Region and City

MATCH (r:Region)<-[:IN_REGION]-(:State)<-[:IN_STATE]-(c:City)<-[:DELIVERED_TO]-(o:Order)
RETURN r.name AS region,
       c.name AS city,
       round(avg(o.sales), 2) AS avg_sales
ORDER BY region, avg_sales DESC;



🔍 Q3: Total Sales and Profit by Region and State

Modifica
MATCH (r:Region)<-[:IN_REGION]-(s:State)<-[:IN_STATE]-(:City)<-[:DELIVERED_TO]-(o:Order)
RETURN r.name AS region,
       s.name AS state,
       round(sum(o.sales), 2) AS total_sales,
       round(sum(o.profit), 2) AS total_profit
ORDER BY total_sales DESC;



🔍 Q4: Most Profitable Customers

MATCH (cust:Customer)-[:PLACED]->(o:Order)
RETURN cust.id AS customer_id,
       cust.name AS customer_name,
       round(sum(o.profit), 2) AS total_profit
ORDER BY total_profit DESC
LIMIT 10;



🔍 Q5: Product Performance by Segment, Category, Subcategory
(assumes your product categories are modeled via properties – not separate nodes)


MATCH (cust:Customer)-[:PLACED]->(o:Order)-[r:CONTAINS]->(p:Product)
RETURN cust.segment AS segment,
       p.category AS category,
       p.sub_category AS sub_category,
       count(o) AS number_of_orders,
       round(sum(o.sales), 2) AS total_sales,
       round(sum(o.profit), 2) AS total_profit
ORDER BY segment, total_sales DESC;




🔍 Q6: Weather on High-Sales Days

MATCH (c:City)<-[:DELIVERED_TO]-(o:Order),
      (c)-[:HAS_WEATHER]->(w:Weather)
WITH c, date(o.date) AS d, sum(o.sales) AS total_sales, w
WHERE total_sales > 1000 AND w.date = d
RETURN c.name AS city,
       d AS order_date,
       w.description AS weather_description
ORDER BY total_sales DESC;




🔍 Q7: Top-Selling Products on Sunny Days per Region

MATCH (r:Region)<-[:IN_REGION]-(:State)<-[:IN_STATE]-(c:City),
      (c)<-[:DELIVERED_TO]-(o:Order)-[:CONTAINS]->(p:Product),
      (c)-[:HAS_WEATHER]->(w:Weather)
WHERE w.description CONTAINS "sky is clear" AND w.date = o.date
WITH r, p.name AS product, sum(o.sales) AS total_sales
ORDER BY r.name, total_sales DESC
WITH r.name AS region, collect({product: product, sales: total_sales})[0] AS top_product
RETURN region, top_product.product AS product_name, top_product.sales AS sales_value;




🔍 Q8: Underperforming Customers vs Regional Profit

MATCH (cust:Customer)-[:PLACED]->(o:Order)
      -[:DELIVERED_TO]->(:City)-[:IN_STATE]->(:State)-[:IN_REGION]->(r:Region)
WITH r, cust, avg(o.profit) AS cust_avg
MATCH (:Customer)-[:PLACED]->(ord:Order)
      -[:DELIVERED_TO]->(:City)-[:IN_STATE]->(:State)-[:IN_REGION]->(r)
WITH r, cust, cust_avg, avg(ord.profit) AS region_avg
WHERE cust_avg < region_avg
RETURN cust.id AS customer_id,
       cust.name AS customer_name,
       r.name AS region,
       round(cust_avg, 2) AS customer_avg_profit,
       round(region_avg, 2) AS region_avg_profit
ORDER BY region_avg DESC;




🔍 Q9: Monthly Sales & Avg Temperature per City (Year: 2014)

MATCH (c:City)<-[:DELIVERED_TO]-(o:Order),
      (c)-[:HAS_WEATHER]->(w:Weather)
WHERE o.date.year = 2014 AND w.date = o.date
WITH c.name AS city, o.date.month AS month,
     sum(o.sales) AS total_sales, avg(w.temperature) AS avg_temp
RETURN city, month,
       round(total_sales, 2) AS total_sales,
       round(avg_temp, 1) AS avg_temp
ORDER BY city, month;




🔍 Q10: Top 5 Products per Weather Condition

MATCH (o:Order)-[:CONTAINS]->(p:Product),
      (o)-[:DELIVERED_TO]->(c:City)-[:HAS_WEATHER]->(w:Weather)
WHERE o.date = w.date
WITH w.description AS weather,
     p.name AS product,
     sum(o.sales) AS total_sales
ORDER BY weather, total_sales DESC
WITH weather, collect({product: product, sales: total_sales})[0..5] AS top5
UNWIND top5 AS row
RETURN weather,
       row.product AS product_name,
       round(row.sales, 2) AS total_sales
ORDER BY weather, total_sales DESC;
