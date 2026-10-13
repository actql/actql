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
test "ordinary compilation drops failed nested diagnostic snapshots" {
  for
    text in [
      "WITH q AS (SELECT x FROM pair WHERE x) SELECT x FROM q", "SELECT x FROM (SELECT x FROM pair WHERE x) AS q",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    let script = @query.parse_query_script(text, syntax_limits()).unwrap()
    let context = pair_context()
    let limits = construction_limits()
    assert_true(
      compile_with_source(query, context, limits)
      is Err(
        BindingPreparationSource(
          LocalProgram(Pipeline(_, { kind: Operation(ExpectedBoolean), .. }))
          | SourceProgram(
            Program(Pipeline(_, { kind: Operation(ExpectedBoolean), .. }))
          ),
          _
        )
      ),
    )
    for
      ordinary in [
        compile(query, context, limits),
        compile_query_script(script, context, limits),
      ] {
      assert_true(
        ordinary
        is Err(
          BindingPreparation(
            LocalProgram(Pipeline(_, { kind: Operation(ExpectedBoolean), .. }))
            | SourceProgram(
              Program(Pipeline(_, { kind: Operation(ExpectedBoolean), .. }))
            )
          )
        ),
      )
    }
    assert_true(
      @frontend.lower(text, Sql, Some(context))
      is Err(
        QueryLowering(
          BindingPreparation(
            LocalProgram(Pipeline(_, { kind: Operation(ExpectedBoolean), .. }))
            | SourceProgram(
              Program(Pipeline(_, { kind: Operation(ExpectedBoolean), .. }))
            )
          )
        )
      ),
    )
    assert_true(
      @frontend.lower(
        text.replace(old="WHERE x", new="WHERE x > 0"),
        Sql,
        Some(context),
      )
      is Ok(_),
    )
  }
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
  let missing = compile_query_script(
    parsed,
    { ..admitted, source_catalog: None, },
    construction_limits(),
  )
  guard missing is Err(BindingPreparation(MissingSourceCatalog(declaration))) else {
    fail("missing Source metadata must retain its common declaration")
  }
  assert_eq(declaration.stage_index, 0)
  assert_eq(declaration.input_name, "objects")
  assert_eq(declaration.connector, "crm/main")
  assert_eq(declaration.resource, "r")
  assert_eq(declaration.view, Some("v"))
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
