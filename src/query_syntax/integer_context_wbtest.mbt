///|
test "integer context retains original lexemes document and source tree without a second parse" {
  let original = parse_query(
    "WITH t AS (SELECT 9007199254740993 AS v) SELECT MOD(v,2) AS x FROM t",
    integer_context_test_limits(),
  ).unwrap()
  let selected = with_integer_function_context(original, 10000).unwrap()
  assert_true(physical_equal(original.source, selected.source))
  assert_true(
    physical_equal(original.source.document, selected.source.document),
  )
  guard original.bindings[0].query.operations[0] is Select(before, _) &&
    selected.bindings[0].query.operations[0] is Select(after, _) else {
    fail("expected original CTE scalar projections")
  }
  let before = before[0].expression.unwrap()
  let after = after[0].expression.unwrap()
  assert_true(before.nodes[before.root].kind is Number("9007199254740993"))
  guard after.nodes[after.root].kind
    is ContextualIntegerCompanion(child, original_name) else {
    fail("expected the private exact view of the original integer token")
  }
  assert_eq(original_name.unwrap().value, "v")
  assert_true(
    after.nodes[child].kind is ContextualInteger(Some(9007199254740993L)),
  )
  assert_true(
    physical_equal(
      with_integer_function_context(selected, 10000).unwrap(),
      selected,
    ),
  )
  assert_true(
    with_integer_function_context(original, 0)
    is Err({ issue: Limit(Work), .. }),
  )
  assert_true(before.nodes[before.root].kind is Number("9007199254740993"))
}

///|
test "integer context keeps Number spelling and explicit conversion separate" {
  for text in ["5.0", "5e0", "9223372036854775808", "0x8000000000000000"] {
    assert_eq(contextual_integer_literal(text, false), None, msg=text)
  }
  assert_eq(
    contextual_integer_literal("0x8000000000000000", true),
    Some(-9223372036854775807L - 1L),
  )
  assert_eq(
    contextual_integer_literal("9223372036854775807", false),
    Some(9223372036854775807L),
  )
  let original = parse_query(
    "WITH t AS (SELECT 5 AS v) SELECT v FROM t",
    integer_context_test_limits(),
  ).unwrap()
  assert_true(
    physical_equal(
      with_integer_function_context(original, 10000).unwrap(),
      original,
    ),
  )
}

///|
fn integer_context_test_limits() -> QueryLimits {
  let lexical : LexicalLimits = {
    max_source_bytes: 10000,
    max_tokens: 1000,
    max_literal_bytes: 1000,
    max_work: 10000,
  }
  {
    lexical,
    expression: { lexical, max_nodes: 1000, max_depth: 64, max_work: 10000, },
    max_syntax_nodes: 1000,
    max_cte_count: 20,
    max_work: 10000,
  }
}

///|
test "integer context preserves the original ON list and omitted public name provenance" {
  let original = parse_query(
    "WITH t AS (SELECT 9007199254740993 AS v UNION ALL BY NAME ON (v) SELECT 9007199254740995 AS v) SELECT MOD(v,2) AS m FROM t",
    integer_context_test_limits(),
  ).unwrap()
  let selected = with_integer_function_context(original, 10000).unwrap()
  let before = original.bindings[0].query
  let after = selected.bindings[0].query
  assert_true(physical_equal(original.source, selected.source))
  assert_true(physical_equal(before.source.document, after.source.document))
  assert_eq(
    before.sets[0].by_name_columns,
    Some([{ value: "v", quoted: false, }]),
  )
  assert_true(
    physical_equal(
      before.sets[0].by_name_columns,
      after.sets[0].by_name_columns,
    ),
  )
  guard before.operations[0] is Select(projections, _) else {
    fail("original SELECT")
  }
  assert_eq(projections.length(), 1)
  assert_eq(projections[0].name, Some({ value: "v", quoted: false, }))
  assert_eq(integer_context_companion_columns(before), [])
  let companions = integer_context_companion_columns(after)
  assert_eq(companions.length(), 1)
  assert_true(integer_context_is_companion_column(after, companions[0]))
  assert_eq(integer_context_original_column(after, companions[0]), Some("v"))
  assert_false(integer_context_is_companion_column(after, "v"))
  assert_eq(integer_context_original_column(after, "v"), None)
  assert_true(
    physical_equal(
      with_integer_function_context(selected, 10000).unwrap(),
      selected,
    ),
  )
}
