///|
// Exact current authored success texts whose retired outer declarations change.
// This executes the real parser, not Host/provider acquisition or publication.

///|
test "WITH current Relation public callers aggregate-order-parameter" {
  for
    text in [
      "WITH labels AS (SELECT id, CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY @key DESC NULLS LAST, id) AS names FROM labels",
      "WITH labels AS (SELECT id, CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name FROM records WHERE id > 0) FROM labels |> AGGREGATE STRING_AGG(name, '|' ORDER BY (@`KEY`) DESC NULLS LAST, id) AS names",
      "WITH labels AS (SELECT id, CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY @key DESC NULLS LAST, id) AS names FROM labels",
      "WITH labels AS (SELECT id, CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY @NAME DESC NULLS LAST, id) AS names FROM labels",
      "WITH labels AS (SELECT id, CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name FROM records WHERE id > 0) FROM labels |> AGGREGATE STRING_AGG(name, '|' ORDER BY ((@`CFG`)).`rank` DESC NULLS LAST, id) AS names",
      "WITH labels AS (SELECT id, CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name FROM records WHERE id > 0) FROM labels |> AGGREGATE STRING_AGG(name, '|' ORDER BY ((@`CFG`)).`rank` DESC NULLS LAST, id) AS names",
      "WITH labels AS (SELECT id, CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name FROM records WHERE id > 0) FROM labels |> AGGREGATE STRING_AGG(name, '|' ORDER BY ((@`CFG`)).`rank` DESC NULLS LAST, id) AS names",
      "WITH labels AS (SELECT id, CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' WHERE id <= 2 ORDER BY @key DESC NULLS LAST, id) AS names FROM labels",
      "WITH labels AS (SELECT id, CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY @key DESC NULLS LAST, id) AS names FROM labels",
      "WITH labels AS (SELECT id, CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name FROM records WHERE id > 0) SELECT STRING_AGG(DISTINCT @label, '|' ORDER BY @LABEL) AS names FROM labels",
      "WITH labels AS (SELECT id, CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name FROM records WHERE id > 0) FROM labels |> AGGREGATE STRING_AGG(DISTINCT @`LABEL`, '|' ORDER BY (@label)) AS names",
    ] {
    let script = parse_query_script(text, query_limits()).unwrap()
    assert_true(query_binding_count(script_query(script)) > 0)
  }
}

///|
test "WITH current Relation public callers aggregate-property" {
  for
    text in [
      "WITH objects AS (SELECT 2 AS id, 'A' AS bucket, @a AS payload, @oa AS other UNION ALL SELECT 1 AS id, 'A' AS bucket, @b AS payload, @ob AS other UNION ALL SELECT 3 AS id, 'A' AS bucket, @c AS payload, @oc AS other UNION ALL SELECT 5 AS id, 'A' AS bucket, @d AS payload, @od AS other UNION ALL SELECT 6 AS id, 'A' AS bucket, @e AS payload, @oe AS other UNION ALL SELECT 4 AS id, 'B' AS bucket, @f AS payload, @of AS other) SELECT bucket, COUNT(payload.score) AS n, COUNT(DISTINCT payload.score) AS d, COUNTIF(payload.score >= 20) AS h, SUM(payload.score) AS s, AVG(payload.score) AS a, MIN(payload.score) AS lo, MAX(payload.score) AS hi FROM objects GROUP BY bucket ORDER BY bucket",
      "WITH objects AS (SELECT 2 AS id, 'A' AS bucket, @a AS payload, @oa AS other UNION ALL SELECT 1 AS id, 'A' AS bucket, @b AS payload, @ob AS other UNION ALL SELECT 3 AS id, 'A' AS bucket, @c AS payload, @oc AS other UNION ALL SELECT 5 AS id, 'A' AS bucket, @d AS payload, @od AS other UNION ALL SELECT 6 AS id, 'A' AS bucket, @e AS payload, @oe AS other UNION ALL SELECT 4 AS id, 'B' AS bucket, @f AS payload, @of AS other) FROM objects |> AGGREGATE COUNT(payload.score) AS n, COUNT(DISTINCT payload.score) AS d, COUNTIF(payload.score >= 20) AS h, SUM(payload.score) AS s, AVG(payload.score) AS a, MIN(payload.score) AS lo, MAX(payload.score) AS hi GROUP BY bucket |> SELECT bucket, n, d, h, s, a, lo, hi |> ORDER BY bucket",
      "WITH objects AS (SELECT 2 AS id, 'A' AS bucket, @a AS payload, @oa AS other UNION ALL SELECT 1 AS id, 'A' AS bucket, @b AS payload, @ob AS other UNION ALL SELECT 3 AS id, 'A' AS bucket, @c AS payload, @oc AS other UNION ALL SELECT 5 AS id, 'A' AS bucket, @d AS payload, @od AS other UNION ALL SELECT 6 AS id, 'A' AS bucket, @e AS payload, @oe AS other UNION ALL SELECT 4 AS id, 'B' AS bucket, @f AS payload, @of AS other) SELECT bucket, COUNT(`objects`.`payload`.`score` + 1) AS n, SUM(objects.payload.score + 1) AS s FROM objects GROUP BY bucket ORDER BY bucket",
      "WITH objects AS (SELECT 2 AS id, 'A' AS bucket, @a AS payload, @oa AS other UNION ALL SELECT 1 AS id, 'A' AS bucket, @b AS payload, @ob AS other UNION ALL SELECT 3 AS id, 'A' AS bucket, @c AS payload, @oc AS other UNION ALL SELECT 5 AS id, 'A' AS bucket, @d AS payload, @od AS other UNION ALL SELECT 6 AS id, 'A' AS bucket, @e AS payload, @oe AS other UNION ALL SELECT 4 AS id, 'B' AS bucket, @f AS payload, @of AS other) FROM objects AS before |> SET payload = other |> AGGREGATE COUNT(payload.score) AS current_count, COUNT(before.payload.score) AS original_count",
      "WITH objects AS (SELECT 2 AS id, 'A' AS bucket, @a AS payload, @oa AS other UNION ALL SELECT 1 AS id, 'A' AS bucket, @b AS payload, @ob AS other UNION ALL SELECT 3 AS id, 'A' AS bucket, @c AS payload, @oc AS other UNION ALL SELECT 5 AS id, 'A' AS bucket, @d AS payload, @od AS other UNION ALL SELECT 6 AS id, 'A' AS bucket, @e AS payload, @oe AS other UNION ALL SELECT 4 AS id, 'B' AS bucket, @f AS payload, @of AS other) SELECT COUNT(payload.score) AS n, SUM(payload.score) AS s, AVG(payload.score) AS a, MIN(payload.score) AS lo FROM objects WHERE FALSE",
      "WITH objects AS (SELECT 2 AS id, 'A' AS bucket, @a AS payload, @oa AS other UNION ALL SELECT 1 AS id, 'A' AS bucket, @b AS payload, @ob AS other UNION ALL SELECT 3 AS id, 'A' AS bucket, @c AS payload, @oc AS other UNION ALL SELECT 5 AS id, 'A' AS bucket, @d AS payload, @od AS other UNION ALL SELECT 6 AS id, 'A' AS bucket, @e AS payload, @oe AS other UNION ALL SELECT 4 AS id, 'B' AS bucket, @f AS payload, @of AS other) SELECT COUNT(payload.score) AS payload, COUNT(other.score) AS other FROM objects",
      "WITH objects AS (SELECT 2 AS id, 'A' AS bucket, @a AS payload, @oa AS other UNION ALL SELECT 1 AS id, 'A' AS bucket, @b AS payload, @ob AS other UNION ALL SELECT 3 AS id, 'A' AS bucket, @c AS payload, @oc AS other UNION ALL SELECT 5 AS id, 'A' AS bucket, @d AS payload, @od AS other UNION ALL SELECT 6 AS id, 'A' AS bucket, @e AS payload, @oe AS other UNION ALL SELECT 4 AS id, 'B' AS bucket, @f AS payload, @of AS other) SELECT id, COUNT(payload.score) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running FROM objects ORDER BY id",
    ] {
    let script = parse_query_script(text, query_limits()).unwrap()
    assert_true(query_binding_count(script_query(script)) > 0)
  }
}

