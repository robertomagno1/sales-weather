# Sales × Weather — Relational Data Model in MySQL (+ Neo4j comparison)

End-to-end relational engineering project: integrating retail order lines with daily
weather observations in a **MySQL 8** database designed from scratch — schema design,
constraints, ETL, data-quality checks and query optimisation — with the same model
replicated in **Neo4j** to compare relational and graph access paths.

Team of two: [Roberto Magno Mazzotta](https://github.com/robertomagno1) ·
[Jacopo Caldana](https://github.com/JacopoCaldana)

---

## Data

| Source | Grain | Volume |
|---|---|---|
| `Sample - Superstore.csv` | one row per order line (`order_id` + `product_id`) | 9,994 rows, 21 columns |
| `temperature1.csv`, `humidity.csv`, `description.csv` | one row per city–day | 67,932 rows each, 36 cities, 2012-10-01 → 2017-11-30 |

## Data model

- **Weather tables** (`temperature`, `humidity`, `description`): composite primary key
  `(date, city)` — the measurement is unique per city-day, so no surrogate key is needed —
  plus secondary indexes on `city` and `date`.
- **Staging** (`orders_raw`): loaded verbatim, dates kept as strings, then parsed explicitly
  with `STR_TO_DATE(order_date, '%d/%m/%y')`.
- **Integration**: `weather_condition` joins the three measures on `(date, city)`;
  `sales_weather` joins orders to weather on parsed date **and** city.
- **Target table** (`sales_weather_clean`): typed columns (`DATE`, `DECIMAL`), `NOT NULL`
  on keys, `CHECK (quantity > 0)` and `CHECK (discount BETWEEN 0 AND 1)`, and seven
  secondary indexes on the columns used for filtering and grouping.
- `order_id` is deliberately **not** a primary key: one order with three items produces
  three rows. The grain is the order line — documented in `sql/04_clean_model_and_quality.sql`.

## Data quality

Duplicate-key check on `row_id` (2 duplicates found), NULL check on identifiers, explicit
date parsing instead of implicit casts, and a documented rationale for every constraint.

## Query optimisation

`EXPLAIN ANALYZE` on the regional averages filtered by `weather_description` showed a
poorly selective index scan: **3,616 rows read to keep 1,563 (~43%)**. Two indexes were
added — a composite `(weather_description, region)` covering both the `WHERE` and the
`GROUP BY`, and a covering variant `(weather_description, region, sales)` that also
carries the aggregated column. Separately, the typed and indexed target table **halved a
full-table read (0.15 s → 0.08 s)** compared with the untyped join table.

> Timings were measured locally with `EXPLAIN ANALYZE`; they are indicative, not a
> controlled benchmark.

## Analytics

19 analytical queries (`sql/03_*`, `sql/05_*`): weather distributions per city, regional
sales and profit, customer profitability against the regional average, product and
sub-category performance conditioned on weather, and rankings built with
`RANK() OVER (PARTITION BY ...)`.

## Repository layout

```
sql/
  01_schema.sql                  staging table, weather tables, PKs and indexes
  02_etl_join.sql                weather view and the date-parsed sales × weather join
  03_analytics_core.sql          Q1–Q10
  04_clean_model_and_quality.sql typed target table, constraints, indexes, DQ checks
  05_analytics_weather.sql       Q11–Q19
  06_query_optimization.sql      EXPLAIN ANALYZE, composite and covering indexes
neo4j/
  graph_model.cypher             uniqueness constraints, Region→State→City→Order/Product
  queries_commented.md           Q1–Q10 in Cypher, commented
dataset/                         source CSVs
docs/report_it.docx              original project report (Italian)
```

## Relational vs graph

The Neo4j layer models the same facts as `Region → State → City → {Customer, Product, Order}`
with `HAS_WEATHER` edges. It expresses path queries more directly and avoids repeated joins
on the geographic hierarchy; the relational model remains stronger for column-wise
aggregation over the full fact table, which is what most of the analytical questions here
actually need.

## Reproduce

```bash
mysql -u <user> -p < sql/01_schema.sql   # then load dataset/*.csv into the staging tables
mysql -u <user> -p sales_data < sql/02_etl_join.sql
mysql -u <user> -p sales_data < sql/04_clean_model_and_quality.sql
mysql -u <user> -p sales_data < sql/06_query_optimization.sql
```

Built for the Databases & Big Data course, Sapienza University of Rome.
