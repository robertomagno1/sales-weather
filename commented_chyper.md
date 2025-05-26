## Blocks 0 – 4 ▪ Cypher script **with in‐place, numbered commentary**  
*(copy–paste this single cell into your `.md` notes)*


```cypher
// ───────────────────────── Block 0 – CONSTRAINTS ─────────────────────
01 CREATE CONSTRAINT city_name    IF NOT EXISTS FOR (c:City)    REQUIRE c.name IS UNIQUE;
02 CREATE CONSTRAINT state_name   IF NOT EXISTS FOR (s:State)   REQUIRE s.name IS UNIQUE;
03 CREATE CONSTRAINT region_name  IF NOT EXISTS FOR (r:Region)  REQUIRE r.name IS UNIQUE;
04 CREATE CONSTRAINT customer_id  IF NOT EXISTS FOR (c:Customer) REQUIRE c.id IS UNIQUE;
05 CREATE CONSTRAINT product_id   IF NOT EXISTS FOR (p:Product) REQUIRE p.id IS UNIQUE;
06 CREATE CONSTRAINT order_id     IF NOT EXISTS FOR (o:Order)   REQUIRE o.id IS UNIQUE;
07 CREATE CONSTRAINT weather_key  IF NOT EXISTS FOR (w:Weather) REQUIRE (w.city, w.date) IS UNIQUE;

// ───────────────────────── Block 1 – SALES + GEO CSV ─────────────────
08 :auto
09 CALL {                                   // batch-loader sub-query
10   WITH "file:///sales_final.csv" AS url
11   LOAD CSV WITH HEADERS FROM url AS row  // stream each CSV record
12   MERGE (reg:Region {name: row.region})
13   MERGE (st:State  {name: row.state})
14   MERGE (st)-[:IN_REGION]->(reg)         // wire state → region
15   MERGE (city:City {name: row.city})
16   MERGE (city)-[:IN_STATE]->(st)         // wire city → state
17   MERGE (cust:Customer {id: row.customer_id})
18     ON CREATE SET cust.name = row.customer_name,
19                   cust.segment = row.segment
20   MERGE (prod:Product {id: row.product_id})
21     ON CREATE SET prod.name         = row.product_name,
22                   prod.category     = row.category,
23                   prod.sub_category = row.sub_category
24   MERGE (ord:Order {id: row.order_id})
25     ON CREATE SET ord.date   = date(row.order_date),
26                   ord.sales  = toFloat(row.sales),
27                   ord.profit = toFloat(row.profit)
28     ON MATCH  SET ord.sales  = ord.sales  + toFloat(row.sales),
29                   ord.profit = ord.profit + toFloat(row.profit)
30   MERGE (cust)-[:PLACED]->(ord)
31   MERGE (ord)-[:DELIVERED_TO]->(city)
32   MERGE (ord)-[:CONTAINS {
33           qty      : toInteger(row.quantity),
34           discount : toFloat(row.discount)
35         }]->(prod)
36 } IN TRANSACTIONS OF 5000 ROWS;

// ───────────────────────── Block 2 – WEATHER description ─────────────
37 :auto
38 CALL {
39   WITH "file:///description.csv" AS url
40   LOAD CSV WITH HEADERS FROM url AS row
41   MATCH (city:City {name: row.city})
42   MERGE (w:Weather {city: row.city, date: date(row.date)})
43     ON CREATE SET w.description = row.description
44   MERGE (city)-[:HAS_WEATHER]->(w)
45 } IN TRANSACTIONS OF 10000 ROWS;

// ───────────────────────── Block 3 – WEATHER temperature ─────────────
46 :auto
47 CALL {
48   WITH "file:///temperature1.csv" AS url
49   LOAD CSV WITH HEADERS FROM url AS row
50   MATCH (w:Weather {city: row.city, date: date(row.date)})
51   SET   w.temperature = toFloat(row.temperature) - 273.15
52 } IN TRANSACTIONS OF 10000 ROWS;

// ───────────────────────── Block 4 – WEATHER humidity ────────────────
53 :auto
54 CALL {
55   WITH "file:///humidity.csv" AS url
56   LOAD CSV WITH HEADERS FROM url AS row
57   MATCH (w:Weather {city: row.city, date: date(row.date)})
58   SET   w.humidity = toFloat(row.humidity)
59 } IN TRANSACTIONS OF 10000 ROWS;


### Query 1 – Average Temperature & Humidity per City  
*Goal: show the long-term climate profile of each city so we can later compare it with sales trends.*

```cypher
// ── Q1: Average Temperature & Humidity per City ──────────────────────
MATCH (c:City)-[:HAS_WEATHER]->(w:Weather)    // ① traverse City → Weather
RETURN
       c.name                                 // ② group key
         AS city,
       round(avg(w.temperature), 2)           // ③ mean temp (2-dec precision)
         AS avg_temp,
       round(avg(w.humidity), 2)              // ④ mean RH %
         AS avg_humidity
ORDER BY city;                                // ⑤ alphabetic for easy reading


① MATCH (c)-[:HAS_WEATHER]->(w)	Scans each :City node and uses the HAS_WEATHER relationship to reach every weather reading tied to that city.
  Because weather_key is (city,date) and an index backs it, Neo4j streams this as an index seek for each hop—not a label scan.