///|
test "WITH current Relation public callers aggregate-signed-order" {
  for
    text in [
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY -payload.score NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects AS before |> AGGREGATE STRING_AGG(name, '|' ORDER BY +((before.payload).score) NULLS LAST, id) AS names",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects AS before |> SET payload = other |> AGGREGATE STRING_AGG(name, '|' ORDER BY -payload.score NULLS LAST, id) AS `current`, STRING_AGG(name, '|' ORDER BY -before.payload.score NULLS LAST, id) AS previous",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT COUNT(*) AS payload, STRING_AGG(name, '|' ORDER BY -payload.score NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY -id NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY -(-payload.score) NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY -payload.score NULLS FIRST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' WHERE id <= 2 ORDER BY -payload.score NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY -payload.score NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(IF(id / (id - id) = 0, name, name), '|' WHERE FALSE ORDER BY -payload.score NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects |> ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4 |> AGGREGATE ARRAY_AGG(id IGNORE NULLS ORDER BY -payload.score NULLS LAST, id) AS ids",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY -@key NULLS LAST, id) AS names FROM objects",
    ] {
    let script = parse_query_script(text, query_limits()).unwrap()
    assert_true(query_binding_count(script_query(script)) > 0)
  }
}

///|
test "WITH current Relation public callers analytic-order" {
  for
    text in [
      "WITH objects AS (SELECT 2 AS id, @a AS payload, @oa AS other UNION ALL SELECT 1 AS id, @b AS payload, @ob AS other UNION ALL SELECT 3 AS id, @c AS payload, @oc AS other) SELECT id, payload.score AS original_score, other AS payload, ROW_NUMBER() OVER (ORDER BY payload.score + 1 NULLS LAST, id) AS pos FROM objects ORDER BY id",
    ] {
    let script = parse_query_script(text, query_limits()).unwrap()
    assert_true(query_binding_count(script_query(script)) > 0)
  }
}

///|
test "WITH current Relation public callers analytic-partition-expression" {
  for
    text in [
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @a WHEN id = 2 THEN @b WHEN id = 3 THEN @c ELSE @e END AS payload, @d AS other FROM records WHERE id > 0) SELECT id, ROW_NUMBER() OVER (PARTITION BY COALESCE(payload.bucket, 'missing'), COALESCE((objects.payload).`BUCKET`, 'missing') ORDER BY id) AS pos, RANK() OVER (PARTITION BY COALESCE((payload).bucket, 'missing') ORDER BY id DESC) AS ranking FROM objects ORDER BY id",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @a WHEN id = 2 THEN @b WHEN id = 3 THEN @c ELSE @e END AS payload, @d AS other FROM records WHERE id > 0) SELECT id, ROW_NUMBER() OVER (PARTITION BY COALESCE(payload.bucket, 'missing'), COALESCE((objects.payload).`BUCKET`, 'missing') ORDER BY id) AS pos, RANK() OVER (PARTITION BY COALESCE(other.bucket, 'missing') ORDER BY id DESC) AS ranking FROM objects ORDER BY id",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @a WHEN id = 2 THEN @b WHEN id = 3 THEN @c ELSE @e END AS payload, @d AS other FROM records WHERE id > 0) SELECT id, ROW_NUMBER() OVER (PARTITION BY COALESCE(payload.bucket, 'missing'), COALESCE((objects.payload).`BUCKET`, 'missing') ORDER BY id) AS pos, RANK() OVER (PARTITION BY COALESCE((payload).bucket, 'missing') ORDER BY id DESC) AS ranking FROM objects ORDER BY id",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @a WHEN id = 2 THEN @b WHEN id = 3 THEN @c ELSE @e END AS payload, @d AS other FROM records WHERE id > 0) SELECT id, ROW_NUMBER() OVER (PARTITION BY COALESCE(payload.bucket, 'missing'), COALESCE((objects.payload).`BUCKET`, 'missing') ORDER BY id) AS pos, RANK() OVER (PARTITION BY COALESCE(other.bucket, 'missing') ORDER BY id DESC) AS ranking FROM objects ORDER BY id",
    ] {
    let script = parse_query_script(text, query_limits()).unwrap()
    assert_true(query_binding_count(script_query(script)) > 0)
  }
}

