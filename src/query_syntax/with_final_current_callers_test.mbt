// Exact current caller sources; values and schemas remain independent.

///|
test "WITH final source callers parse" {
  for
    text in [
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload FROM records WHERE id > @minimum) , g AS (GRAPH (NODE TABLES (objects AS N KEY (id) LABEL Person PROPERTIES (id, payload)))) FROM GRAPH g |> MATCH WALK (a:Person) |> SELECT a.id AS id, a.payload.score AS score |> ORDER BY id |> RESULT matched",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload FROM records WHERE id > @minimum) , g AS (GRAPH (NODE TABLES (objects AS N KEY (id) LABEL Person PROPERTIES (id, payload)))) FROM GRAPH g |> MATCH WALK (a:Person) |> SELECT a.id AS id, a.payload.SCORE AS score |> ORDER BY id |> RESULT matched",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload FROM records WHERE id > @minimum) , g AS (GRAPH (NODE TABLES (objects AS N KEY (id) LABEL Person PROPERTIES (id, payload)))) FROM GRAPH g |> MATCH WALK (a:Person) |> SELECT `A`.`ID` AS id, `A`.`PAYLOAD`.`ScOrE` AS score |> ORDER BY id |> RESULT matched",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload FROM records WHERE id > @minimum) , g AS (GRAPH (NODE TABLES (objects AS N KEY (id) LABEL Person PROPERTIES (id, payload)))) FROM GRAPH g |> MATCH WALK (a:Person) |> SELECT a.id AS id, a.payload AS kept |> SELECT id, kept.SCORE AS score |> ORDER BY id |> RESULT matched",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload FROM records WHERE id > @minimum) , g AS (GRAPH (NODE TABLES (objects AS N KEY (id) LABEL Person PROPERTIES (id, payload)))) FROM GRAPH g |> MATCH WALK (a:Person) |> WHERE a.payload.SCORE IS NULL |> SELECT a.id AS id, a.payload.SCORE AS score |> ORDER BY id |> RESULT matched",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload FROM records WHERE id > @minimum) , g AS (GRAPH (NODE TABLES (objects AS N KEY (id) LABEL Person PROPERTIES (id, payload)))) FROM GRAPH g |> MATCH WALK (a:Person) |> WHERE a.payload.SCORE > 100 |> SELECT a.id AS id, a.payload.SCORE AS score |> ORDER BY id |> RESULT matched",
    ] {
    let _ = parse_query_script(text, query_limits()).unwrap()
  }
}

///|
test "WITH final graph callers parse" {
  for
    text in [
      "WITH n AS (SELECT 1 AS node_key, 7 AS p) , g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p)))) , changes AS (SELECT JSON r'''{\"base_graph_cid\":\"sha256:c8cc2e373daae2ed0889d0584c3bf8c17267b97cb69ff84b2d5c51bbca715521\",\"edges\":{\"add\":[],\"remove\":[],\"update\":[]},\"graph_contract_cid\":\"sha256:8cd1d8aacc3f58ba719dd5e1219fb49c53bd1908e724606511a7147790a94a17\",\"nodes\":{\"add\":[],\"remove\":[],\"update\":[{\"after\":{\"id\":{\"definition\":\"N\",\"domain\":\"sha256:d1f467b6f6bf05cf2676ee816a7d0b5666ba19e68a52072177e0fa3c8b98bd14\",\"key\":[1],\"key_types\":[{\"kind\":\"number\"}]},\"key\":[1],\"props\":{\"p\":8}},\"before\":{\"id\":{\"definition\":\"N\",\"domain\":\"sha256:d1f467b6f6bf05cf2676ee816a7d0b5666ba19e68a52072177e0fa3c8b98bd14\",\"key\":[1],\"key_types\":[{\"kind\":\"number\"}]},\"key\":[1],\"props\":{\"p\":7}}}]},\"target_graph_cid\":\"sha256:aeb95420b23c14424e553374173364d5503df5eb33eef35406e464feee47ceb5\",\"version\":\"actql-graph-delta/0.1\"}''' AS delta) FROM g |> apply_graph_delta(with: changes, field: \"delta\") |> node_rows() |> SELECT p, node_key |> RESULT answer",
    ] {
    let _ = parse_query_script(text, query_limits()).unwrap()
  }
}

