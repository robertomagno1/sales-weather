## Ecco una query visuale (da mostrare nel Browser) che restituisce direttamente il grafo dei risultati:

MATCH (c:City)<-[:DELIVERED_TO]-(o:Order)-[:CONTAINS]->(p:Product),
      (c)-[:HAS_WEATHER]->(w:Weather)
WHERE w.date = o.date
  AND w.description CONTAINS "clear"
  AND w.temperature >= 20 AND w.temperature <= 25
  AND w.humidity >= 40 AND w.humidity <= 60
RETURN c, o, p, w
LIMIT 100;