///|
test "WITH current Relation public callers analytic-partition-property" {
  for
    text in [
      "WITH objects AS (SELECT id, CASE WHEN id = 3 THEN @none WHEN id = 5 THEN @empty WHEN id = 1 THEN @b ELSE @a END AS payload, CASE WHEN id = 2 OR id = 3 THEN @oa ELSE @ob END AS other FROM records WHERE id > 0) SELECT id, ROW_NUMBER() OVER (PARTITION BY payload.bucket ORDER BY id) AS pos FROM objects ORDER BY id",
      "WITH objects AS (SELECT id, CASE WHEN id = 3 THEN @none WHEN id = 5 THEN @empty WHEN id = 1 THEN @b ELSE @a END AS payload, CASE WHEN id = 2 OR id = 3 THEN @oa ELSE @ob END AS other FROM records WHERE id > 0) FROM objects |> SELECT id, ROW_NUMBER() OVER (PARTITION BY objects.payload.`bucket`, objects.payload.`bucket` ORDER BY objects.payload.`bucket`, id) AS pos, RANK() OVER (PARTITION BY objects.payload.`bucket`, objects.payload.`bucket` ORDER BY objects.payload.`bucket`, id) AS ranking |> ORDER BY id",
      "WITH objects AS (SELECT id, CASE WHEN id = 3 THEN @none WHEN id = 5 THEN @empty WHEN id = 1 THEN @b ELSE @a END AS payload, CASE WHEN id = 2 OR id = 3 THEN @oa ELSE @ob END AS other FROM records WHERE id > 0) SELECT id, other AS payload, ROW_NUMBER() OVER (PARTITION BY payload.bucket ORDER BY id) AS pos FROM objects ORDER BY id",
      "WITH objects AS (SELECT id, CASE WHEN id = 3 THEN @none WHEN id = 5 THEN @empty WHEN id = 1 THEN @b ELSE @a END AS payload, CASE WHEN id = 2 OR id = 3 THEN @oa ELSE @ob END AS other FROM records WHERE id > 0) FROM objects AS original |> SET payload = other |> SELECT id, ROW_NUMBER() OVER (PARTITION BY original.payload.bucket ORDER BY id) AS before, ROW_NUMBER() OVER (PARTITION BY payload.bucket ORDER BY id) AS `current` |> ORDER BY id",
      "WITH objects AS (SELECT id, CASE WHEN id = 3 THEN @none WHEN id = 5 THEN @empty WHEN id = 1 THEN @b ELSE @a END AS payload, CASE WHEN id = 2 OR id = 3 THEN @oa ELSE @ob END AS other FROM records WHERE id > 0) SELECT id, ROW_NUMBER() OVER (PARTITION BY payload.bucket ORDER BY id) AS pos FROM objects ORDER BY id",
      "WITH objects AS (SELECT id, CASE WHEN id = 3 THEN @none WHEN id = 5 THEN @empty WHEN id = 1 THEN @b ELSE @a END AS payload, CASE WHEN id = 2 OR id = 3 THEN @oa ELSE @ob END AS other FROM records WHERE id > 0) FROM objects |> SELECT id, payload.bucket AS bucket |> SELECT id, ROW_NUMBER() OVER (PARTITION BY bucket ORDER BY id) AS pos |> ORDER BY id",
    ] {
    let script = parse_query_script(text, query_limits()).unwrap()
    assert_true(query_binding_count(script_query(script)) > 0)
  }
}

///|
test "WITH current Relation public callers concat-expression-reuse" {
  for
    text in [
      "WITH pieces AS (SELECT id, CASE WHEN amount = 2 THEN 'z' ELSE 'a' END AS x, CASE WHEN amount IS NULL THEN CAST(NULL AS STRING) WHEN amount = 2 THEN 'a' ELSE 'z' END AS y FROM records WHERE id > 0) SELECT x || y AS value, COUNT(*) AS n FROM pieces GROUP BY CONCAT(x,y) ORDER BY value NULLS LAST",
      "WITH pieces AS (SELECT id, CASE WHEN amount = 2 THEN 'z' ELSE 'a' END AS x, CASE WHEN amount IS NULL THEN CAST(NULL AS STRING) WHEN amount = 2 THEN 'a' ELSE 'z' END AS y FROM records WHERE id > 0) SELECT CONCAT(x,y) AS value, COUNT(*) AS n FROM pieces GROUP BY x || y ORDER BY value NULLS LAST",
      "WITH pieces AS (SELECT id, CASE WHEN amount = 2 THEN 'z' ELSE 'a' END AS x, CASE WHEN amount IS NULL THEN CAST(NULL AS STRING) WHEN amount = 2 THEN 'a' ELSE 'z' END AS y FROM records WHERE id > 0) SELECT `concat`((pieces.x),y) AS value, COUNT(*) AS n FROM pieces GROUP BY (x) || (pieces.y) ORDER BY value NULLS LAST",
      "WITH pieces AS (SELECT id, CASE WHEN amount = 2 THEN 'z' ELSE 'a' END AS x, CASE WHEN amount IS NULL THEN CAST(NULL AS STRING) WHEN amount = 2 THEN 'a' ELSE 'z' END AS y FROM records WHERE id > 0) SELECT CONCAT(x,y) AS value, COUNT(*) AS n FROM pieces GROUP BY x || y ORDER BY value NULLS LAST LIMIT 1 OFFSET 1",
      "WITH pieces AS (SELECT id, CASE WHEN amount = 2 THEN 'z' ELSE 'a' END AS x, CASE WHEN amount IS NULL THEN CAST(NULL AS STRING) WHEN amount = 2 THEN 'a' ELSE 'z' END AS y FROM records WHERE id > 0) SELECT x || y AS value, COUNT(*) AS n FROM pieces GROUP BY CONCAT(x,y) ORDER BY value NULLS LAST",
      "WITH pieces AS (SELECT id, CASE WHEN amount = 2 THEN 'z' ELSE 'a' END AS x, CASE WHEN amount IS NULL THEN CAST(NULL AS STRING) WHEN amount = 2 THEN 'a' ELSE 'z' END AS y FROM records WHERE id > 0) SELECT DISTINCT CONCAT(x,y) AS value FROM pieces ORDER BY x || y NULLS LAST",
      "WITH pieces AS (SELECT id, CASE WHEN amount = 2 THEN 'z' ELSE 'a' END AS x, CASE WHEN amount IS NULL THEN CAST(NULL AS STRING) WHEN amount = 2 THEN 'a' ELSE 'z' END AS y FROM records WHERE id > 0) SELECT DISTINCT x || y AS value FROM pieces ORDER BY CONCAT(x,y) NULLS LAST",
      "WITH pieces AS (SELECT id, CASE WHEN amount = 2 THEN 'z' ELSE 'a' END AS x, CASE WHEN amount IS NULL THEN CAST(NULL AS STRING) WHEN amount = 2 THEN 'a' ELSE 'z' END AS y FROM records WHERE id > 0) FROM pieces |> SELECT DISTINCT CONCAT(x,y) AS value |> ORDER BY x || y NULLS LAST",
      "WITH pieces AS (SELECT id, CASE WHEN amount = 2 THEN 'z' ELSE 'a' END AS x, CASE WHEN amount IS NULL THEN CAST(NULL AS STRING) WHEN amount = 2 THEN 'a' ELSE 'z' END AS y FROM records WHERE id > 0) FROM pieces |> SELECT DISTINCT x || y AS value |> ORDER BY `concat`(pieces.x,y) NULLS LAST",
      "WITH pieces AS (SELECT id, CASE WHEN amount = 2 THEN 'z' ELSE 'a' END AS x, CASE WHEN amount IS NULL THEN CAST(NULL AS STRING) WHEN amount = 2 THEN 'a' ELSE 'z' END AS y FROM records WHERE id > 0) SELECT DISTINCT CONCAT(x,y) AS value FROM pieces ORDER BY x || y NULLS LAST",
      "WITH pieces AS (SELECT id, CASE WHEN amount = 2 THEN 'z' ELSE 'a' END AS x, CASE WHEN amount IS NULL THEN CAST(NULL AS STRING) WHEN amount = 2 THEN 'a' ELSE 'z' END AS y FROM records WHERE id > 0) SELECT id, CONCAT(x,y) AS original, y AS x FROM pieces ORDER BY x || y NULLS LAST, id",
      "WITH pieces AS (SELECT id, CASE WHEN amount = 2 THEN 'z' ELSE 'a' END AS x, CASE WHEN amount IS NULL THEN CAST(NULL AS STRING) WHEN amount = 2 THEN 'a' ELSE 'z' END AS y FROM records WHERE id > 0) SELECT id, CONCAT(x,y) AS original, y AS x FROM pieces ORDER BY pieces.x || y NULLS LAST, id",
    ] {
    let script = parse_query_script(text, query_limits()).unwrap()
    assert_true(query_binding_count(script_query(script)) > 0)
  }
}

