///|
test "unused WITH expression reaches the common pipeline type checker" {
  let parsed = @query.parse_query_script(
    "WITH unused AS (SELECT 1 + 'text' AS invalid) SELECT 1 AS id",
    syntax_limits(),
  ).unwrap()
  let actual = compile_query_script(
    parsed,
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  )
  assert_true(
    actual
    is Err(
      BindingPreparation(
        LocalProgram(
          Pipeline(0, { kind: Operation(Expression(TypeMismatch(_))), .. })
        )
      )
    ),
  )
}

///|
test "unused WITH Source requires its actual Catalog registration" {
  let parsed = @query.parse_query_script(
    "WITH unused AS (SELECT id FROM objects) SELECT 1 AS id",
    syntax_limits(),
  ).unwrap()
  let admitted = source_member_context()
  assert_true(
    compile_query_script(parsed, admitted, construction_limits()) is Ok(_),
  )
  // Keeping the exact schema but removing the Catalog must not fabricate an
  // admitted SourceViewInput. No provider execution is available in this API.
  assert_true(
    compile_query_script(
      parsed,
      { ..admitted, source_catalog: None, },
      construction_limits(),
    )
    is Err(BindingPreparation(LocalProgram(MissingSourceViewRegistrations(0)))),
  )
}

///|
test "unused WITH field resolution still fails before demand selection" {
  let actual = compile_query_script(
    @query.parse_query_script(
      "WITH unused AS (SELECT missing FROM objects) SELECT 1 AS id",
      syntax_limits(),
    ).unwrap(),
    source_member_context(),
    construction_limits(),
  )
  assert_true(actual is Err(Expression({ issue: UnknownReference, .. })))
}

///|
test "unused Graph duplicate key remains a conditional value obligation" {
  // Static checking cannot turn these duplicate rows into unique keys. Their
  // runtime obligation remains with the common Graph owner. Demand elimination
  // and its zero-I/O public acceptance are a separate connection step.
  let actual = compile_query_script(
    @query.parse_query_script(
      "WITH n AS (SELECT 1 AS id UNION ALL SELECT 1 AS id), unused AS (GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node NO PROPERTIES))) SELECT 1 AS answer",
      syntax_limits(),
    ).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  )
  assert_true(actual is Ok(_))
}
