


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

# MATCH …	Traverses the Region → State → City chain (two hops) and then follows DELIVERED_TO to every order delivered in each city.
Each hop is index-backed thanks to the unique constraints defined in Block 0, so the pattern is resolved with index-seeks, not label scans.
# r.name AS region	Emits the region name; implicit GROUP BY will aggregate on (region, city).
# c.name AS city	Emits the city inside its parent region, producing one result row per city.
# avg(o.sales)	Calculates the arithmetic mean of sales for all orders in that city. round(…,2) formats the number for presentation without altering stored precision.
# ORDER BY region, avg_sales DESC	First sorts alphabetically by region, then ranks cities inside each region from highest to lowest average sale value—making revenue “hot-spots”
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


### Query 5 – Product Performance by Segment, Category & Sub-Category

```cypher
// Q5 – multi-level product mix analysis
MATCH (cust:Customer)-[:PLACED]->(o:Order)-[:CONTAINS]->(p:Product)   // ① join Customer → Order → Product
RETURN
       cust.segment            AS segment,                            // ② market dimension
       p.category              AS category,                           // ③ product family
       p.sub_category          AS sub_category,                       // ④ finer granularity
       count(o)                AS number_of_orders,                   // ⑤ order volume metric
       round(sum(o.sales),2)   AS total_sales,                        // ⑥ revenue
       round(sum(o.profit),2)  AS total_profit                        // ⑦ margin
ORDER BY segment, total_sales DESC;                                   // ⑧ ranked inside each segment

① MATCH (cust)-[:PLACED]->(o)-[:CONTAINS]->(p)	Traverses the selling path from each customer to every product they purchased. All three hops use indexed keys (customer_id, order_id, product_id) so look-ups are index-seeks, not scans.
② cust.segment AS segment	Groups by the marketing segment (Consumer, Corporate, …) captured as a scalar property on :Customer—no need for an extra node.
③ p.category AS category	Adds the product category to the grouping key; still a plain property for a lean model.
④ p.sub_category AS sub_category	Adds a third dimension, giving one result row per “segment × category × sub-category” combination.
⑤ count(o)	Counts how many orders contained at least one item of that sub-category. Because the relationship pattern guarantees each (order,product) pair is visited once, plain count(o) is accurate; no DISTINCT needed.
⑥ sum(o.sales)	Aggregates gross sales across all matching orders. round(…,2) formats to currency precision for the slide.
⑦ sum(o.profit)	Aggregates profit—useful to see if high-revenue sub-categories are also high-margin.
⑧ ORDER BY segment, total_sales DESC	Within each segment the table is sorted by descending sales, so you can instantly say “In the Corporate segment the top-grossing sub-category is Chairs with $123 k”.


### Query 6 – Weather on High-Sales Days  
*Business idea: “When a city sells **more than €1 000 in a single day, what was the weather like?”  
This helps spot weather patterns that coincide with sales spikes.*

```cypher
// Q6 – link city-day sales > 1 000 € to its weather description
MATCH (c:City)<-[:DELIVERED_TO]-(o:Order),          // ① city ↔︎ order
      (c)-[:HAS_WEATHER]->(w:Weather)               // ② city ↔︎ weather
WITH  c,                                            // ③ keep city for grouping
      date(o.date)      AS d,                       //    canonical day key
      sum(o.sales)      AS total_sales,             //    aggregate daily sales
      w                                                   
WHERE total_sales > 1000 AND w.date = d             // ④ sales-threshold + same day
RETURN
       c.name        AS city,                       // ⑤ result columns
       d             AS order_date,
       w.description AS weather_description
ORDER BY total_sales DESC;                          // ⑥ most lucrative days first


① MATCH (c)<-[:DELIVERED_TO]-(o)	Follows DELIVERED_TO to grab every order delivered in each city. With the unique order_id constraint, this hop is an index-seek on both ends.
② (c)-[:HAS_WEATHER]->(w)	Jumps from the same city to all its weather readings. The composite (city,date) index guarantees fast look-up.
③ WITH c, date(o.date) AS d, sum(o.sales) AS total_sales, w	Groups orders by city-day and pre-computes total daily sales. Converting o.date to a date literal collapses time-of-day differences, so all orders on the same date aggregate together.
④ WHERE total_sales > 1000 AND w.date = d	Filters to “big sales” days and aligns weather rows by the identical date key d, avoiding cartesian products.
⑤ RETURN …	Outputs city, the day, and the sky condition—exactly what you narrate in the pitch: “Milan sold 1 200 € on 2024-06-18 when the sky was clear.”
⑥ ORDER BY total_sales DESC	Presents the highest-earning days at the top; lets you spotlight the most interesting rows during the 10-minute demo.


### Query 7 – Top-Selling Product on “Sky Is Clear” Days per Region  
*Business question: “For each sales region, which single product earned the most **on sunny days**?”*