///|
test "WITH current Relation public callers distinct-order" {
  for
    text in [
      "WITH objects AS (SELECT id, amount AS score, CASE WHEN id = 2 THEN @a WHEN id = 1 OR id = 4 THEN @b WHEN id = 5 THEN @d ELSE @c END AS payload FROM records WHERE id > 0) SELECT DISTINCT payload.score AS score FROM objects ORDER BY (payload).score NULLS LAST",
      "WITH objects AS (SELECT id, amount AS score, CASE WHEN id = 2 THEN @a WHEN id = 1 OR id = 4 THEN @b WHEN id = 5 THEN @d ELSE @c END AS payload FROM records WHERE id > 0) SELECT DISTINCT (payload).score AS score FROM objects ORDER BY objects.payload.score NULLS LAST",
      "WITH objects AS (SELECT id, amount AS score, CASE WHEN id = 2 THEN @a WHEN id = 1 OR id = 4 THEN @b WHEN id = 5 THEN @d ELSE @c END AS payload FROM records WHERE id > 0) SELECT DISTINCT ((payload)).`SCORE` AS score FROM objects ORDER BY payload.score NULLS LAST",
      "WITH objects AS (SELECT id, amount AS score, CASE WHEN id = 2 THEN @a WHEN id = 1 OR id = 4 THEN @b WHEN id = 5 THEN @d ELSE @c END AS payload FROM records WHERE id > 0) FROM objects AS active |> SELECT DISTINCT active.payload.score AS score |> ORDER BY (payload).score NULLS LAST",
      "WITH objects AS (SELECT id, amount AS score, CASE WHEN id = 2 THEN @a WHEN id = 1 OR id = 4 THEN @b WHEN id = 5 THEN @d ELSE @c END AS payload FROM records WHERE id > 0) SELECT DISTINCT payload.score + 1 AS score FROM objects ORDER BY (payload).score + 1 NULLS LAST",
      "WITH objects AS (SELECT id, amount AS score, CASE WHEN id = 2 THEN @a WHEN id = 1 OR id = 4 THEN @b WHEN id = 5 THEN @d ELSE @c END AS payload FROM records WHERE id > 0) SELECT DISTINCT (payload).score AS score FROM objects ORDER BY objects.payload.score NULLS LAST LIMIT 2 OFFSET 1",
      "WITH objects AS (SELECT id, amount AS score, CASE WHEN id = 2 THEN @a WHEN id = 1 OR id = 4 THEN @b WHEN id = 5 THEN @d ELSE @c END AS payload FROM records WHERE id > 0) SELECT DISTINCT payload.score AS score FROM objects ORDER BY (payload).score NULLS LAST",
      "WITH objects AS (SELECT id, amount AS score, CASE WHEN id = 2 THEN @a WHEN id = 1 OR id = 4 THEN @b WHEN id = 5 THEN @d ELSE @c END AS payload FROM records WHERE id > 0) SELECT payload.score AS score FROM objects ORDER BY (payload).score NULLS LAST",
    ] {
    let script = parse_query_script(text, query_limits()).unwrap()
    assert_true(query_binding_count(script_query(script)) > 0)
  }
}

///|
test "WITH current Relation public callers group-order-range-alias" {
  for
    text in [
      "WITH objects AS (SELECT amount AS score FROM records WHERE id > 0) SELECT score AS bucket, CASE WHEN score IS NULL THEN @nil WHEN score = 10 THEN @low ELSE @high END AS payload, COUNT(*) AS n FROM objects AS payload GROUP BY score ORDER BY payload.score NULLS LAST",
      "WITH objects AS (SELECT amount AS score FROM records WHERE id > 0) SELECT score AS bucket, CASE WHEN score IS NULL THEN @nil WHEN score = 10 THEN @low ELSE @high END AS payload, COUNT(*) AS n FROM objects AS payload GROUP BY score ORDER BY (payload).score NULLS LAST",
      "WITH objects AS (SELECT amount AS score FROM records WHERE id > 0) SELECT score AS bucket, CASE WHEN score IS NULL THEN @nil WHEN score = 10 THEN @low ELSE @high END AS payload, COUNT(*) AS n FROM objects AS payload GROUP BY score ORDER BY `PAYLOAD`.`score` NULLS LAST",
      "WITH objects AS (SELECT amount AS score FROM records WHERE id > 0) SELECT score AS bucket, CASE WHEN score IS NULL THEN @nil WHEN score = 10 THEN @low ELSE @high END AS payload, COUNT(*) AS n FROM objects AS original GROUP BY score ORDER BY original.score NULLS LAST",
      "WITH objects AS (SELECT amount AS score FROM records WHERE id > 0) SELECT score AS bucket, CASE WHEN score IS NULL THEN @nil WHEN score = 10 THEN @low ELSE @high END AS payload, COUNT(*) AS n FROM objects AS payload GROUP BY score ORDER BY payload.score NULLS LAST",
    ] {
    let script = parse_query_script(text, query_limits()).unwrap()
    assert_true(query_binding_count(script_query(script)) > 0)
  }
}

