# 📊 Assignment 3 – Presentazione Progetto NoSQL con Neo4j

## 🎯 Obiettivo della presentazione (15 minuti)

Spiegare al docente:

1. Perché abbiamo scelto **Neo4j** (database a grafo) rispetto ad altri NoSQL
2. Come abbiamo **modellato e importato** i dati
3. Come abbiamo **riscritto le query SQL** in **Cypher**, con esempi visivi
4. Differenze pratiche tra SQL e Cypher e vantaggi del grafo

---

## 1. 🔧 Perché Neo4j è la scelta giusta per questo progetto

| Caratteristica richiesta                                 | SQL tradizionale         | Neo4j (grafo)                                             |
| -------------------------------------------------------- | ------------------------ | --------------------------------------------------------- |
| Relazioni complesse tra clienti, ordini, prodotti, meteo | JOIN su molte tabelle    | Archi diretti tra nodi: `(:Customer)-[:PLACED]->(:Order)` |
| Navigazione geografica (Region → State → City)           | JOIN in cascata          | Traversal con `MATCH` in 1 riga                           |
| Query su più livelli (es. vendite meteo)                 | Subquery o JOIN multipli | Pattern-matching semplice su archi                        |
| Visualizzazione intuitiva del grafo                      | Non nativa               | ✔ Grafo interattivo in Neo4j Desktop                      |

---

## 2. 👁  Modellazione e Importazione Dati

### 2.1 ✨ Vincoli e struttura

```cypher
CREATE CONSTRAINT city_name     IF NOT EXISTS FOR (c:City)     REQUIRE c.name IS UNIQUE;
CREATE CONSTRAINT state_name    IF NOT EXISTS FOR (s:State)    REQUIRE s.name IS UNIQUE;
CREATE CONSTRAINT region_name   IF NOT EXISTS FOR (r:Region)   REQUIRE r.name IS UNIQUE;
CREATE CONSTRAINT customer_id   IF NOT EXISTS FOR (c:Customer) REQUIRE c.id IS UNIQUE;
CREATE CONSTRAINT product_id    IF NOT EXISTS FOR (p:Product)  REQUIRE p.id IS UNIQUE;
CREATE CONSTRAINT order_id      IF NOT EXISTS FOR (o:Order)    REQUIRE o.id IS UNIQUE;
CREATE CONSTRAINT weather_key   IF NOT EXISTS FOR (w:Weather)  REQUIRE (w.city, w.date) IS UNIQUE;
```

### 2.2 → Importazione `sales_final.csv`

```cypher
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
```

### 2.3 ❄ Meteo: `description.csv`, `temperature1.csv`, `humidity.csv`

Import simile, unendo i dati meteo al nodo `Weather` collegato a `City` tramite `[:HAS_WEATHER]`.

---

## 3. 🔢 Esecuzione Query in Cypher

> In SQL: query con JOIN su 3-4 tabelle.
> In Cypher: pattern su nodi e archi già collegati.

### Esempio Q1: Media temperatura e umidità per città

```cypher
MATCH (c:City)-[:HAS_WEATHER]->(w:Weather)
RETURN c.name AS city,
       round(avg(w.temperature), 2) AS avg_temp,
       round(avg(w.humidity), 2) AS avg_humidity
ORDER BY city;
```

### Esempio Q4: Clienti più profittevoli

```cypher
MATCH (cust:Customer)-[:PLACED]->(o:Order)
RETURN cust.id, cust.name, round(sum(o.profit),2) AS total_profit
ORDER BY total_profit DESC
LIMIT 10;
```

### Esempio Q7: Prodotto top in giornate "sky is clear"

```cypher
MATCH (r:Region)<-[:IN_REGION]-(:State)<-[:IN_STATE]-(c:City),
      (c)<-[:DELIVERED_TO]-(o:Order)-[:CONTAINS]->(p:Product),
      (c)-[:HAS_WEATHER]->(w:Weather)
WHERE w.description CONTAINS "sky is clear" AND w.date = o.date
WITH r, p.name AS product, sum(o.sales) AS total_sales
ORDER BY r.name, total_sales DESC
WITH r.name AS region, collect({product: product, sales: total_sales})[0] AS top_product
RETURN region, top_product.product AS product_name, top_product.sales AS sales_value;
```

---

## 4. 🚀 Come presentarlo al professore (schema da seguire)

| Minuto | Cosa mostrare                                        | Note                                                 |
| ------ | ---------------------------------------------------- | ---------------------------------------------------- |
| 0-1    | Slide titolo + gruppo                                | Nome, dataset, obiettivo HW3                         |
| 1-3    | Differenze SQL vs Neo4j                              | JOIN vs PATTERN, grafo nativo                        |
| 3-6    | Vincoli + Import (Cypher live)                       | Mostra `CREATE CONSTRAINT` e `CALL { LOAD CSV ... }` |
| 6-10   | Query chiave: Q1, Q4, Q7                             | Mostra output + grafo in Neo4j Browser               |
| 10-12  | Visualizzazione con `CALL db.schema.visualization()` | Espandi nodi Customer, Product, Order                |
| 12-14  | Esempio query "grafica" per demo finale              | `MATCH path = (...) RETURN path`                     |
| 14-15  | Conclusione + domande                                | Ripeti vantaggi: chiarezza, velocità, leggibilità    |

---

## 5. 📈 Differenze SQL ↔ Cypher da evidenziare

| Concetto        | SQL                        | Cypher                                  |
| --------------- | -------------------------- | --------------------------------------- |
| JOIN            | `JOIN` esplicito su PK/FK  | relazioni predefinite (es. `[:PLACED]`) |
| GROUP BY        | `GROUP BY` + funzioni agg. | `WITH` + `RETURN` con agg.              |
| Subquery        | CTE o subselect            | `WITH` + altro `MATCH` sequenziale      |
| WHERE           | su colonne                 | su proprietà di nodi o archi            |
| Visualizzazione | Tabelle                    | Grafo interattivo (Browser, Bloom)      |

---

## 🚀 Conclusione pronta per l'orale

> "Con Neo4j abbiamo trasformato una base dati relazionale in un grafo semantico dove i JOIN diventano archi diretti, rendendo le query più veloci, leggibili e visivamente navigabili. Questo approccio è particolarmente efficace quando le entità sono densamente collegate, come nel nostro caso tra clienti, ordini, città e condizioni meteo."

> "In 15 minuti abbiamo mostrato il modello, il codice Cypher, le query e il grafo: tutto integrato, visivo e pronto all'analisi."

---

*Progetto completo, validato, documentato. Pronto per il 30 e lode.*
