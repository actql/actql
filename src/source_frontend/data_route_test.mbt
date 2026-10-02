///|
test "public AQL source routing uses admitted DATA script and preserves explicit Results" {
  let text = "DATA n = SELECT 2 AS id; FROM n |> RESULT original |> WHERE id > 0 |> RESULT active"
  let context = { ..test_context(), inputs: [], captured_stage: None, }
  let lowered = lower(text, Text, Some(context)).unwrap()
  assert_true(lowered.format is @program.Json)
  assert_true(lowered.document.contains("\"original\""))
  assert_true(lowered.document.contains("\"active\""))
  assert_true(!lowered.document.contains("\"answer\""))
  assert_true(!lowered.document.contains("\"connector\":"))
  assert_true(lower(text, Sql, Some(context)) is Err(WrongQueryForm))
  assert_true(lower(text, Text, None) is Err(MissingQueryContext))
}

///|
test "public source route preserves keyed labels and refuses hidden Graph fields" {
  let context = { ..test_context(), inputs: [], captured_stage: None, }
  let prefix = "DATA n = SELECT 1 AS id, 'Company' AS entity_type; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Person PROPERTIES (id, entity_type))); "
  let lowered = lower(
    prefix +
    "FROM GRAPH g |> MATCH WALK (a:Person) |> SELECT a.id AS id, a.entity_type AS category |> RESULT people",
    Text,
    Some(context),
  ).unwrap()
  assert_true(lowered.document.contains("\"property_graph\":"))
  assert_true(lowered.document.contains("\"label\":\"Person\""))
  assert_true(lowered.document.contains("\"people\""))
  assert_true(lowered.document.contains("\"fields\":[\"id\",\"category\"]"))
  assert_true(!lowered.document.contains("\"eq\":"))
  assert_true(
    lower(
      prefix + "FROM GRAPH g |> MATCH WALK (a) |> SELECT *",
      Text,
      Some(context),
    )
    is Err(QueryLowering(@query.UnsupportedProjection)),
  )
  assert_true(
    lower(
      prefix + "FROM GRAPH missing |> MATCH WALK (a) |> SELECT a.id",
      Text,
      Some(context),
    )
    is Err(QueryLowering(@query.UnknownRelation)),
  )
}

///|
test "public DATA routing has no retired constructor fallback" {
  let context = { ..test_context(), inputs: [], captured_stage: None, }
  for
    text in [
      "DATA same = FROM g |> graphs_equal(with: g);", "DATA g = graph(nodes: n); FROM GRAPH g |> MATCH WALK (a) |> SELECT a.id",
      "DATA g = OP graph {}; FROM GRAPH g |> MATCH WALK (a) |> SELECT a.id",
    ] {
    assert_true(lower(text, Text, Some(context)) is Err(QuerySyntax(_)))
    assert_true(lower(text, Sql, Some(context)) is Err(WrongQueryForm))
  }
}

///|
test "public ordered DATA set refuses the unavailable Relation strategy before admission" {
  let context = { ..test_context(), inputs: [], captured_stage: None, }
  for
    text in [
      "DATA n = SELECT 2 AS id UNION ALL SELECT 1 AS other ORDER BY id + 1, id + 1 DESC LIMIT 1; FROM n |> SELECT id |> RESULT nodes",
      "DATA `n` = SELECT 2 AS id UNION ALL SELECT 1 AS other ORDER BY id; FROM `n` |> SELECT id",
    ] {
    assert_true(
      lower(text, Text, Some(context))
      is Err(QueryLowering(@query.UnsupportedSet)),
      msg=text,
    )
  }
  // Ordinary SQL set queries keep their established Stage strategy; this is
  // an execution-profile refusal, not a change to ORDER BY or set semantics.
  assert_true(
    lower(
      "SELECT 2 AS id UNION ALL SELECT 1 AS other ORDER BY id + 1 LIMIT 1",
      Sql,
      Some(context),
    )
    is Ok(_),
  )
  // Do not classify all ordered DATA sets as invalid: a typed Graph consumer
  // already supplies the existing Carrier segmentation boundary.
  assert_true(
    lower(
      "DATA n = SELECT 2 AS id UNION ALL SELECT 1 AS id ORDER BY id LIMIT 1; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node PROPERTIES (id))); FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.id AS id |> RESULT nodes",
      Text,
      Some(context),
    )
    is Ok(_),
  )
}