///|
test "WITH current Relation public callers group-property-receiver" {
  for
    text in [
      "WITH objects AS (SELECT amount AS score, CASE WHEN id = 1 THEN @a WHEN id = 2 THEN @b ELSE @c END AS payload FROM records WHERE id > 0) SELECT payload.score AS input_score, (payload).score AS object_score, COUNT(*) AS n FROM objects AS payload GROUP BY ALL ORDER BY input_score, object_score",
      "WITH objects AS (SELECT amount AS score, CASE WHEN id = 1 THEN @a WHEN id = 2 THEN @b ELSE @c END AS payload FROM records WHERE id > 0) SELECT payload.score AS input_score, (payload).score AS object_score, COUNT(*) AS n FROM objects AS payload GROUP BY payload.score, (payload).score ORDER BY input_score, object_score",
      "WITH objects AS (SELECT amount AS score, CASE WHEN id = 1 THEN @a WHEN id = 2 THEN @b ELSE @c END AS payload FROM records WHERE id > 0) SELECT payload.score AS input_score, ((payload)).`SCORE` AS object_score, COUNT(*) AS n FROM objects AS payload GROUP BY ALL ORDER BY input_score, object_score",
      "WITH objects AS (SELECT amount AS score, CASE WHEN id = 1 THEN @a WHEN id = 2 THEN @b ELSE @c END AS payload FROM records WHERE id > 0) SELECT payload.score + 1 AS input_score, (payload).score + 1 AS object_score, COUNT(*) AS n FROM objects AS payload GROUP BY ALL ORDER BY input_score, object_score",
      "WITH objects AS (SELECT amount AS score, CASE WHEN id = 1 THEN @a WHEN id = 2 THEN @b ELSE @c END AS payload FROM records WHERE id > 0) SELECT payload.score AS input_score, (payload).score AS object_score, COUNT(*) AS n FROM objects AS payload GROUP BY ALL HAVING object_score > 20 ORDER BY input_score, object_score",
      "WITH objects AS (SELECT amount AS score, CASE WHEN id = 1 THEN @a WHEN id = 2 THEN @b ELSE @c END AS payload FROM records WHERE id > 0) SELECT payload.score AS input_score, (payload).score AS object_score, COUNT(*) AS n FROM objects AS payload GROUP BY ALL ORDER BY input_score, object_score",
    ] {
    let script = parse_query_script(text, query_limits()).unwrap()
    assert_true(query_binding_count(script_query(script)) > 0)
  }
}

///|
test "WITH current Relation public callers implicit-property" {
  for
    text in [
      "WITH objects AS (SELECT 2 AS id, @p2 AS payload, @o2 AS other UNION ALL SELECT 1 AS id, @p1 AS payload, @o1 AS other UNION ALL SELECT 3 AS id, @p3 AS payload, @o3 AS other UNION ALL SELECT 4 AS id, @p4 AS payload, @o4 AS other) SELECT payload.score, id FROM objects ORDER BY score NULLS LAST, id",
      "WITH objects AS (SELECT 2 AS id, @p2 AS payload, @o2 AS other UNION ALL SELECT 1 AS id, @p1 AS payload, @o1 AS other UNION ALL SELECT 3 AS id, @p3 AS payload, @o3 AS other UNION ALL SELECT 4 AS id, @p4 AS payload, @o4 AS other) SELECT payload.SCORE AS score, id FROM objects ORDER BY score NULLS LAST, id",
      "WITH objects AS (SELECT 2 AS id, @p2 AS payload, @o2 AS other UNION ALL SELECT 1 AS id, @p1 AS payload, @o1 AS other UNION ALL SELECT 3 AS id, @p3 AS payload, @o3 AS other UNION ALL SELECT 4 AS id, @p4 AS payload, @o4 AS other) SELECT `objects`.`payload`.`SCORE` AS score, id FROM objects ORDER BY score NULLS LAST, id",
      "WITH objects AS (SELECT 2 AS id, @p2 AS payload, @o2 AS other UNION ALL SELECT 1 AS id, @p1 AS payload, @o1 AS other UNION ALL SELECT 3 AS id, @p3 AS payload, @o3 AS other UNION ALL SELECT 4 AS id, @p4 AS payload, @o4 AS other) SELECT COALESCE(payload, payload).SCORE AS score, id FROM objects ORDER BY score NULLS LAST, id",
      "WITH objects AS (SELECT 2 AS id, @p2 AS payload, @o2 AS other UNION ALL SELECT 1 AS id, @p1 AS payload, @o1 AS other UNION ALL SELECT 3 AS id, @p3 AS payload, @o3 AS other UNION ALL SELECT 4 AS id, @p4 AS payload, @o4 AS other) FROM objects |> SELECT payload.score, id |> ORDER BY score NULLS LAST, id",
      "WITH objects AS (SELECT 2 AS id, @p2 AS payload, @o2 AS other UNION ALL SELECT 1 AS id, @p1 AS payload, @o1 AS other UNION ALL SELECT 3 AS id, @p3 AS payload, @o3 AS other UNION ALL SELECT 4 AS id, @p4 AS payload, @o4 AS other) SELECT `objects`.`payload`.`score`, id FROM objects ORDER BY score NULLS LAST, id",
      "WITH objects AS (SELECT 2 AS id, @p2 AS payload, @o2 AS other UNION ALL SELECT 1 AS id, @p1 AS payload, @o1 AS other UNION ALL SELECT 3 AS id, @p3 AS payload, @o3 AS other UNION ALL SELECT 4 AS id, @p4 AS payload, @o4 AS other) SELECT payload.inner.risk, id FROM objects ORDER BY id",
      "WITH objects AS (SELECT 2 AS id, @p2 AS payload, @o2 AS other UNION ALL SELECT 1 AS id, @p1 AS payload, @o1 AS other UNION ALL SELECT 3 AS id, @p3 AS payload, @o3 AS other UNION ALL SELECT 4 AS id, @p4 AS payload, @o4 AS other) SELECT payload.INNER.RISK AS risk, id FROM objects ORDER BY id",
      "WITH objects AS (SELECT 2 AS id, @p2 AS payload, @o2 AS other UNION ALL SELECT 1 AS id, @p1 AS payload, @o1 AS other UNION ALL SELECT 3 AS id, @p3 AS payload, @o3 AS other UNION ALL SELECT 4 AS id, @p4 AS payload, @o4 AS other) SELECT payload.score, id FROM objects WHERE FALSE ORDER BY score NULLS LAST, id",
      "WITH objects AS (SELECT 2 AS id, @p2 AS payload, @o2 AS other UNION ALL SELECT 1 AS id, @p1 AS payload, @o1 AS other UNION ALL SELECT 3 AS id, @p3 AS payload, @o3 AS other UNION ALL SELECT 4 AS id, @p4 AS payload, @o4 AS other) SELECT payload.score, other AS payload, id FROM objects ORDER BY score NULLS LAST, id",
      "WITH objects AS (SELECT 2 AS id, @p2 AS payload, @o2 AS other UNION ALL SELECT 1 AS id, @p1 AS payload, @o1 AS other UNION ALL SELECT 3 AS id, @p3 AS payload, @o3 AS other UNION ALL SELECT 4 AS id, @p4 AS payload, @o4 AS other) FROM objects AS before |> SET payload = other |> SELECT before.payload.score AS original, payload.score, id |> ORDER BY id",
      "WITH objects AS (SELECT 2 AS id, @p2 AS payload, @o2 AS other UNION ALL SELECT 1 AS id, @p1 AS payload, @o1 AS other UNION ALL SELECT 3 AS id, @p3 AS payload, @o3 AS other UNION ALL SELECT 4 AS id, @p4 AS payload, @o4 AS other) SELECT `ID`, payload.score FROM objects ORDER BY `ID`",
    ] {
    let script = parse_query_script(text, query_limits()).unwrap()
    assert_true(query_binding_count(script_query(script)) > 0)
  }
}