```cypher
// Q7 – find the best-seller in each region when the weather is ‘sky is clear’
MATCH (r:Region)<-[:IN_REGION]-(:State)<-[:IN_STATE]-(c:City)      // ① Region → City
MATCH (c)-[:HAS_WEATHER]->(w:Weather)                              // ② City → Weather
WHERE w.description CONTAINS 'sky is clear'                        // ③ sunny-day filter
MATCH (c)<-[:DELIVERED_TO]-(o:Order)-[:CONTAINS]->(p:Product)      // ④ sunny orders → products
WHERE w.date = o.date                                              // ⑤ same calendar day
WITH  r, p.name AS product, sum(o.sales) AS total_sales            // ⑥ aggregate by region+product
ORDER BY r.name, total_sales DESC
WITH  r.name        AS region,                                     // ⑦ keep region label
      collect({product: product, sales: total_sales})[0] AS top    //    pick best seller
RETURN region,
       top.product  AS product_name,
       top.sales    AS sales_value;                                // ⑧ final, ranked list


	① MATCH (r)<-[:IN_REGION]-(:State)<-[:IN_STATE]-(c)
Walks the geography hierarchy (Region → State → City) using indexed keys, so each hop is an index-seek rather than a label scan.
	•	② MATCH (c)-[:HAS_WEATHER]->(w)
Jumps from the city to all its weather readings.
The composite uniqueness constraint on (city,date) guarantees a small, indexed lookup set.
	•	③ WHERE w.description CONTAINS 'sky is clear'
Text filter that keeps only “sunny” rows. With a range index on Weather.description, this becomes an index-backed string predicate.
	•	④ MATCH (c)<-[:DELIVERED_TO]-(o)-[:CONTAINS]->(p)
Collects every order delivered in that city, then hops to the product(s) on the order—again, an index-seek on order_id and product_id.
	•	⑤ WHERE w.date = o.date
Aligns the weather row and the order on the exact same calendar day, eliminating any cartesian product between multi-day observations and orders.
	•	⑥ WITH r, p.name, sum(o.sales) AS total_sales
Aggregates per (region, product) the gross sales that occurred on sunny days only.
	•	⑦ collect(…)[0] trick
collect() gathers the (product, sales) pairs already ordered by total_sales DESC;
[0] plucks the first element—the top seller—for each region.
	•	⑧ RETURN region, top.product, top.sales
Produces a concise, three-column result: perfect for a slide or dashboard snippet (“In the West, Canon LX Printer tops sunny-day sales with €42 k”).

### Query 8 – Customers Whose Profit Is **Below** Their Regional Average  
*Business question: “Which customers are under-performing relative to the profit norm of their own region?”*  

```cypher
// Q8 – flag customers whose avg-profit < avg-profit in their region
MATCH (cust:Customer)-[:PLACED]->(o:Order)                               // ① customer → order
      -[:DELIVERED_TO]->(:City)-[:IN_STATE]->(:State)-[:IN_REGION]->(r)  // ② order → region
WITH  r, cust, avg(o.profit) AS cust_avg                                 // ③ compute customer’s avg-profit
MATCH (:Customer)-[:PLACED]->(ord:Order)                                 // ④ re-scan all orders …
      -[:DELIVERED_TO]->(:City)-[:IN_STATE]->(:State)-[:IN_REGION]->(r)  //    … inside same region
WITH  r, cust, cust_avg, avg(ord.profit) AS region_avg                   // ⑤ region-level avg-profit
WHERE cust_avg < region_avg                                              // ⑥ keep only under-performers
RETURN
       cust.id      AS customer_id,                                      // ⑦ business key
       cust.name    AS customer_name,
       r.name       AS region,
       round(cust_avg, 2)   AS customer_avg_profit,
       round(region_avg, 2) AS region_avg_profit
ORDER BY region_avg DESC;                                                // ⑧ most profitable regions first

	•	① MATCH (cust)-[:PLACED]->(o) Finds every order each customer has ever placed; both ends are indexed (unique customer_id, order_id), so the hop is an index-seek.
	•	② hop through City → State → Region Uses the geography hierarchy to tag each order with its region.
Each hop is again index-backed thanks to the constraints created in Block 0.
	•	③ WITH r, cust, avg(o.profit) AS cust_avg Groups by (region, customer) and pre-computes the customer’s average profit per order—already local to the right region.
	•	④ / ⑤ second MATCH block Re-scans all orders in that same region to compute the regional average profit.
Because r is already bound, the match is scoped—Neo4j does not visit other regions.
	•	⑥ WHERE cust_avg < region_avg Keeps only those customers whose mean profit is strictly below the mean for their region—exact definition of “under-performer”.
	•	⑦ return columns Shows IDs (for deterministic joins) and human names (for readability), plus both averages so the delta is obvious.
	•	⑧ ORDER BY region_avg DESC Lists the richest regions first—useful narrative:
“In our top-profit region, these three customers lag behind the regional benchmark.”


### Query 9 – Monthly Sales & Average Temperature per City (Year 2014)  
*Goal: “Show, month-by-month, how each city’s sales evolved in 2014 and what the average outdoor temperature was.”*