///|
test "WITH final pipe callers parse" {
  for
    text in [
      "FROM records AS old |> SELECT id + 10 AS key, amount |> AS l |> WHERE l.key >= @minimum |> ORDER BY key |> LIMIT @take |> JOIN (SELECT 13 AS key) AS r ON l.key = r.key MAX_OUTPUT_ROWS 10 |> SELECT l.amount AS amount, l.key AS key, r.key AS matched |> ORDER BY key, amount NULLS FIRST",
      "SELECT id + 10 AS key, amount FROM records AS old |> AS l |> WHERE l.key >= @minimum |> ORDER BY key |> LIMIT @take |> JOIN (SELECT 13 AS key) AS r ON l.key = r.key MAX_OUTPUT_ROWS 10 |> SELECT l.amount AS amount, l.key AS key, r.key AS matched |> ORDER BY key, amount NULLS FIRST",
      "WITH joined AS (FROM records AS old |> SELECT id + 10 AS key, amount |> AS l |> WHERE l.key >= @minimum |> ORDER BY key |> LIMIT @take |> JOIN (SELECT 13 AS key) AS r ON l.key = r.key MAX_OUTPUT_ROWS 10 |> SELECT l.amount AS amount, l.key AS key, r.key AS matched |> ORDER BY key, amount NULLS FIRST) FROM joined |> RESULT answer",
      "FROM records AS old |> SELECT id + 10 AS key, amount |> AS l |> WHERE l.key >= @minimum |> ORDER BY key |> LIMIT @take |> JOIN (SELECT 13 AS key) AS r ON l.key = r.key MAX_OUTPUT_ROWS 10 |> SELECT l.amount AS amount, l.key AS key, r.key AS matched |> ORDER BY key, amount NULLS FIRST",
      "FROM records AS old |> SELECT id + 10 AS key, amount |> AS l |> WHERE l.key >= @minimum |> ORDER BY key |> LIMIT @take |> LEFT JOIN (SELECT 12 AS key) AS r ON l.key = r.key MAX_OUTPUT_ROWS 10 |> SELECT l.amount AS amount, l.key AS key, r.key AS matched |> ORDER BY key, amount NULLS FIRST",
      "FROM records AS old |> SELECT id + 10 AS key, amount |> AS previous |> SET key = key + 1 |> AS l |> WHERE l.key >= @minimum |> ORDER BY key |> LIMIT @take |> JOIN (SELECT 13 AS key) AS r ON l.key = r.key MAX_OUTPUT_ROWS 10 |> SELECT l.amount AS amount, l.key AS key, r.key AS matched |> ORDER BY key, amount NULLS FIRST",
      "FROM records AS old |> SELECT id + 10 AS key, amount |> WHERE key >= @minimum |> ORDER BY key |> LIMIT @take |> JOIN (SELECT 13 AS k) AS r ON key = r.k MAX_OUTPUT_ROWS 10 |> SELECT amount AS amount, key AS key, r.k AS matched |> ORDER BY key, amount NULLS FIRST",
      "FROM records AS l |> JOIN (SELECT 3 AS k) AS r ON l.id = r.k MAX_OUTPUT_ROWS 10 |> WHERE r.k > 2 |> JOIN (SELECT 3 AS k) AS s ON r.k = s.k MAX_OUTPUT_ROWS 10 |> SELECT l.amount AS amount, l.id AS key, s.k AS matched |> ORDER BY key",
      "FROM records AS old |> SELECT amount, id |> AS l |> WHERE l.id = 3 |> CROSS JOIN records AS r MAX_OUTPUT_ROWS 10 |> SELECT l.amount AS amount, l.id AS key, r.id AS matched |> ORDER BY key, matched",
      "FROM records |> AGGREGATE COUNT(*) AS n GROUP BY id |> AS l |> JOIN (SELECT 3 AS k) AS r ON l.id = r.k MAX_OUTPUT_ROWS 10 |> SELECT l.n AS n, l.id AS id |> ORDER BY id",
    ] {
    let _ = parse_query_script(text, query_limits()).unwrap()
  }
}

///|
test "WITH final two callers parse" {
  for
    text in [
      "WITH left_rows AS (FROM left_records |> WHERE id >= 0 |> SELECT id, amount)\n, right_rows AS (FROM right_records |> WHERE id >= 0 |> SELECT id, amount)\n, joined_rows AS (SELECT l.id AS id, l.amount AS left_amount, r.amount AS right_amount\n  FROM left_rows AS l JOIN right_rows AS r ON l.id = r.id MAX_OUTPUT_ROWS 100)\nFROM joined_rows\n  |> WHERE id = 1\n  |> EXTEND 'high' AS risk, 'a00000000000002' AS target_id, 'review-required' AS next_name\n  |> SELECT id, left_amount, right_amount, risk, target_id, next_name\n  |> ORDER BY id, left_amount, right_amount\n  |> RESULT updates\n",
      "WITH left_rows AS (FROM left_records |> WHERE id >= 0 |> SELECT id, amount)\n, right_rows AS (FROM right_records |> WHERE id >= 0 |> SELECT id, amount)\n, joined_rows AS (SELECT l.id AS id, l.amount AS left_amount, r.amount AS right_amount\n  FROM left_rows AS l JOIN right_rows AS r ON l.id = r.id MAX_OUTPUT_ROWS 100)\nFROM joined_rows\n  |> WHERE id = 1\n  |> EXTEND 'high' AS risk, 'a00000000000002' AS target_id, 'review-required' AS next_name\n  |> SELECT id, left_amount, right_amount, risk, target_id, next_name\n  |> ORDER BY id, left_amount, right_amount\n  |> RESULT updates\n  |> EFFECT save UPDATE TARGET 'connector://crm-main/Test_Record__c'\n     MAPPING `__PUBLICATION_MAPPING_REF__`\n     FROM RESULT updates ID target_id SET (Name = next_name)\n",
    ] {
    let _ = parse_query_script(text, query_limits()).unwrap()
  }
}

///|
test "WITH final python callers parse" {
  for
    text in [
      "WITH seed AS (SELECT 1 AS n) FROM seed |> EXTEND n + 1 AS value |> SELECT value |> RESULT answer",
    ] {
    let _ = parse_query_script(text, query_limits()).unwrap()
  }
}

///|
test "WITH final snapshot callers parse" {
  for
    text in [
      "\nWITH n AS (SELECT 1 AS id)\n , e AS (SELECT 10 AS key, 1 AS src, 1 AS dst\n  UNION ALL SELECT 11 AS key, 1 AS src, 1 AS dst)\n , g AS (GRAPH (\n  NODE TABLES (n AS N KEY (id) LABEL Node NO PROPERTIES)\n  EDGE TABLES (e AS E KEY (key)\n    SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N\n    LABEL R NO PROPERTIES)\n))\nFROM GRAPH g |> MATCH p = TRAIL (:Node)-[:R]->(:Node)-[:R]->(:Node)\n  |> SELECT PATH_LENGTH(p) AS depth |> RESULT paths\n",
    ] {
    let _ = parse_query_script(text, query_limits()).unwrap()
  }
}