///|
test "WITH current Relation public callers membership-expression-reuse" {
  for
    text in [
      "WITH pieces AS (SELECT id, amount = 2 AS needle, amount = 1 AS other FROM records WHERE id > 0) SELECT id, needle IN (TRUE) AS original, other AS needle FROM pieces ORDER BY needle IN UNNEST([TRUE]) NULLS LAST, id",
      "WITH pieces AS (SELECT id, amount = 2 AS needle, amount = 1 AS other FROM records WHERE id > 0) SELECT id, needle IN (TRUE) AS original, other AS needle FROM pieces ORDER BY pieces.needle IN UNNEST([TRUE]) NULLS LAST, id",
    ] {
    let script = parse_query_script(text, query_limits()).unwrap()
    assert_true(query_binding_count(script_query(script)) > 0)
  }
}

///|
test "WITH current Relation public callers negated-predicate-reuse" {
  for
    text in [
      "WITH pieces AS (SELECT id, amount, IF(amount = 1, NULL, 1) AS other FROM records WHERE id > 0) SELECT id, amount IS NOT NULL AS original, other AS amount FROM pieces ORDER BY NOT (amount IS NULL), id",
      "WITH pieces AS (SELECT id, amount, IF(amount = 1, NULL, 1) AS other FROM records WHERE id > 0) SELECT id, amount IS NOT NULL AS original, other AS amount FROM pieces ORDER BY NOT (pieces.amount IS NULL), id",
    ] {
    let script = parse_query_script(text, query_limits()).unwrap()
    assert_true(query_binding_count(script_query(script)) > 0)
  }
}

///|
test "WITH current Relation public callers scalar-alias-group" {
  for
    text in [
      "WITH texts AS (SELECT id, CASE WHEN id = 1 THEN @a WHEN id = 2 THEN @b ELSE @c END AS name FROM records WHERE id > 0) SELECT CHAR_LENGTH(name) AS width, COUNT(*) + CHARACTER_LENGTH(texts.name) AS total FROM texts GROUP BY CHAR_LENGTH(name) ORDER BY width NULLS LAST",
      "WITH texts AS (SELECT id, CASE WHEN id = 1 THEN @a WHEN id = 2 THEN @b ELSE @c END AS name FROM records WHERE id > 0) SELECT `CHARACTER_LENGTH`(name) AS width, COUNT(*) + `CHAR_LENGTH`(texts.name) AS total FROM texts GROUP BY `CHAR_LENGTH`(name) ORDER BY width NULLS LAST",
      "WITH texts AS (SELECT id, CASE WHEN id = 1 THEN @a WHEN id = 2 THEN @b ELSE @c END AS name FROM records WHERE id > 0) FROM texts |> AGGREGATE COUNT(*) AS n GROUP BY CHAR_LENGTH(name) AS width |> SELECT width, n + width AS total |> ORDER BY width NULLS LAST |> RESULT answer",
      "WITH texts AS (SELECT id, CASE WHEN id = 1 THEN @a WHEN id = 2 THEN @b ELSE @c END AS name FROM records WHERE id > 0) SELECT CHAR_LENGTH(name) AS width, COUNT(*) + CHARACTER_LENGTH(texts.name) AS total FROM texts GROUP BY CHAR_LENGTH(name) ORDER BY width NULLS LAST",
    ] {
    let script = parse_query_script(text, query_limits()).unwrap()
    assert_true(query_binding_count(script_query(script)) > 0)
  }
}

///|
test "WITH current Relation public callers qualify" {
  for
    text in [
      "WITH objects AS (SELECT 2 AS id, @a AS payload UNION ALL SELECT 1 AS id, @b AS payload UNION ALL SELECT 3 AS id, @c AS payload) SELECT 1 / (id - 1) AS objects, ROW_NUMBER() OVER (ORDER BY id) AS n FROM objects QUALIFY objects.id > 1 AND objects.payload.score > 5 ORDER BY n",
    ] {
    let script = parse_query_script(text, query_limits()).unwrap()
    assert_true(query_binding_count(script_query(script)) > 0)
  }
}

///|
test "WITH current Relation public callers pipe-pivot" {
  for
    text in [
      "WITH counts AS ((SELECT CAST(NULL AS FLOAT64) AS n,'A' AS axis UNION ALL SELECT CAST(NULL AS FLOAT64),'A' UNION ALL SELECT 1,'A') |> PIVOT(COUNT(*) FOR axis IN('A')) |> ORDER BY n NULLS LAST) FROM counts |> SELECT n, A |> ORDER BY n NULLS LAST",
    ] {
    let script = parse_query_script(text, query_limits()).unwrap()
    assert_true(query_binding_count(script_query(script)) > 0)
  }
}

///|
test "WITH current Relation public callers pipe-distinct" {
  for
    text in [
      "WITH copied AS (FROM records |> SELECT amount |> UNION ALL (FROM records |> SELECT amount) |> DISTINCT) FROM copied |> ORDER BY amount NULLS LAST",
    ] {
    let script = parse_query_script(text, query_limits()).unwrap()
    assert_true(query_binding_count(script_query(script)) > 0)
  }
}

///|
test "WITH current Relation public callers order-window" {
  for
    text in [
      "WITH combined AS (SELECT * FROM UNNEST(@items) e UNION ALL SELECT * FROM UNNEST(@items) e ORDER BY ROW_NUMBER() OVER (ORDER BY id) DESC) FROM combined |> SELECT * |> RESULT answer",
    ] {
    let script = parse_query_script(text, query_limits()).unwrap()
    assert_true(query_binding_count(script_query(script)) > 0)
  }
}