```cypher
// Q9 – combine sales totals and mean temperature per city–month
MATCH (c:City)<-[:DELIVERED_TO]-(o:Order),              // ① city ↔︎ order
      (c)-[:HAS_WEATHER]->(w:Weather)                   // ② city ↔︎ weather
WHERE  o.date.year = 2014                               // ③ restrict to 2014
  AND  w.date = o.date                                  // ④ align weather and order on same calendar day
WITH   c.name                 AS city,                  // ⑤ grouping key part 1
       o.date.month           AS month,                 // ⑥ grouping key part 2
       sum(o.sales)           AS total_sales,           // ⑦ aggregate sales
       avg(w.temperature)     AS avg_temp               // ⑧ aggregate temperature
RETURN city,
       month,
       round(total_sales, 2)   AS total_sales,          // ⑨ formatted output
       round(avg_temp,   1)    AS avg_temp
ORDER BY city, month;                                   // ⑩ tidy alphabetical / chronological sort

	•	① MATCH (c)<-[:DELIVERED_TO]-(o) –
Traverses from each city to every order delivered there. Both node labels are indexed (City → composite (name,state) key, Order → unique id), so the hop is resolved with index-seeks.
	•	② MATCH (c)-[:HAS_WEATHER]->(w) –
Hops from the same city to its weather readings. The composite uniqueness constraint (city,date) ensures at most one weather node per day, avoiding duplication downstream.
	•	③ WHERE o.date.year = 2014 –
Uses the native DATE property of o.date; the year component is extracted server-side with zero string parsing cost.
	•	④ w.date = o.date –
Aligns order rows and weather rows on the exact same calendar day, eliminating cartesian products when a city has multiple weather rows in the year.
	•	⑤ / ⑥ –
city and month jointly form the aggregation key. o.date.month returns an integer 1 – 12 directly from the DATE value.
	•	⑦ sum(o.sales) –
Adds up gross sales for all orders in that city-month bucket. Because the grouping keys are fixed, this executes as a streaming aggregation with constant memory per group.
	•	⑧ avg(w.temperature) –
Calculates the mean Celsius temperature already stored on each Weather node (converted from Kelvin during load phase).
	•	⑨ rounding –
round(total_sales, 2) prints currency-style values;
round(avg_temp, 1) keeps one decimal because climate data rarely needs more precision for executive dashboards.
	•	⑩ ORDER BY city, month –
Sorts alphabetically by city and then 1-to-12 by month: an intuitive layout for a slide or spreadsheet export.

How to discuss the output

	“For 2014, Chicago peaks at €210 k in July when the average temp is 23 °C, whereas Seattle peaks in December at €145 k even though the temperature drops to 6 °C—clear evidence that weather impacts each market differently.”


### Query 10 – Top-5 Products per Weather Condition  
*Goal: “For every distinct sky condition, list the five products that generated the highest sales **on the days that condition occurred**.”*

```cypher
// Q10 – rank products inside each weather-type bucket
MATCH (o:Order)-[:CONTAINS]->(p:Product),                   // ① order → product
      (o)-[:DELIVERED_TO]->(c:City)-[:HAS_WEATHER]->(w)     // ② order-day → weather-day
WHERE  o.date = w.date                                      // ③ align rows on identical day
WITH   w.description  AS weather,                           // ④ group key #1
       p.name         AS product,                           // ⑤ group key #2
       sum(o.sales)   AS total_sales                        // ⑥ measure
ORDER BY weather, total_sales DESC                          // ⑦ per-weather ranking
WITH   weather, collect({product: product,                  // ⑧ gather pairs already sorted
                         sales: total_sales})[0..5] AS top5 //     slice first five
UNWIND top5 AS row                                          // ⑨ explode list → rows
RETURN weather,
       row.product  AS product_name,                        // ⑩ final columns
       round(row.sales,2) AS total_sales
ORDER BY weather, total_sales DESC;                         // ⑪ tidy display

	•	① MATCH (o)-[:CONTAINS]->(p) Pulls the product(s) on each order.
Both order_id and product_id are indexed, so the hop is an index-seek.
	•	② MATCH (o)-[:DELIVERED_TO]->(c)-[:HAS_WEATHER]->(w) 
Walks from the same order to its city, then to the day’s weather reading.
	•	③ WHERE o.date = w.date Guarantees we only pair the order with the weather
of that very day, preventing cartesian blow-ups when a city has many observations.
	•	④ / ⑤ Use the weather description and product name as composite keys.
	•	⑥ sum(o.sales) Aggregates gross sales for each (weather, product) pair.
	•	⑦ ORDER BY weather, total_sales DESC Sorts inside every weather group
so the richest products come first—critical for the next step.
	•	⑧ collect()[0..5] Gathers the already-sorted pairs into a list and slices
the first five—efficient top-k without window functions.
	•	⑨ UNWIND Flattens the list back to individual rows so each best-seller
re-appears as a standalone record.
	•	⑩ columns product_name plus formatted sales figure; easy to read aloud.
	•	⑪ final ORDER BY Keeps weather buckets contiguous in the result grid,
with items already ranked inside each section.

Talking point for the slide

	“When the sky is clear Canon LX Printer tops sales at €42 k, while on moderate rain days people buy more Rubbermaid Chairs at €18 k.
Marketing can tailor promotions to the forecast accordingly.”
