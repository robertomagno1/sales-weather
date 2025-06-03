 🌦️ Sales & Weather Analysis Project

An advanced SQL + NoSQL (Neo4j) project analyzing how weather affects sales by integrating two datasets in both **relational** and **graph-based** architectures.

---

## 📌 Project Goals

- Integrate heterogeneous data (sales and weather) into both relational and graph databases.
- Compare SQL (PostgreSQL/SQLite) and NoSQL (Neo4j) solutions.
- Optimize data loading and structure (constraints, indexes).
- Perform complex queries: sales trends under weather conditions, geolocation-aware analysis, customer/product performance.

---

## 🧱 Technologies Used

| Layer            | Technology        |
|------------------|-------------------|
| Relational DB     | SQL (PostgreSQL, SQLite) |
| Graph DB          | Neo4j (Cypher) |
| Data Tools        | CSV (weather, sales), DBeaver, Neo4j Desktop |
| Optional Interface | Jupyter (SQL + Python), pgAdmin, SQLite Browser |

---

## 📂 Project Structure

### 📁 `sql/` - Relational Version
```
├── 00_create_tables.sql          # Create raw tables of sales and weather
├── 01_create_view_weather.sql    # Create weather view
├── 02_join_weather_sales.sql     # Join and merge datasets
├── 03_clean_optimized_table.sql  # Create optimized clean table
├── 04_queries.sql                # Final SQL analysis queries
├── README_queries.md             # Explanations of advanced SQL queries
```

### 📁 `neo4j/` - Graph Version (Assignment 3)
```
├── query_cypher.rtf              # Cypher scripts: constraints, data import, queries
├── Neo4j-ExamplesInSlides.txt    # Sample Cypher syntax from class slides
├── sales_final.csv               # Sales data
├── weather_final.csv             # Weather data
├── humidity.csv / temperature.csv / description.csv
```

---

## 🧭 Step-by-Step Execution

### 🔸 **Relational DB (SQL)**

1. Create tables (`00_create_tables.sql`)
2. Generate weather view (`01_create_view_weather.sql`)
3. Join datasets (`02_join_weather_sales.sql`)
4. Optimize & clean (`03_clean_optimized_table.sql`)
5. Run analytical queries (`04_queries.sql`)

### 🔸 **Graph DB (Neo4j)**

1. Setup constraints and unique keys (`query_cypher.rtf`, section 0)
2. Load sales data, create hierarchy: Region → State → City → Customer/Product/Order
3. Load weather data from `description.csv`, `temperature.csv`, `humidity.csv`
4. Update weather node properties (temperature, humidity)
5. Run graph queries (`query_cypher.rtf`, Q1–Q10):
   - Avg temp/humidity by city
   - Regional sales/profit
   - High sales on sunny days
   - Customer/product insights based on weather
   - Monthly/seasonal trends

---

## 📊 Example Cypher Queries

```cypher
// Average temperature & humidity per city
MATCH (c:City)-[:HAS_WEATHER]->(w:Weather)
RETURN c.name AS city, avg(w.temperature) AS avg_temp, avg(w.humidity) AS avg_humidity;
```

```cypher
// Top 5 selling products on sunny days
MATCH (o:Order)-[:CONTAINS]->(p:Product),
      (o)-[:DELIVERED_TO]->(c:City)-[:HAS_WEATHER]->(w:Weather)
WHERE w.date = o.date AND w.description CONTAINS "sky is clear"
WITH w.description AS weather, p.name AS product, sum(o.sales) AS sales_total
ORDER BY weather, sales_total DESC
WITH weather, collect({product: product, sales: sales_total})[0..5] AS top5
UNWIND top5 AS row
RETURN weather, row.product AS product_name, row.sales AS total_sales;
```

---

## 🧠 Key Learning Outcomes

| SQL                                 | Neo4j (Graph DB)                             |
|-------------------------------------|----------------------------------------------|
| Rigid schema, JOINs for relations   | Schema-less, explicit relationships          |
| Slower for recursive traversals     | Fast path traversal with O(1) hops           |
| Complex aggregation via GROUP BY    | Ad-hoc aggregation using pattern matching    |
| Less flexible to schema changes     | Easy to expand (add properties, labels, rels)|

---

## 🧪 Performance Insights

- Relational joins become heavy in deep multi-level aggregations.
- Neo4j is significantly faster for path-based and recursive queries (e.g., weather → city → order → product).
- Neo4j shows higher flexibility and better expression for “real-world” relationships like weather impact on customer behavior.

---

## 📬 Contacts

- [GitHub: Roberto Magno](https://github.com/robertomagno1)
- [GitHub: Jacopo Caldana](https://github.com/JacopoCaldana)

---

## 🎉 Final Note

This project demonstrates how **SQL and Graph DBs can complement each other**, highlighting the trade-offs between relational integrity and graph-based expressiveness.

Happy querying! 🚀🌤️