///|
test "WITH current Relation public callers aggregate-property-order" {
  for
    text in [
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY payload.score NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY (payload).score NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects AS before |> AGGREGATE STRING_AGG(name, '|' ORDER BY ((before.payload)).`score` NULLS LAST, id) AS names",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) , colliding AS (SELECT id, name, payload, other, other.score AS score FROM objects) SELECT STRING_AGG(name, '|' ORDER BY (payload).score NULLS LAST, id) AS names FROM colliding AS payload",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY (payload).score NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects AS before |> AGGREGATE STRING_AGG(name, '|' ORDER BY `before`.`payload`.`score` NULLS LAST, id) AS names",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY payload.score NULLS LAST, id) AS names, STRING_AGG(name, '|' ORDER BY payload.score DESC NULLS FIRST, id) AS reverse FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects AS before |> SET payload = other |> AGGREGATE STRING_AGG(name, '|' ORDER BY payload.score, id) AS `current`, STRING_AGG(name, '|' ORDER BY before.payload.score NULLS LAST, id) AS previous",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT COUNT(*) AS payload, STRING_AGG(name, '|' ORDER BY payload.score NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY payload.score NULLS LAST, id) AS names FROM objects WHERE name != 'c' AND id <= 2",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY payload.score NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name ORDER BY payload.score NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects |> AGGREGATE STRING_AGG(name ORDER BY payload.score NULLS LAST, id) AS names",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '' ORDER BY payload.score NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name WHERE id <= 2 ORDER BY payload.score NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name ORDER BY payload.score NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name ORDER BY payload.score NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '' /* separator */ \"|\" '''''' ORDER BY payload.score NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects |> AGGREGATE STRING_AGG(name, r'\\n' '\\r' ORDER BY payload.score NULLS LAST, id) AS names",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, 'e' '\\u0301' WHERE id > 0 ORDER BY payload.score NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects |> ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4 |> AGGREGATE ARRAY_AGG(id IGNORE NULLS ORDER BY payload.score NULLS LAST, id) AS ids",
      "WITH labels AS (SELECT id, CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY @key DESC NULLS LAST, id) AS names FROM labels",
      "WITH labels AS (SELECT id, CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name FROM records WHERE id > 0) FROM labels |> AGGREGATE STRING_AGG(name, '|' ORDER BY (@`KEY`) DESC NULLS LAST, id) AS names",
      "WITH labels AS (SELECT id, CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY @key DESC NULLS LAST, id) AS names FROM labels",
      "WITH labels AS (SELECT id, CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY @NAME DESC NULLS LAST, id) AS names FROM labels",
      "WITH labels AS (SELECT id, CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name FROM records WHERE id > 0) FROM labels |> AGGREGATE STRING_AGG(name, '|' ORDER BY ((@`CFG`)).`rank` DESC NULLS LAST, id) AS names",
      "WITH labels AS (SELECT id, CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name FROM records WHERE id > 0) FROM labels |> AGGREGATE STRING_AGG(name, '|' ORDER BY ((@`CFG`)).`rank` DESC NULLS LAST, id) AS names",
      "WITH labels AS (SELECT id, CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name FROM records WHERE id > 0) FROM labels |> AGGREGATE STRING_AGG(name, '|' ORDER BY ((@`CFG`)).`rank` DESC NULLS LAST, id) AS names",
      "WITH labels AS (SELECT id, CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' WHERE id <= 2 ORDER BY @key DESC NULLS LAST, id) AS names FROM labels",
      "WITH labels AS (SELECT id, CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY @key DESC NULLS LAST, id) AS names FROM labels",
      "WITH labels AS (SELECT id, CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name FROM records WHERE id > 0) SELECT STRING_AGG(DISTINCT @label, '|' ORDER BY @LABEL) AS names FROM labels",
      "WITH labels AS (SELECT id, CASE WHEN id = 1 THEN 'z' WHEN id = 2 THEN 'a' WHEN id = 3 THEN 'm' ELSE NULL END AS name FROM records WHERE id > 0) FROM labels |> AGGREGATE STRING_AGG(DISTINCT @`LABEL`, '|' ORDER BY (@label)) AS names",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, (('' /* separator */ '|')) ORDER BY payload.score NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects |> AGGREGATE STRING_AGG(name, ((r'\\n' '\\r')) ORDER BY payload.score NULLS LAST, id) AS names",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, ('|') ORDER BY payload.score NULLS LAST, id) AS names FROM objects",
    ] {
    let script = parse_query_script(text, query_limits()).unwrap()
    assert_true(query_binding_count(script_query(script)) > 0)
  }
}