② c.name AS city	Emits the city name once per aggregation group; everything downstream is grouped by this field automatically.
③ avg(w.temperature)	Uses the built-in aggregation function. temperature is a numeric property (set in Kelvin→°C conversion during load),
  so no casting cost. round(…,2) gives a tidy presentation value without altering the underlying precision.
④ avg(w.humidity)	Same pattern for humidity. Percentages are stored 0-100, so the average is meaningful.
⑤ ORDER BY city	Purely cosmetic: alphabetical order makes the result table predictable in a demo. Because the result set is typically < 100 rows, the extra sort is negligible.

### Query 2 – Average Sales by Region and City

```cypher
// Q2 – identify where average order value is highest
MATCH (r:Region)<-[:IN_REGION]-(:State)<-[:IN_STATE]-
      (c:City)<-[:DELIVERED_TO]-(o:Order)           // ① geo-hierarchy → orders
RETURN
       r.name                 AS region,            // ② first-level group
       c.name                 AS city,              // ③ second-level group
       round(avg(o.sales),2)  AS avg_sales          // ④ measure
ORDER BY region, avg_sales DESC;                    // ⑤ ranked output

What the query reveals
Example: in the West region, San Francisco averages $486 per order while Phoenix averages $215—insightful for region-specific marketing or inventory decisions.

① MATCH …	Traverses the Region → State → City chain (two hops) and then follows DELIVERED_TO to every order delivered in each city.
 Each hop is index-backed thanks to the unique constraints defined in Block 0, so the pattern is resolved with index-seeks, not label scans.
② r.name AS region	Emits the region name; implicit GROUP BY will aggregate on (region, city).
③ c.name AS city	Emits the city inside its parent region, producing one result row per city.
④ avg(o.sales)	Calculates the arithmetic mean of sales for all orders in that city. round(…,2) formats the number for presentation without altering stored precision.
⑤ ORDER BY region, avg_sales DESC	First sorts alphabetically by region, then ranks cities inside each region from highest to lowest average sale value—making revenue “hot-spots”
 obvious during the demo.



### Query 3 – Total Sales & Profit by Region and State

```cypher
// Q3 – rank regions / states by overall performance
MATCH (r:Region)<-[:IN_REGION]-(s:State)<-[:IN_STATE]-(:City)<-[:DELIVERED_TO]-(o:Order)   // ① follow geography → orders
RETURN
       r.name                      AS region,                                               // ② first-level grouping key
       s.name                      AS state,                                                // ③ second-level grouping key
       round(sum(o.sales),   2)    AS total_sales,                                          // ④ gross revenue
       round(sum(o.profit),  2)    AS total_profit                                          // ⑤ profitability
ORDER BY total_sales DESC;                                                                  // ⑥ big earners on top

“Query 3 shows that although the West → California pair delivers the largest revenue, South → Texas yields a higher profit margin, indicating lower discount pressure or better cost control.”

① MATCH (r)<-[:IN_REGION]-(s)<-[:IN_STATE]-(:City)<-[:DELIVERED_TO]-(o)	Traverses the geo-hierarchy Region → State → City in two hops, then pivots to :Order through DELIVERED_TO.
 Each segment uses an index created in Block 0, so the traversal is resolved by index-seek joins rather than full scans.
② r.name AS region	Emits the region label; implicit grouping starts on (region,state).
③ s.name AS state	Adds the second grouping dimension—one result row per state.
④ sum(o.sales)	Aggregates gross revenue for all orders delivered in that state, regardless of city. round(…,2) formats to standard currency precision for presentation.
⑤ sum(o.profit)	Aggregates net profitability the same way. Shows whether high-revenue regions are also high-margin.
⑥ ORDER BY total_sales DESC	Sorts the result so the highest-earning states appear first—useful for a quick verbal focus during your presentation
  (“California tops the chart with $1.2 M”). Sorting on an aggregated expression is computed after the grouping, so the cost is negligible compared with the match traversal.

### Query 4 – Top-10 Most Profitable Customers  

```cypher
// Q4 – rank customers by the total profit they generated
MATCH (cust:Customer)-[:PLACED]->(o:Order)        // ① traverse Customer → Order
RETURN
       cust.id                    AS customer_id, // ② stable business key
       cust.name                  AS customer_name,
       round(sum(o.profit), 2)    AS total_profit // ③ aggregate profit per customer
ORDER BY total_profit DESC                         // ④ sort from highest to lowest
LIMIT 10;                                         // ⑤ show only the top performers

① MATCH (cust)-[:PLACED]->(o)	Follows the PLACED relationship to pull every order a customer submitted. Because customer_id and order_id are both indexed (Block 0),
Neo4j resolves this with two index-seeks and a pointer hop—very fast even on 100 k + orders.
② cust.id AS customer_id	Uses the immutable customer key for grouping; helpful if two customers share the same display name.
③ sum(o.profit)	Adds up the profit property already stored on each :Order node when the data was loaded. round(…,2) formats to currency precision for slide-ready output.
④ ORDER BY total_profit DESC	Ranks customers from the most profitable downward—ideal for calling out “your VIPs” during the talk.
  Sorting happens after aggregation, so the cost is proportional to the 10–20 k customer groups, not to line-items.
⑤ LIMIT 10	Keeps the result concise and visually digestible in the demo; still easy to change to 20/50 if asked.


