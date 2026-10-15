///|
test "Table CTAS and Pipe lower to a private Table input without a Named Result" {
  let binding = table_write_fixture(Create)
  // Scripts rename the source-free seed through the existing seed importer.
  let expected_source =
    #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_script_seed_0","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_script_seed_0","derive":{"aql_query_expr_0":{"literal":1}}},{"select":[{"id":"aql_query_expr_0"}],"as":"aql_script_result"}],"results":{},"table_inputs":{"aql_table_input":{"from":"aql_script_result","fields":["id"]}},"effects":{"aql_table_effect":{"store":{"target":"connector://local/report","mapping":"mapping:local.report.v1","from":{"table_input":"aql_table_input"},"table_write":{"intent":"create","action":"create","expected_table":null,"mapping_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","capability_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","installation_binding_cid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}}}}}],"results":{}}
  let expected = @program.parse(
    expected_source,
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    source in [
      "CREATE TABLE analytics.report AS SELECT 1 AS id", "SELECT 1 AS id |> CREATE TABLE analytics.report",
    ] {
    let query = match @query.parse_query(source, syntax_limits()) {
      Ok(value) => value
      Err(_) => fail("Table syntax rejected: " + source)
    }
    let program = match
      compile(
        query,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
        table_writes=[binding],
      ) {
      Ok(value) => value
      Err(_) => fail("Table lowering rejected: " + source)
    }
    assert_eq(@program.export_count(program), 0)
    // The expected private capture and operation metadata are authored from the
    // contract, not obtained by executing or serializing the product.
    let actual = semantic(program)
    assert_eq(actual, semantic(expected))
    assert_true(actual.contains("\"table_inputs\":{\"aql_table_input\""))
    assert_true(actual.contains("\"table_input\":\"aql_table_input\""))
    assert_true(actual.contains("\"intent\":\"create\""))
    assert_true(actual.contains("\"expected_table\":null"))
    assert_true(actual.contains("\"results\":{}"))
  }
}

///|
test "Table lowering rejects missing ambiguous and incompatible bindings" {
  let query = @query.parse_query(
    "CREATE TABLE analytics.report AS SELECT 1 AS id",
    syntax_limits(),
  ).unwrap()
  let context = { ..fixture_context(), inputs: [], }
  let create = table_write_fixture(Create)
  assert_true(
    compile(query, context, construction_limits())
    is Err(TableWriteBinding(UnknownTable)),
  )
  assert_true(
    compile(query, context, construction_limits(), table_writes=[create, create])
    is Err(TableWriteBinding(AmbiguousTable)),
  )
  let replace = table_write_fixture(
    Replace("12345678-1234-1234-1234-123456789abc", "sha256:" + "d".repeat(64)),
  )
  assert_true(
    compile(query, context, construction_limits(), table_writes=[replace])
    is Err(TableWriteBinding(ActionMismatch)),
  )
}

///|
test "Table OR REPLACE preserves its fixed selected action and expected generation" {
  let query = @query.parse_query(
    "SELECT 1 AS id |> EFFECT save CREATE OR REPLACE TABLE analytics.report",
    syntax_limits(),
  ).unwrap()
  let actions : Array[TableWriteAction] = [
    Create,
    Replace("12345678-1234-1234-1234-123456789abc", "sha256:" + "d".repeat(64)),
  ]
  for action in actions {
    let program = compile(
      query,
      { ..fixture_context(), inputs: [], },
      construction_limits(),
      table_writes=[table_write_fixture(action)],
    ).unwrap()
    let actual = semantic(program)
    assert_true(actual.contains("\"save\":{\"store\":"))
    assert_true(actual.contains("\"intent\":\"create_or_replace\""))
    match action {
      Create => assert_true(actual.contains("\"action\":\"create\""))
      Replace(uuid, generation) => {
        assert_true(actual.contains("\"action\":\"replace\""))
        assert_true(actual.contains(uuid))
        assert_true(actual.contains(generation))
      }
    }
  }
}

///|
test "Table private capture lowers sparse Graph rows without public Results" {
  let source = "WITH persons AS (SELECT 2 AS person_key, 'a' AS tenant_key, CAST(NULL AS FLOAT64) AS p UNION ALL SELECT 1 AS person_key, 'a' AS tenant_key, 7 AS p), companies AS (SELECT 3 AS person_key, 'a' AS tenant_key), g AS (GRAPH (NODE TABLES (persons AS N KEY (person_key, tenant_key) LABEL Person PROPERTIES (p), companies AS M KEY (person_key, tenant_key) LABEL Company NO PROPERTIES))) FROM g |> node_rows() |> DROP id, labels, tenant_key |> ORDER BY person_key |> EFFECT save CREATE TABLE analytics.report"
  let script = @query.parse_query_script(source, syntax_limits()).unwrap()
  let compiled = compile_query_script(
    script,
    { ..fixture_context(), inputs: [], },
    construction_limits(),
    table_writes=[table_write_fixture(Create)],
  )
  let program = match compiled {
    Ok(program) => program
    Err(UnsupportedGraph) => fail("Sparse Table lowering: UnsupportedGraph")
    Err(UnsupportedResult) => fail("Sparse Table lowering: UnsupportedResult")
    Err(UnsupportedOrdering) =>
      fail("Sparse Table lowering: UnsupportedOrdering")
    Err(UnsupportedEffect) => fail("Sparse Table lowering: UnsupportedEffect")
    Err(_) => fail("Sparse Table lowering rejected")
  }
  assert_eq(@program.export_count(program), 0)
  assert_true(semantic(program).contains("\"fields\":[\"p\",\"person_key\"]"))
  assert_true(
    semantic(program).contains("\"drop\":[\"id\",\"labels\",\"tenant_key\"]"),
  )
}

///|
test "Table terminal publishes only authored prefix Results and keeps its final input private" {
  for
    (statement, action) in [
      ("CREATE TABLE", Create),
      (
        "CREATE OR REPLACE TABLE",
        Replace(
          "12345678-1234-1234-1234-123456789abc",
          "sha256:" + "d".repeat(64),
        ),
      ),
    ] {
    let program = compile(
      @query.parse_query(
        statement +
        " analytics.report AS (SELECT 1 AS id |> RESULT before_write |> WHERE id = 2)",
        syntax_limits(),
      ).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
      table_writes=[table_write_fixture(action)],
    ).unwrap()
    let exports = @program.exports(program)
    assert_eq(exports.map(entry => entry.0), ["before_write"])
    let stage = @wire.open_object(
      @program.stage_body(@program.stages(program)[0]),
    ).unwrap()
    let results = @wire.required(stage, "results").unwrap()
    assert_eq(@wire.object_field_names(results).unwrap(), [exports[0].2])
    let original = @wire.open_object(
      @wire.required(@wire.open_object(results).unwrap(), exports[0].2).unwrap(),
    ).unwrap()
    let inputs = @wire.open_object(
      @wire.required(stage, "table_inputs").unwrap(),
    ).unwrap()
    let final = @wire.open_object(
      @wire.required(inputs, "aql_table_input").unwrap(),
    ).unwrap()
    assert_eq(
      @wire.elements(@wire.required(original, "fields").unwrap())
      .unwrap()
      .map(field => @wire.text(field).unwrap()),
      ["id"],
    )
    assert_eq(
      @wire.elements(@wire.required(final, "fields").unwrap())
      .unwrap()
      .map(field => @wire.text(field).unwrap()),
      ["id"],
    )
    // The earlier public producer must not be replaced by the filtered input.
    assert_false(
      @wire.text(@wire.required(original, "from").unwrap()) ==
      @wire.text(@wire.required(final, "from").unwrap()),
    )
    let steps = @wire.elements(@wire.required(stage, "steps").unwrap()).unwrap()
    assert_true(
      steps.any(step => {
        let body = @wire.open_object(step).unwrap()
        @wire.lookup(body, "filter") is Some(_)
      }),
    )
    assert_eq(
      @wire.text(
        @wire.required(@wire.open_object(steps.last().unwrap()).unwrap(), "as").unwrap(),
      ),
      @wire.text(@wire.required(final, "from").unwrap()),
    )
  }
}

///|
test "Table terminal authored final Result stays public without a second primary export" {
  let program = compile(
    @query.parse_query(
      "CREATE TABLE analytics.report AS (SELECT 1 AS id |> RESULT final)",
      syntax_limits(),
    ).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
    table_writes=[table_write_fixture(Create)],
  ).unwrap()
  assert_eq(@program.exports(program).map(entry => entry.0), ["final"])
  let stage = @wire.open_object(
    @program.stage_body(@program.stages(program)[0]),
  ).unwrap()
  let results = @wire.open_object(@wire.required(stage, "results").unwrap()).unwrap()
  let result = @wire.open_object(
    @wire.required(results, @program.exports(program)[0].2).unwrap(),
  ).unwrap()
  let inputs = @wire.open_object(@wire.required(stage, "table_inputs").unwrap()).unwrap()
  let input = @wire.open_object(
    @wire.required(inputs, "aql_table_input").unwrap(),
  ).unwrap()
  assert_eq(
    @wire.text(@wire.required(result, "from").unwrap()),
    @wire.text(@wire.required(input, "from").unwrap()),
  )
}

///|
test "ordinary nonterminal RESULT keeps its primary tail outside Table writes" {
  let program = compile(
    @query.parse_query(
      "SELECT 1 AS id |> RESULT before_write |> WHERE id = 2",
      syntax_limits(),
    ).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  assert_eq(@program.exports(program).map(entry => entry.0), [
    "before_write", "answer",
  ])
}