///|
test "WITH current Relation public callers aggregate-conditional-order" {
  for
    text in [
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY COALESCE(payload.score, 0) NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects AS t |> AGGREGATE STRING_AGG(name, '|' ORDER BY `IFNULL`((t.payload).score, 0) NULLS LAST, id) AS names",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY CASE WHEN id = 1 THEN 0 ELSE payload.score END NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY IF(payload.score IS NULL, other.score, -payload.score) NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY COALESCE(payload, other).score NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY IFNULL(payload.score, 0), id) AS names, STRING_AGG(name, '|' ORDER BY IFNULL(payload.score, 0) DESC, id) AS reverse FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects AS before |> SET payload = other |> AGGREGATE STRING_AGG(name, '|' ORDER BY IFNULL(payload.score, 0), id) AS `current`, STRING_AGG(name, '|' ORDER BY IFNULL(before.payload.score, 0), id) AS previous",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' WHERE id <= 2 ORDER BY COALESCE(payload.score, 0) NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(IF(id / (id - id) = 0, name, name), '|' WHERE FALSE ORDER BY COALESCE(payload.score, 0) NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY COALESCE(payload.score, 0) NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY COALESCE(payload.score, @fallback) NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(DISTINCT IFNULL(name, 'missing'), '|' ORDER BY IFNULL(name, 'missing')) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY payload.score IS NULL NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects AS t |> AGGREGATE STRING_AGG(name, '|' ORDER BY ((t.payload)).`SCORE` > 15 NULLS LAST, id) AS names",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY NOT (payload.score > 15) NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY (payload.score > 15) AND id != 3 NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY (payload.score > 15) OR id = 3 NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY (payload.score > 15) IS UNKNOWN NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY payload.score IS NULL NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(IF(id / (id - id) = 0, name, name), '|' WHERE FALSE ORDER BY payload.score IS NULL NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY payload.score IS NULL, id) AS names, STRING_AGG(name, '|' ORDER BY payload.score IS NULL DESC, id) AS reverse FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects AS before |> SET payload = other |> AGGREGATE STRING_AGG(name, '|' ORDER BY payload.score > 15 NULLS LAST, id) AS `current`, STRING_AGG(name, '|' ORDER BY before.payload.score > 15 NULLS LAST, id) AS previous",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY id = @selected NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT COUNT(*) AS payload, STRING_AGG(name, '|' ORDER BY payload.score IS NULL, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects |> ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4 |> AGGREGATE ARRAY_AGG(id IGNORE NULLS ORDER BY payload.score IS NULL, id) AS ids",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY payload.score IN (20, NULL) NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects AS t |> AGGREGATE STRING_AGG(name, '|' ORDER BY ((t.payload)).`SCORE` IN (20, 20) NULLS LAST, id) AS names",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY payload.score NOT IN (20) NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY payload.score IN UNNEST(ARRAY[20, NULL]) NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY payload.score NOT IN UNNEST([]) NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY payload.score BETWEEN 5 AND 15 NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY payload.score NOT BETWEEN 5 AND 15 NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY payload.score IS NOT DISTINCT FROM 20 NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY payload.score IS DISTINCT FROM NULL NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects AS before |> SET payload = other |> AGGREGATE STRING_AGG(name, '|' ORDER BY payload.score IN (25, 30) NULLS LAST, id) AS `current`, STRING_AGG(name, '|' ORDER BY before.payload.score IN (25, 30) NULLS LAST, id) AS previous",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY payload.score IN (@wanted, NULL) NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(IF(id / (id - id) = 0, name, name), '|' WHERE FALSE ORDER BY payload.score BETWEEN 5 AND 15 NULLS LAST, id) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects |> ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4 |> AGGREGATE ARRAY_AGG(id IGNORE NULLS ORDER BY payload.score IN (20) NULLS LAST, id) AS ids",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(DISTINCT IFNULL(name, 'missing'), '|' ORDER BY IFNULL(objects.name, 'missing')) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects AS o |> AGGREGATE STRING_AGG(DISTINCT IFNULL(name, 'missing'), '|' ORDER BY IFNULL(`o`.`NAME`, 'missing')) AS names",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(DISTINCT IFNULL(name, 'missing'), '|' ORDER BY IFNULL(objects.name, 'missing')) AS names FROM objects",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY IFNULL(name, 'missing')) AS names, STRING_AGG(name, '|' ORDER BY IFNULL(o.name, 'missing') DESC) AS reverse FROM objects AS o",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(DISTINCT CASE WHEN id = 3 THEN 'third' ELSE IFNULL(name, 'missing') END, '|' ORDER BY CASE WHEN o.id = 3 THEN 'third' ELSE IFNULL(o.name, 'missing') END) AS names FROM objects AS o",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects AS o |> ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4 |> AGGREGATE ARRAY_AGG(DISTINCT IFNULL((payload).score, 0) IGNORE NULLS ORDER BY IFNULL((o.payload).`SCORE`, 0) DESC) AS ids",
    ] {
    let script = parse_query_script(text, query_limits()).unwrap()
    assert_true(query_binding_count(script_query(script)) > 0)
  }
}

///|
test "WITH current Relation public callers aggregate-member-call-reuse" {
  for
    text in [
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT COUNT(payload.score) AS n FROM objects HAVING COUNT((objects.payload).`SCORE`) > 0",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT COUNT(payload.score WHERE payload.score > 10) AS n FROM objects HAVING COUNT((payload).score WHERE (objects.payload).`SCORE` > 10) > 0",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT COUNT(payload.score) AS n FROM objects HAVING COUNT((payload).score) = 0",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT COUNT(payload.score) AS n, @p3 AS payload FROM objects HAVING COUNT((payload).score) > 0",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT COUNT(payload.score) AS n, @p3 AS payload FROM objects HAVING COUNT((objects.payload).score) > 0",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) , colliding AS (SELECT id, payload, other.score AS score FROM objects) SELECT COUNT((payload).score) AS n FROM colliding AS payload HAVING COUNT(payload.score) > 3",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT COUNT(payload.score) AS n FROM objects HAVING COUNT(DISTINCT (payload).score) = 2",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT COUNT(payload.score WHERE payload.score > 10) AS n FROM objects HAVING COUNT((payload).score WHERE payload.score > 20) > 0",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY payload.score NULLS LAST, id) AS names FROM objects HAVING STRING_AGG(name, '|' ORDER BY (objects.payload).`SCORE` NULLS LAST, id) = 'b|b|a|c'",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN 'a' WHEN id = 2 THEN 'b' WHEN id = 3 THEN 'c' ELSE NULL END AS name, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) SELECT STRING_AGG(name, '|' ORDER BY payload.score NULLS LAST, id) AS names FROM objects HAVING STRING_AGG(name, '|' ORDER BY (objects.payload).score DESC NULLS FIRST, id) = 'c|a|b|b'",
    ] {
    let script = parse_query_script(text, query_limits()).unwrap()
    assert_true(query_binding_count(script_query(script)) > 0)
  }
}

///|
test "WITH current Relation public callers distinct-signed-order" {
  for
    text in [
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects AS o |> ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4 |> AGGREGATE ARRAY_AGG(DISTINCT -payload.score IGNORE NULLS ORDER BY -o.payload.score) AS items",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects AS o |> ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4 |> AGGREGATE ARRAY_AGG(DISTINCT -(payload).score IGNORE NULLS ORDER BY -o.payload.`SCORE`) AS items",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) , keyed AS (FROM objects AS o |> ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4 ) SELECT ARRAY_AGG(DISTINCT -payload.score IGNORE NULLS ORDER BY -k.payload.score) AS items FROM keyed AS k",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects AS o |> ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4 |> AGGREGATE ARRAY_AGG(DISTINCT -o.payload.score IGNORE NULLS ORDER BY -((payload)).score DESC NULLS LAST) AS items",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects AS o |> ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4 |> AGGREGATE ARRAY_AGG(DISTINCT +payload.score IGNORE NULLS ORDER BY +o.payload.score) AS items",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects AS o |> ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4 |> AGGREGATE ARRAY_AGG(DISTINCT -(-payload.score) IGNORE NULLS ORDER BY -(-o.payload.score)) AS items",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects AS o |> ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4 |> AGGREGATE ARRAY_AGG(DISTINCT -id IGNORE NULLS ORDER BY -o.id DESC) AS items",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects AS o |> ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4 |> AGGREGATE ARRAY_AGG(DISTINCT -payload.score IGNORE NULLS WHERE id = 1 ORDER BY -o.payload.score) AS items",
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0) FROM objects AS o |> ASSERT UNIQUE BY (id) |> ORDER BY id |> LIMIT 4 |> AGGREGATE ARRAY_AGG(DISTINCT -payload.score IGNORE NULLS ORDER BY -o.payload.score) AS items",
    ] {
    let script = parse_query_script(text, query_limits()).unwrap()
    assert_true(query_binding_count(script_query(script)) > 0)
  }
}
