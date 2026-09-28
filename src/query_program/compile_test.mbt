///|
fn construction_limits() -> Limits {
  let source : @builder.Limits = {
    source: { max_input_bytes: 10000, max_nodes: 10000, max_depth: 100, },
    tree: {
      max_nodes: 10000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 100000,
    },
    max_origin_entries: 20000,
    max_output_bytes: 100000,
  }
  {
    source,
    program: { source: source.source, tree: source.tree, max_stages: 20, },
    max_expression_work: 10000,
    max_join_output_rows: 1000L,
    max_collection_items: 1000L,
    max_collection_bytes: 10000L,
  }
}

///|
fn syntax_limits() -> @query.QueryLimits {
  let lexical : @query.LexicalLimits = {
    max_source_bytes: 10000,
    max_tokens: 1000,
    max_literal_bytes: 10000,
    max_work: 20000,
  }
  {
    lexical,
    expression: { lexical, max_nodes: 1000, max_depth: 100, max_work: 10000, },
    max_syntax_nodes: 1000,
    max_cte_count: 20,
    max_work: 20000,
  }
}

///|
fn fixture_context() -> Context {
  let declaration = @wire.admit(
    @source.parse_json(
      (
        #|{"carrier":"relation","schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"primary_key":["id"]}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    program_id: "fixture.query_pair",
    stage_id: "main",
    stage_result: "rows",
    result_name: "answer",
    captured_stage: None,
    inputs: [
      {
        relation: [{ value: "orders", quoted: false, }],
        name: "orders",
        source: Captured(declaration),
        visible_fields: ["id", "customer_id", "status", "amount"],
      },
    ],
  }
}

///|
fn values_context() -> Context {
  let step = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let base = fixture_context()
  let inputs = [{ ..base.inputs[0], source: GeneratedValues(step), }]
  { ..base, inputs, }
}

///|
fn semantic(program : @program.Program) -> String raise {
  let writer = @encode.writer(100000, 10000, 100)
  @program.emit_metadata_stripped_program(program, writer)
  @encode.finish(writer)
}

///|
fn check_limits() -> @check.CheckLimits {
  {
    input: construction_limits().program,
    compilation: {
      work: 10000000,
      artifacts: { bytes: 1000000, nodes: 100000, depth: 100, },
      structure: {
        stages: 20,
        steps: 20,
        results: 20,
        parameters: 10,
        bindings: 100,
        slots: 1000,
        references: 1000,
        requirements: 1000,
        tokens: 10000,
      },
      traversal: {
        nodes: 100000,
        depth: 100,
        text_bytes: 10000000,
        string_bytes: 100000,
        name_bytes: 1000000,
        pointer_units: 1000000,
        comparison_pairs: 1000000,
      },
      values: { nodes: 1000000, depth: 100, text_bytes: 100000, },
      policy: { bytes: 10000, nodes: 1000000, depth: 100, },
      patterns: { bytes: 1000000, nodes: 1000000, depth: 100, },
    },
  }
}

///|
fn check_environment(numeric? : Bool = false) -> @check.CheckEnvironment {
  let cid = "sha256:04185e37572a0a791a18909c4bc09da47f393976a9b6bb940ed9658a0497de07"
  let wire = @environment.read(
    @utf8.encode(
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:04185e37572a0a791a18909c4bc09da47f393976a9b6bb940ed9658a0497de07","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_analytic_frame_memberships":1000,"max_analytic_input_wire_bytes":1000,"max_analytic_output_wire_bytes":1000,"max_analytic_partition_wire_bytes":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
      ),
    ),
    cid,
    { max_bytes: 10000, max_nodes: 1000, max_depth: 100, max_members: 10, },
  ).unwrap()
  @check.checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    numeric_profile=if numeric {
      Some(@numeric.builtin_profile())
    } else {
      None
    },
  )
}

///|
test "independent SQL and Pipe pair enters the same admitted Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{"orders":{"carrier":"relation","schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"from":"orders","filter":{"eq":[{"field":"status"},{"literal":"open"}]}},{"select":["id","customer_id","amount"]},{"sort":[{"field":"amount","dir":"desc","nulls":"last"},{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","customer_id","amount"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    text in [
      "SELECT id, customer_id, amount FROM orders WHERE status = 'open' ORDER BY amount DESC, id ASC;",
      "FROM orders |> WHERE status = 'open' |> SELECT id, customer_id, amount |> ORDER BY amount DESC, id ASC;",
    ] {
    let parsed = @query.parse_query(text, syntax_limits()).unwrap()
    let compiled = compile(parsed, fixture_context(), construction_limits()).unwrap()
    assert_eq(semantic(compiled), semantic(expected))
  }
}

///|
test "query pair reaches the ordinary Program checker" {
  for
    text in [
      "SELECT id, customer_id, amount FROM orders WHERE status = 'open' ORDER BY amount DESC, id ASC",
      "SELECT id FROM orders ORDER BY amount DESC", "SELECT amount AS status FROM orders ORDER BY status, id",
      "SELECT DISTINCT amount AS x FROM orders ORDER BY x",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    let program = compile(query, fixture_context(), construction_limits()).unwrap()
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("typed local input should be statically closed")
      Rejected(_) => fail("query failed the ordinary checker")
    }
  }
}

///|
test "query Program construction rejects unresolved scope and output conflicts" {
  for
    text in [
      "SELECT missing FROM orders", "SELECT id, id FROM orders", "SELECT id FROM elsewhere",
      "SELECT id FROM orders ORDER BY missing", "FROM orders |> SELECT amount AS id, id",
    ] {
    let parsed = @query.parse_query(text, syntax_limits()).unwrap()
    assert_true(
      compile(parsed, fixture_context(), construction_limits()) is Err(_),
      msg=text,
    )
  }
}

///|
test "FROM-only selection and derived fields enter Program admission" {
  for
    text in [
      "FROM orders", "SELECT id, amount + 1 AS adjusted FROM orders WHERE status IS NOT NULL",
      "FROM orders |> WHERE amount > 0 |> SELECT id |> ORDER BY id |> LIMIT 2 OFFSET 1",
    ] {
    let parsed = @query.parse_query(text, syntax_limits()).unwrap()
    assert_true(
      compile(parsed, fixture_context(), construction_limits()) is Ok(_),
      msg=text,
    )
  }
}

///|
test "SELECT aliases preserve input snapshot and use private slots for replacements" {
  let context = fixture_context()
  let swapped = compile(
    @query.parse_query(
      "SELECT amount AS status, status AS original FROM orders",
      syntax_limits(),
    ).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(swapped).contains(
      "\"select\":[{\"status\":\"amount\"},{\"original\":\"status\"}]",
    ),
  )
  let replaced = compile(
    @query.parse_query(
      "SELECT amount + 1 AS amount FROM orders",
      syntax_limits(),
    ).unwrap(),
    fixture_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(replaced).contains(
      "\"derive\":{\"aql_query_expr_0\":{\"add\":[{\"field\":\"amount\"},{\"literal\":1}]}}",
    ),
  )
  assert_true(
    semantic(replaced).contains(
      "\"select\":[{\"amount\":\"aql_query_expr_0\"}]",
    ),
  )
}

///|
test "non-output ORDER BY stays hidden and output aliases take precedence" {
  let hidden = compile(
    @query.parse_query(
      "SELECT id FROM orders ORDER BY amount DESC",
      syntax_limits(),
    ).unwrap(),
    fixture_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(hidden)
  assert_true(
    wire.contains(
      "\"sort\":[{\"dir\":\"desc\",\"field\":\"amount\",\"nulls\":\"last\"}]",
    ),
  )
  assert_true(wire.contains("\"select\":[\"id\"]"))
  assert_true(wire.contains("\"fields\":[\"id\"]"))
  assert_true(wire.contains("\"steps\":[{\"from\":\"orders\",\"sort\""))
  let alias_over_input = compile(
    @query.parse_query(
      "SELECT amount AS status FROM orders ORDER BY status, id",
      syntax_limits(),
    ).unwrap(),
    fixture_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(alias_over_input)
  assert_true(wire.contains("\"sort\":[{\"dir\":\"asc\",\"field\":\"amount\""))
  assert_true(wire.contains("\"field\":\"id\""))
  assert_true(wire.contains("\"select\":[{\"status\":\"amount\"}]"))
  let qualified_input = compile(
    @query.parse_query(
      "SELECT amount AS status FROM orders AS o ORDER BY o.status",
      syntax_limits(),
    ).unwrap(),
    fixture_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(qualified_input)
  assert_true(wire.contains("\"field\":\"status\""))
  assert_true(wire.contains("\"steps\":[{\"from\":\"orders\",\"sort\""))
  assert_true(wire.contains("\"select\":[{\"status\":\"amount\"}]"))
}

///|
test "WHERE and peer SELECT expressions cannot use new SELECT aliases" {
  for
    text in [
      "SELECT amount AS adjusted FROM orders WHERE adjusted > 0", "SELECT amount AS adjusted, adjusted + 1 AS next FROM orders",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    assert_true(
      compile(query, fixture_context(), construction_limits()) is Err(_),
      msg=text,
    )
  }
}

///|
test "OVER uses the input scope and lowers through ordinary Program admission" {
  let text = "SELECT id AS renamed, ROW_NUMBER() OVER (PARTITION BY status ORDER BY id) AS pos FROM orders ORDER BY renamed"
  let query = @query.parse_query(text, syntax_limits()).unwrap()
  let program = compile(query, values_context(), construction_limits()).unwrap()
  let pipe = @query.parse_query(
    "FROM orders |> SELECT id AS renamed, ROW_NUMBER() OVER (PARTITION BY status ORDER BY id) AS pos |> ORDER BY renamed",
    syntax_limits(),
  ).unwrap()
  assert_eq(
    semantic(program),
    semantic(compile(pipe, values_context(), construction_limits()).unwrap()),
  )
  let wire = semantic(program)
  assert_true(
    wire.contains(
      "\"analytic\":{\"functions\":{\"pos\":{\"fn\":\"row_number\"}}",
    ),
  )
  assert_true(wire.contains("\"partition_by\":[\"status\"]"))
  assert_true(wire.contains("\"field\":\"id\""))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("analytic input should be statically closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let invalid = @query.parse_query(
    "SELECT id AS renamed, ROW_NUMBER() OVER (ORDER BY renamed) AS pos FROM orders",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(invalid, values_context(), construction_limits()) is Err(_),
  )
}

///|
test "Pipe analytic resolves a changed input snapshot" {
  let text = "FROM orders AS before |> SET amount = amount + 1 |> SELECT before.amount AS old_amount, amount, ROW_NUMBER() OVER (ORDER BY amount) AS pos"
  let query = @query.parse_query(text, syntax_limits()).unwrap()
  let program = compile(query, fixture_context(), construction_limits()).unwrap()
  let wire = semantic(program)
  assert_true(wire.contains("\"analytic\""))
  assert_true(wire.contains("\"old_amount\""))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("Pipe analytic should resolve changed input")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let sibling = @query.parse_query(
    "FROM orders |> SET amount = amount + 1 |> SELECT ROW_NUMBER() OVER (ORDER BY pos) AS pos",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(sibling, fixture_context(), construction_limits()) is Err(_),
  )
}

///|
test "OVER frame aggregate is not a group or final ORDER BY" {
  let text = "SELECT id, COUNT(amount) OVER (PARTITION BY status ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running FROM orders"
  let query = @query.parse_query(text, syntax_limits()).unwrap()
  let program = compile(query, values_context(), construction_limits()).unwrap()
  let wire = semantic(program)
  assert_true(
    wire.contains(
      "\"analytic\":{\"frame\":{\"end\":\"current_row\",\"start\":\"unbounded_preceding\"}",
    ),
  )
  assert_true(
    wire.contains("\"running\":{\"field\":\"amount\",\"fn\":\"count\"}"),
  )
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("analytic input should be statically closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "analytic SUM and AVG require the selected numeric profile" {
  for function_name in ["SUM", "AVG"] {
    let text = "SELECT id, " +
      function_name +
      "(amount) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running FROM orders"
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    let program = compile(query, values_context(), construction_limits()).unwrap()
    let wire = semantic(program)
    assert_true(wire.contains("\"analytic\""), msg=text)
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      NeedsInputs(_) => ()
      _ => fail("numeric profile omission must remain visible")
    }
    match
      @check.check_parsed(
        program,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      NeedsInputs(_) => fail("declared numeric profile should close the slot")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

///|
test "matching OVER windows share one analytic operation" {
  let text = "SELECT id, ROW_NUMBER() OVER (PARTITION BY status ORDER BY id) AS pos, LAG(amount, 2) OVER (PARTITION BY status ORDER BY id) AS previous FROM orders"
  let query = @query.parse_query(text, syntax_limits()).unwrap()
  let program = compile(query, values_context(), construction_limits()).unwrap()
  let wire = semantic(program)
  assert_eq(wire.split("\"analytic\":").length(), 2)
  assert_true(wire.contains("\"pos\":{\"fn\":\"row_number\"}"))
  assert_true(
    wire.contains(
      "\"previous\":{\"expr\":{\"field\":\"amount\"},\"fn\":\"lag\",\"offset\":2}",
    ),
  )
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("rank and navigation need no numeric profile")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  for
    text in [
      "SELECT ROW_NUMBER() OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS pos FROM orders",
      "SELECT LAG(amount, 9007199254740992) OVER (ORDER BY id) AS previous FROM orders",
      "SELECT LAG(amount, -1) OVER (ORDER BY id) AS previous FROM orders", "SELECT FIRST_VALUE(amount) OVER (ORDER BY id) AS first_amount FROM orders",
      "SELECT LAST_VALUE(amount) OVER (ORDER BY id) AS last_amount FROM orders",
      "SELECT COUNT(*) OVER (ORDER BY id) AS running FROM orders", "SELECT COUNTIF(amount > 0) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running FROM orders",
      "SELECT ROW_NUMBER() OVER (PARTITION BY missing ORDER BY id) AS pos FROM orders",
      "SELECT ROW_NUMBER() OVER (ORDER BY missing) AS pos FROM orders",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    assert_true(
      compile(query, values_context(), construction_limits()) is Err(_),
      msg=text,
    )
  }
  for
    text in [
      "SELECT COUNT(*) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED FOLLOWING AND CURRENT ROW) AS running FROM orders",
      "SELECT COUNT(*) OVER (ORDER BY id ROWS BETWEEN 2 FOLLOWING AND 1 FOLLOWING) AS running FROM orders",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    let program = compile(query, values_context(), construction_limits()).unwrap()
    assert_true(
      @check.check_parsed(program, check_environment(), None, check_limits())
      is Rejected(_),
      msg=text,
    )
  }
}

///|
test "Pipe EXTEND resolves every expression against its input snapshot" {
  let accepted = @query.parse_query(
    "FROM orders |> EXTEND amount + 1 AS adjusted, amount + 2 AS next |> SELECT id, adjusted, next",
    syntax_limits(),
  ).unwrap()
  let program = compile(accepted, fixture_context(), construction_limits()).unwrap()
  let wire = semantic(program)
  assert_true(wire.contains("\"derive\":{\"adjusted\""))
  assert_true(wire.contains("\"next\":{\"add\""))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("bounded scalar extension should be closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let invalid = @query.parse_query(
    "FROM orders |> EXTEND amount + 1 AS adjusted, adjusted + 1 AS next",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(invalid, fixture_context(), construction_limits()) is Err(_),
  )
}

///|
fn pair_context() -> Context {
  let step = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    program_id: "fixture.pipe_slots",
    stage_id: "main",
    stage_result: "rows",
    result_name: "answer",
    captured_stage: None,
    inputs: [
      {
        relation: [{ value: "pair", quoted: false, }],
        name: "pair",
        source: GeneratedValues(step),
        visible_fields: ["x", "y"],
      },
    ],
  }
}

///|
test "Pipe SET keeps old range slots and evaluates replacements together" {
  let query = @query.parse_query(
    "FROM pair AS before |> SET x = y, y = x |> SELECT before.x AS old_x, before.y AS old_y, x, y",
    syntax_limits(),
  ).unwrap()
  let program = compile(query, pair_context(), construction_limits()).unwrap()
  let wire = semantic(program)
  assert_true(wire.contains("\"aql_pipe_set_2\":{\"field\":\"y\"}"))
  assert_true(wire.contains("\"aql_pipe_set_3\":{\"field\":\"x\"}"))
  assert_true(
    wire.contains(
      "\"select\":[{\"old_x\":\"x\"},{\"old_y\":\"y\"},{\"x\":\"aql_pipe_set_2\"},{\"y\":\"aql_pipe_set_3\"}]",
    ),
  )
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("static pair is closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "Pipe DROP and AS separate current names from old range snapshots" {
  let context = pair_context()
  let retained = compile(
    @query.parse_query(
      "FROM pair AS before |> DROP x |> SELECT before.x AS old_x, y",
      syntax_limits(),
    ).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(retained).contains("\"select\":[{\"old_x\":\"x\"},\"y\"]"),
  )
  for
    text in [
      "FROM pair AS before |> DROP x |> SELECT x", "FROM pair |> SET z = x", "FROM pair |> RENAME x AS y",
      "FROM pair |> SET x = y, x = x",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    assert_true(
      compile(query, pair_context(), construction_limits()) is Err(_),
      msg=text,
    )
  }
  let renamed = compile(
    @query.parse_query(
      "FROM pair |> RENAME x AS z |> AS later |> SELECT later.z AS new_x, pair.x AS old_x",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(renamed).contains(
      "\"select\":[{\"new_x\":\"x\"},{\"old_x\":\"x\"}]",
    ),
  )
  let implicit = compile(
    @query.parse_query("FROM pair |> DROP x", syntax_limits()).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(implicit).contains("\"from\":\"pair\",\"select\":[\"y\"]"),
  )
  let old_order = compile(
    @query.parse_query(
      "FROM pair AS before |> SET x = y |> SELECT x |> ORDER BY before.x",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  let old_wire = semantic(old_order)
  assert_true(old_wire.contains("\"sort\":[{\"dir\":\"asc\",\"field\":\"x\""))
  assert_true(old_wire.contains("\"select\":[{\"x\":\"aql_pipe_set_2\"}]"))
  let alias_order = compile(
    @query.parse_query(
      "FROM pair AS before |> SET x = y |> SELECT x |> ORDER BY x",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(alias_order).contains(
      "\"sort\":[{\"dir\":\"asc\",\"field\":\"aql_pipe_set_2\"",
    ),
  )
  for program in [old_order, alias_order] {
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("static pair ordering should be closed")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

///|
test "Pipe AGGREGATE sees replaced top-level fields and closes old ranges" {
  let query = @query.parse_query(
    "FROM pair AS before |> SET x = y |> AGGREGATE COUNT(*) AS n GROUP BY x |> SELECT x, n",
    syntax_limits(),
  ).unwrap()
  let program = compile(query, pair_context(), construction_limits()).unwrap()
  let wire = semantic(program)
  assert_true(wire.contains("\"select\":[{\"x\":\"aql_pipe_set_2\"},\"y\"]"))
  assert_true(
    wire.contains("\"group\":{\"aggregates\":{\"n\":{\"fn\":\"count\"}}"),
  )
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("materialized grouping should be closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let old_range = @query.parse_query(
    "FROM pair AS before |> SET x = y |> AGGREGATE COUNT(*) AS n GROUP BY x |> SELECT before.x AS old_x, n",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(old_range, pair_context(), construction_limits()) is Err(_),
  )
}

///|
fn set_context() -> Context {
  let left = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"a":{"type":"number","nullable":true},"b":{"type":"string","nullable":false}},"rows":[{"a":1,"b":"x"},{"a":1,"b":"x"},{"a":2,"b":"y"},{"a":null,"b":"n"}]},"as":"left_rows"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let right = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"c":{"type":"number","nullable":true},"d":{"type":"string","nullable":false}},"rows":[{"c":1,"d":"x"},{"c":3,"d":"z"},{"c":null,"d":"n"}]},"as":"right_rows"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    program_id: "fixture.sql_set",
    stage_id: "main",
    stage_result: "rows",
    result_name: "answer",
    captured_stage: None,
    inputs: [
      {
        relation: [{ value: "left_rows", quoted: false, }],
        name: "left_rows",
        source: GeneratedValues(left),
        visible_fields: ["a", "b"],
      },
      {
        relation: [{ value: "right_rows", quoted: false, }],
        name: "right_rows",
        source: GeneratedValues(right),
        visible_fields: ["c", "d"],
      },
    ],
  }
}

///|
test "SQL set operations align positions before existing row-set kernels" {
  let terms = [
    ("UNION ALL", "\"append\":{\"with\":\"r\"}"),
    ("UNION DISTINCT", "\"distinct\":[\"a\",\"b\"]"),
    ("INTERSECT DISTINCT", "\"intersect\":{\"duplicates\":\"distinct\""),
    ("EXCEPT DISTINCT", "\"except\":{\"duplicates\":\"distinct\""),
  ]
  for (operator, expected) in terms {
    let text = "SELECT a, b FROM left_rows " +
      operator +
      " SELECT c, d FROM right_rows"
    let parsed = @query.parse_query(text, syntax_limits()).unwrap()
    let program = compile(parsed, set_context(), construction_limits()).unwrap()
    let wire = semantic(program)
    assert_true(wire.contains(expected), msg=text)
    assert_true(wire.contains("\"select\":[{\"a\":\"c\"},{\"b\":\"d\"}]"))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("set operands should be closed")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

///|
test "captured set terms share one checked acquisition stage" {
  let query = @query.parse_query(
    "SELECT id FROM orders WHERE amount > 1 UNION ALL SELECT id FROM orders WHERE amount > 1",
    syntax_limits(),
  ).unwrap()
  let program = compile(query, fixture_context(), construction_limits()).unwrap()
  let wire = semantic(program)
  assert_eq(wire.split("\"id\":\"aql_set_capture_0\"").length(), 2)
  assert_true(wire.contains("\"result\":\"source\""))
  assert_true(wire.contains("\"append\":{\"with\":\"r\"}"))
  assert_eq(wire.split("\"gt\":").length(), 2)
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) | NeedsInputs(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let distinct_predicates = @query.parse_query(
    "SELECT id FROM orders WHERE amount > 1 UNION ALL SELECT id FROM orders WHERE status = 'open'",
    syntax_limits(),
  ).unwrap()
  let preserved = compile(
    distinct_predicates,
    fixture_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(preserved).split("\"gt\":").length(), 2)
}

///|
test "BY NAME aligns selected names and retains checker type rejection" {
  let valid = @query.parse_query(
    "SELECT a, b FROM left_rows UNION DISTINCT BY NAME SELECT d AS b, c AS a FROM right_rows",
    syntax_limits(),
  ).unwrap()
  let program = compile(valid, set_context(), construction_limits()).unwrap()
  let wire = semantic(program)
  assert_true(wire.contains("\"select\":[{\"b\":\"d\"},{\"a\":\"c\"}]"))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("BY NAME operands should be statically closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let incompatible = @query.parse_query(
    "SELECT a, b FROM left_rows UNION DISTINCT BY NAME SELECT d AS a, c AS b FROM right_rows",
    syntax_limits(),
  ).unwrap()
  let wrong = compile(incompatible, set_context(), construction_limits()).unwrap()
  match @check.check_parsed(wrong, check_environment(), None, check_limits()) {
    Rejected(_) => ()
    _ => fail("BY NAME must not promote mismatched column contracts")
  }
}

///|
test "SQL and Pipe set expressions share checked Program meaning" {
  let sql = @query.parse_query(
    "SELECT a, b FROM left_rows UNION ALL SELECT c, d FROM right_rows",
    syntax_limits(),
  ).unwrap()
  let pipe = @query.parse_query(
    "FROM left_rows |> SELECT a, b |> UNION ALL (SELECT c, d FROM right_rows)",
    syntax_limits(),
  ).unwrap()
  let standard = compile(sql, set_context(), construction_limits()).unwrap()
  let piped = compile(pipe, set_context(), construction_limits()).unwrap()
  assert_eq(semantic(standard), semantic(piped))
  match @check.check_parsed(piped, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("Pipe set operands should be closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "source-free equijoin enters the ordinary checker" {
  let parsed = @query.parse_query(
    "SELECT l.a AS a, r.d AS d FROM left_rows AS l INNER JOIN right_rows AS r ON l.a = r.c",
    syntax_limits(),
  ).unwrap()
  let program = compile(parsed, set_context(), construction_limits()).unwrap()
  let piped = @query.parse_query(
    "FROM left_rows AS l |> INNER JOIN right_rows AS r ON l.a = r.c |> SELECT l.a AS a, r.d AS d",
    syntax_limits(),
  ).unwrap()
  assert_eq(
    semantic(program),
    semantic(compile(piped, set_context(), construction_limits()).unwrap()),
  )
  let implicit_alias = @query.parse_query(
    "SELECT l.a AS a, r.d AS d FROM left_rows l INNER JOIN right_rows r ON l.a = r.c",
    syntax_limits(),
  ).unwrap()
  assert_eq(
    semantic(program),
    semantic(
      compile(implicit_alias, set_context(), construction_limits()).unwrap(),
    ),
  )
  let wire = semantic(program)
  assert_true(wire.contains("\"join\":{\"kind\":\"inner\""))
  assert_true(wire.contains("\"left\":\"a\",\"right\":\"c\""))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("source-free join should be closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "JOIN computes SELECT expressions once after matching rows" {
  let sql = @query.parse_query(
    "SELECT l.a + r.c AS total, r.d AS label FROM left_rows AS l JOIN right_rows AS r ON l.a = r.c",
    syntax_limits(),
  ).unwrap()
  let pipe = @query.parse_query(
    "FROM left_rows AS l |> JOIN right_rows AS r ON l.a = r.c |> SELECT l.a + r.c AS total, r.d AS label",
    syntax_limits(),
  ).unwrap()
  let program = compile(sql, set_context(), construction_limits()).unwrap()
  assert_eq(
    semantic(program),
    semantic(compile(pipe, set_context(), construction_limits()).unwrap()),
  )
  let wire = semantic(program)
  assert_true(wire.contains("\"derive\":{\"total\":{\"add\""))
  assert_true(wire.contains("\"from\":\"aql_join_derived\",\"select\""))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("joined Values expression should be closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let missing_alias = @query.parse_query(
    "SELECT l.a + r.c FROM left_rows AS l JOIN right_rows AS r ON l.a = r.c",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(missing_alias, set_context(), construction_limits())
    is Err(UnsupportedJoin),
  )
  let unknown = @query.parse_query(
    "SELECT l.a + r.missing AS total FROM left_rows AS l JOIN right_rows AS r ON l.a = r.c",
    syntax_limits(),
  ).unwrap()
  assert_true(compile(unknown, set_context(), construction_limits()) is Err(_))
  let reversed = @query.parse_query(
    "SELECT r.c - l.a AS gap FROM left_rows AS l JOIN right_rows AS r ON l.a = r.c",
    syntax_limits(),
  ).unwrap()
  let reordered = semantic(
    compile(reversed, set_context(), construction_limits()).unwrap(),
  )
  assert_true(reordered.contains("\"aql_join_input_5\":\"right.c\""))
  assert_true(reordered.contains("\"aql_join_input_6\":\"left.a\""))
}

///|
test "JOIN DISTINCT compares only the selected output row" {
  let query = @query.parse_query(
    "SELECT DISTINCT l.a AS a FROM left_rows AS l JOIN right_rows AS r ON l.a = r.c",
    syntax_limits(),
  ).unwrap()
  let program = compile(query, set_context(), construction_limits()).unwrap()
  let wire = semantic(program)
  assert_true(wire.contains("\"distinct\":[\"a\"]"))
  assert_true(wire.contains("\"from\":\"aql_join_unique\""))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("distinct joined Values should be closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "LEFT JOIN WHERE filters null-extended rows after matching" {
  let sql = @query.parse_query(
    "SELECT l.a AS a FROM left_rows AS l LEFT JOIN right_rows AS r ON l.a = r.c WHERE r.c IS NULL",
    syntax_limits(),
  ).unwrap()
  let pipe = @query.parse_query(
    "FROM left_rows AS l |> LEFT JOIN right_rows AS r ON l.a = r.c |> WHERE r.c IS NULL |> SELECT l.a AS a",
    syntax_limits(),
  ).unwrap()
  let program = compile(sql, set_context(), construction_limits()).unwrap()
  assert_eq(
    semantic(program),
    semantic(compile(pipe, set_context(), construction_limits()).unwrap()),
  )
  let wire = semantic(program)
  assert_true(wire.contains("\"join\":{\"kind\":\"left\""))
  assert_true(wire.contains("\"filter\":{\"is_null\""))
  assert_true(wire.contains("\"aql_join_filtered\""))
  assert_true(wire.contains("\"from\":\"aql_join_filtered\",\"select\""))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("post-join filter should be statically closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "JOIN output ordering and LIMIT use selected aliases" {
  for
    text in [
      "SELECT l.a AS y, r.d AS detail FROM left_rows AS l LEFT JOIN right_rows AS r ON l.a = r.c ORDER BY y DESC LIMIT 2",
      "FROM left_rows AS l |> LEFT JOIN right_rows AS r ON l.a = r.c |> SELECT l.a AS y, r.d AS detail |> ORDER BY y DESC |> LIMIT 2",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    let program = compile(query, set_context(), construction_limits()).unwrap()
    let wire = semantic(program)
    assert_true(wire.contains("\"sort\":[{\"dir\":\"desc\",\"field\":\"y\""))
    assert_true(wire.contains("\"from\":\"aql_join_taken\""))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("joined ordering should be statically closed")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

///|
test "JOIN orders by hidden input without exposing it or weakening DISTINCT" {
  for
    text in [
      "SELECT l.a AS x FROM left_rows AS l CROSS JOIN right_rows AS r ORDER BY r.d DESC, x DESC LIMIT 3",
      "FROM left_rows AS l |> CROSS JOIN right_rows AS r |> SELECT l.a AS x |> ORDER BY r.d DESC, x DESC |> LIMIT 3",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    let program = compile(query, set_context(), construction_limits()).unwrap()
    let wire = semantic(program)
    assert_true(wire.contains("aql_join_sort_"))
    assert_true(wire.contains("\"from\":\"aql_join_visible\""))
    assert_true(wire.contains("\"fields\":[\"x\"]"))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("hidden JOIN sort should be statically closed")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
  let distinct = @query.parse_query(
    "SELECT DISTINCT l.a AS x FROM left_rows AS l CROSS JOIN right_rows AS r ORDER BY r.d",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(distinct, set_context(), construction_limits())
    is Err(UnsupportedOrdering),
  )
}

///|
test "Pipe WHERE before JOIN filters the left seed before null extension" {
  let query = @query.parse_query(
    "FROM left_rows AS l |> WHERE l.a > 1 |> LEFT JOIN right_rows AS r ON l.a = r.c |> SELECT l.a AS a, r.d AS d",
    syntax_limits(),
  ).unwrap()
  let program = compile(query, set_context(), construction_limits()).unwrap()
  let wire = semantic(program)
  assert_true(wire.contains("\"aql_join_prefiltered\""))
  assert_eq(wire.split("\"filter\":").length(), 2)
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("prefiltered joined Values should be closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "Pipe WHERE before JOIN cannot see the right relation" {
  let query = @query.parse_query(
    "FROM left_rows AS l |> WHERE r.c > 1 |> LEFT JOIN right_rows AS r ON l.a = r.c |> SELECT l.a AS a",
    syntax_limits(),
  ).unwrap()
  assert_true(compile(query, set_context(), construction_limits()) is Err(_))
}

///|
test "Pipe WHERE before JOIN filters a subquery stage" {
  let query = @query.parse_query(
    "FROM (SELECT a, b FROM left_rows) AS l |> WHERE l.a > 1 |> LEFT JOIN (SELECT c, d FROM right_rows) AS r ON l.a = r.c |> SELECT l.a AS a, r.d AS d",
    syntax_limits(),
  ).unwrap()
  let program = compile(query, set_context(), construction_limits()).unwrap()
  let wire = semantic(program)
  assert_true(wire.contains("\"aql_join_prefiltered\""))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("subquery join should be statically closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "CTE JOIN body shares scalar projection and post-join filter lowering" {
  let query = @query.parse_query(
    "WITH base AS (SELECT a, b FROM left_rows), other AS (SELECT a, b FROM base), matched AS (SELECT l.a + r.a AS total FROM base AS l JOIN other AS r ON l.a = r.a WHERE r.a > 0) SELECT total FROM matched",
    syntax_limits(),
  ).unwrap()
  let program = compile(query, set_context(), construction_limits()).unwrap()
  let wire = semantic(program)
  assert_true(wire.contains("\"derive\":{\"total\":{\"add\""))
  assert_true(wire.contains("\"aql_join_filtered\""))
  assert_eq(@program.stage_count(program), 4)
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("joined CTE inputs should be statically closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "CTE JOIN DISTINCT publishes the deduplicated Stage Result" {
  for
    text in [
      "WITH base AS (SELECT a FROM left_rows), other AS (SELECT a FROM base) SELECT DISTINCT l.a AS a FROM base AS l JOIN other AS r ON l.a = r.a",
      "WITH base AS (SELECT a FROM left_rows), other AS (SELECT a FROM base), matched AS (SELECT DISTINCT l.a AS a FROM base AS l JOIN other AS r ON l.a = r.a) SELECT a FROM matched",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    let program = compile(query, set_context(), construction_limits()).unwrap()
    let wire = semantic(program)
    assert_true(wire.contains("\"distinct\":[\"a\"]"), msg=text)
    assert_true(wire.contains("\"from\":\"aql_join_unique\""), msg=text)
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("joined CTE inputs should be statically closed")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

///|
test "CTE JOIN uses the same hidden ORDER and visible Result projection" {
  for
    text in [
      "WITH base AS (SELECT a, b FROM left_rows), other AS (SELECT a, b FROM base) SELECT l.a AS x FROM base AS l CROSS JOIN other AS r ORDER BY r.b DESC, x DESC LIMIT 3",
      "WITH base AS (SELECT a, b FROM left_rows), other AS (SELECT a, b FROM base) SELECT l.a AS x FROM base AS l CROSS JOIN other AS r ORDER BY x DESC LIMIT 2",
    ] {
    let parsed = @query.parse_query(text, syntax_limits())
    assert_true(parsed is Ok(_), msg=text)
    let query = parsed.unwrap()
    let program = compile(query, set_context(), construction_limits()).unwrap()
    let wire = semantic(program)
    if text.contains("r.b DESC") {
      assert_true(wire.contains("aql_join_sort_"))
      assert_true(wire.contains("\"from\":\"aql_join_visible\""))
    }
    assert_true(wire.contains("\"fields\":[\"x\"]"))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("CTE JOIN order should be statically closed")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}

///|
test "FULL Values join refuses to invent stable row identities" {
  let query = @query.parse_query(
    "SELECT l.a AS a, r.d AS d FROM left_rows AS l FULL JOIN right_rows AS r ON l.a = r.c",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(query, set_context(), construction_limits()) is Err(UnsupportedJoin),
  )
}

///|
test "one CTE lowers to a shared checked Stage Result" {
  let query = @query.parse_query(
    "WITH chosen AS (SELECT a, b FROM left_rows WHERE a > 1) SELECT a FROM chosen",
    syntax_limits(),
  ).unwrap()
  let program = compile(query, set_context(), construction_limits()).unwrap()
  let wire = semantic(program)
  assert_eq(@program.stage_count(program), 2)
  assert_true(wire.contains("\"id\":\"aql_cte_0\""))
  assert_true(wire.contains("\"stage\":\"aql_cte_0\""))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("source-free CTE should be closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let shadow = @query.parse_query(
    "WITH left_rows AS (SELECT a FROM left_rows) SELECT a FROM left_rows",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(shadow, set_context(), construction_limits()) is Err(UnsupportedCte),
  )
  let reused = @query.parse_query(
    "WITH chosen AS (SELECT a, b FROM left_rows WHERE a > 0) SELECT l.a AS a, r.b AS right_b FROM chosen AS l JOIN chosen AS r ON l.a = r.a",
    syntax_limits(),
  ).unwrap()
  let joined = compile(reused, set_context(), construction_limits()).unwrap()
  assert_eq(@program.stage_count(joined), 2)
  assert_true(
    compile(reused, set_context(), {
      ..construction_limits(),
      max_join_output_rows: 0L,
    })
    is Err(UnsupportedCte),
  )
  match @check.check_parsed(joined, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("reused CTE should remain closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let using_join = @query.parse_query(
    "WITH chosen AS (SELECT a, b FROM left_rows) SELECT a FROM chosen AS l JOIN chosen AS r USING (a)",
    syntax_limits(),
  ).unwrap()
  let using_program = compile(using_join, set_context(), construction_limits()).unwrap()
  assert_true(
    semantic(using_program).contains("\"left\":\"a\",\"right\":\"a\""),
  )
  match
    @check.check_parsed(
      using_program,
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    NeedsInputs(_) => fail("reused USING CTE should remain closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "CTE chain references prior declarations without source substitution" {
  let query = @query.parse_query(
    "WITH first AS (SELECT a, b FROM left_rows), second AS (SELECT a, b FROM first WHERE a > 1) SELECT a FROM second",
    syntax_limits(),
  ).unwrap()
  let program = compile(query, set_context(), construction_limits()).unwrap()
  assert_eq(@program.stage_count(program), 3)
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("source-free CTE chain should be closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let forward = @query.parse_query(
    "WITH first AS (SELECT a FROM second), second AS (SELECT a FROM first) SELECT a FROM second",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(forward, set_context(), construction_limits())
    is Err(UnsupportedCte),
  )
}

///|
test "CTE branches share one checked producer and reject unchecked declarations" {
  let branched = @query.parse_query(
    "WITH base AS (SELECT a, b FROM left_rows), first AS (SELECT a FROM base WHERE a = 1), second AS (SELECT a FROM base WHERE a = 2) SELECT l.a AS left_a, r.a AS right_a FROM first AS l JOIN second AS r ON l.a = r.a",
    syntax_limits(),
  ).unwrap()
  let program = compile(branched, set_context(), construction_limits()).unwrap()
  assert_eq(@program.stage_count(program), 4)
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("branched CTE should remain closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let unused = @query.parse_query(
    "WITH unused AS (SELECT a FROM left_rows), selected AS (SELECT a FROM left_rows WHERE a > 1) SELECT a FROM selected",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(unused, set_context(), construction_limits()) is Err(UnsupportedCte),
  )
  for
    text in [
      "WITH bad AS (SELECT a FROM bad), selected AS (SELECT a FROM left_rows) SELECT a FROM selected",
      "WITH bad AS (SELECT a FROM missing), selected AS (SELECT a FROM left_rows) SELECT a FROM selected",
      "WITH bad AS (SELECT a FROM selected), selected AS (SELECT a FROM left_rows) SELECT a FROM selected",
      "WITH chosen AS (SELECT a FROM left_rows), CHOSEN AS (SELECT a FROM left_rows) SELECT a FROM chosen",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    assert_true(compile(query, set_context(), construction_limits()) is Err(_))
  }
}

///|
test "SQL and Pipe FROM subqueries reuse the ordinary checked Stage Result" {
  let sql = @query.parse_query(
    "SELECT s.id FROM (SELECT id FROM orders WHERE status = 'open') AS s",
    syntax_limits(),
  ).unwrap()
  let pipe = @query.parse_query(
    "FROM (SELECT id FROM orders WHERE status = 'open') AS s |> SELECT s.id",
    syntax_limits(),
  ).unwrap()
  let sql_program = compile(sql, fixture_context(), construction_limits()).unwrap()
  let pipe_program = compile(pipe, fixture_context(), construction_limits()).unwrap()
  assert_eq(semantic(sql_program), semantic(pipe_program))
  assert_eq(@program.stage_count(sql_program), 2)
  match
    @check.check_parsed(sql_program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("FROM subquery should remain statically closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let inside_cte = @query.parse_query(
    "WITH chosen AS (SELECT s.id FROM (SELECT id FROM orders) AS s) SELECT id FROM chosen",
    syntax_limits(),
  ).unwrap()
  let inside_program = compile(
    inside_cte,
    fixture_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(@program.stage_count(inside_program), 3)
  match
    @check.check_parsed(
      inside_program,
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    NeedsInputs(_) => fail("nested CTE source should remain statically closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let collision = @query.parse_query(
    "WITH aql_query_source_0 AS (SELECT id FROM orders) SELECT s.id FROM (SELECT id FROM aql_query_source_0) AS s",
    syntax_limits(),
  ).unwrap()
  let collision_program = compile(
    collision,
    fixture_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(@program.stage_count(collision_program), 3)
  match
    @check.check_parsed(
      collision_program,
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    NeedsInputs(_) => fail("source names should not capture generated bindings")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let ordered = @query.parse_query(
    "SELECT s.id FROM (SELECT id FROM orders ORDER BY id LIMIT 2) AS s",
    syntax_limits(),
  ).unwrap()
  let ordered_program = compile(
    ordered,
    fixture_context(),
    construction_limits(),
  ).unwrap()
  assert_true(semantic(ordered_program).contains("\"take\":{\"count\":2"))
  match
    @check.check_parsed(
      ordered_program,
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    NeedsInputs(_) => fail("ordered subquery should remain statically closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "named JOIN subquery reuses an earlier checked CTE result" {
  let query = @query.parse_query(
    "WITH base AS (SELECT id FROM orders) SELECT l.id AS left_id, r.id AS right_id FROM base AS l JOIN (SELECT id FROM base WHERE id = 'a') AS r ON l.id = r.id",
    syntax_limits(),
  ).unwrap()
  let program = compile(query, values_context(), construction_limits()).unwrap()
  assert_eq(@program.stage_count(program), 3)
  let wire = semantic(program)
  assert_true(wire.contains("\"stage\":\"aql_cte_0\""))
  assert_true(wire.contains("\"stage\":\"aql_cte_1\""))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("JOIN subquery should use checked Stage Results")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "CTE join body consumes prior checked results without source replay" {
  let query = @query.parse_query(
    "WITH base AS (SELECT id FROM orders), chosen AS (SELECT id FROM base WHERE id = 'a'), matched AS (SELECT l.id AS id FROM base AS l JOIN chosen AS r ON l.id = r.id) SELECT id FROM matched",
    syntax_limits(),
  ).unwrap()
  let program = compile(query, values_context(), construction_limits()).unwrap()
  assert_eq(@program.stage_count(program), 4)
  let wire = semantic(program)
  assert_eq(wire.split("\"values\"").length(), 2)
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("CTE join body should use prior checked Results")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  for
    text in [
      "WITH base AS (SELECT id FROM orders), matched AS (SELECT l.id AS id FROM base AS l JOIN later AS r ON l.id = r.id), later AS (SELECT id FROM base) SELECT id FROM matched",
      "WITH base AS (SELECT id FROM orders), matched AS (SELECT l.id AS id FROM orders AS l JOIN base AS r ON l.id = r.id) SELECT id FROM matched",
    ] {
    let rejected = @query.parse_query(text, syntax_limits()).unwrap()
    assert_true(
      compile(rejected, values_context(), construction_limits()) is Err(_),
    )
  }
}

///|
test "FULL CTE join retains keyed input identity for common closure" {
  let query = @query.parse_query(
    "WITH chosen AS (SELECT id, customer_id FROM orders) SELECT l.id AS left_id, r.id AS right_id FROM chosen AS l FULL JOIN chosen AS r ON l.customer_id = r.customer_id",
    syntax_limits(),
  ).unwrap()
  let program = compile(query, fixture_context(), construction_limits()).unwrap()
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("keyed FULL CTE should be statically closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let using_query = @query.parse_query(
    "WITH chosen AS (SELECT id, customer_id FROM orders) SELECT customer_id FROM chosen AS l FULL JOIN chosen AS r USING (customer_id)",
    syntax_limits(),
  ).unwrap()
  let using_program = compile(
    using_query,
    fixture_context(),
    construction_limits(),
  ).unwrap()
  let using_wire = semantic(using_program)
  assert_true(using_wire.contains("\"coalesce\""))
  assert_true(using_wire.contains("\"fields\":[\"customer_id\"]"))
  match
    @check.check_parsed(
      using_program,
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    NeedsInputs(_) => fail("keyed FULL USING CTE should be statically closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let right_only = @query.parse_query(
    "WITH all_rows AS (SELECT id, customer_id FROM orders), subset AS (SELECT id, customer_id FROM all_rows WHERE id = 'one') SELECT customer_id, l.id AS left_id, r.id AS right_id FROM subset AS l FULL JOIN all_rows AS r USING (customer_id)",
    syntax_limits(),
  ).unwrap()
  let right_only_program = compile(
    right_only,
    fixture_context(),
    construction_limits(),
  ).unwrap()
  let right_only_wire = semantic(right_only_program)
  assert_true(right_only_wire.contains("\"coalesce\""))
  assert_true(right_only_wire.contains("\"stage\":\"aql_cte_0\""))
  assert_true(right_only_wire.contains("\"stage\":\"aql_cte_1\""))
  match
    @check.check_parsed(
      right_only_program,
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    NeedsInputs(_) => fail("two-CTE FULL USING should be statically closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let duplicate_alias = @query.parse_query(
    "WITH chosen AS (SELECT id, customer_id FROM orders) SELECT l.id AS key, r.id AS KEY FROM chosen AS l FULL JOIN chosen AS r USING (customer_id)",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(duplicate_alias, fixture_context(), construction_limits())
    is Err(DuplicateOutput),
  )
  let unkeyed = @query.parse_query(
    "WITH chosen AS (SELECT a, b FROM left_rows) SELECT l.a AS left_a, r.a AS right_a FROM chosen AS l FULL JOIN chosen AS r ON l.a = r.a",
    syntax_limits(),
  ).unwrap()
  let unkeyed_program = compile(unkeyed, set_context(), construction_limits()).unwrap()
  assert_true(
    @check.check_parsed(
      unkeyed_program,
      check_environment(),
      None,
      check_limits(),
    )
    is Rejected(_),
  )
}

///|
test "JOIN USING binds both checked keys and rejects ambiguous columns" {
  let using_query = @query.parse_query(
    "SELECT l.a AS a, r.b AS right_b FROM left_rows AS l INNER JOIN left_rows AS r USING (a)",
    syntax_limits(),
  ).unwrap()
  let program = compile(using_query, set_context(), construction_limits()).unwrap()
  let wire = semantic(program)
  assert_true(wire.contains("\"left\":\"a\",\"right\":\"a\""))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("source-free USING join should be closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let ambiguous = @query.parse_query(
    "SELECT a FROM left_rows AS l INNER JOIN left_rows AS r ON l.a = r.a",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(ambiguous, set_context(), construction_limits()) is Err(_),
  )
}

///|
test "SQL exact BY NAME and positional shape reject mismatched outputs" {
  let named = @query.parse_query(
    "SELECT a, b FROM left_rows UNION ALL BY NAME SELECT b, a FROM left_rows",
    syntax_limits(),
  ).unwrap()
  let program = compile(named, set_context(), construction_limits()).unwrap()
  let wire = semantic(program)
  assert_true(wire.contains("\"append\":{\"with\":"))
  assert_eq(wire.split("\"values\":").length(), 3)
  for
    text in [
      "SELECT a, b FROM left_rows UNION ALL BY NAME SELECT c, d FROM right_rows",
      "SELECT a, b FROM left_rows UNION ALL SELECT c FROM right_rows",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    assert_true(
      compile(query, set_context(), construction_limits()) is Err(_),
      msg=text,
    )
  }
}

///|
test "ordered collection aggregates retain literal and order contracts" {
  let source_free = compile(
    @query.parse_query(
      "SELECT STRING_AGG(b, '|' ORDER BY a DESC) AS labels FROM left_rows",
      syntax_limits(),
    ).unwrap(),
    set_context(),
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(source_free, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("source-free collection should be bounded")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let unkeyed_array = compile(
    @query.parse_query(
      "SELECT ARRAY_AGG(DISTINCT a IGNORE NULLS ORDER BY a DESC) AS ids FROM left_rows",
      syntax_limits(),
    ).unwrap(),
    set_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    @check.check_parsed(
      unkeyed_array,
      check_environment(),
      None,
      check_limits(),
    )
    is Rejected(_),
  )
  let keyed_seed = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"a":{"type":"number","nullable":false},"b":{"type":"string","nullable":false}},"rows":[{"a":1,"b":"x"},{"a":1,"b":"y"},{"a":2,"b":"z"}]},"as":"left_rows"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let base = set_context()
  let context = {
    ..base,
    inputs: [
      { ..base.inputs[0], source: GeneratedValues(keyed_seed), },
      base.inputs[1],
    ],
  }
  let keyed_array = compile(
    @query.parse_query(
      "SELECT ARRAY_AGG(DISTINCT a IGNORE NULLS ORDER BY a DESC) AS ids FROM left_rows",
      syntax_limits(),
    ).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  let keyed_wire = semantic(keyed_array)
  assert_true(keyed_wire.contains("\"select\":[\"a\"]"))
  assert_true(keyed_wire.contains("\"distinct\":[\"a\"]"))
  match
    @check.check_parsed(keyed_array, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("deduplicated array input should be bounded")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let unbounded_string = @query.parse_query(
    "SELECT STRING_AGG(b, '|' ORDER BY a) AS labels FROM left_rows",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(unbounded_string, set_context(), {
      ..construction_limits(),
      max_collection_bytes: 0L,
    })
    is Err(UnsupportedAggregate),
  )
  let array_query = @query.parse_query(
    "SELECT customer_id, ARRAY_AGG(DISTINCT id IGNORE NULLS ORDER BY id) AS ids FROM orders GROUP BY customer_id",
    syntax_limits(),
  ).unwrap()
  let array_program = compile(
    array_query,
    fixture_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    compile(array_query, fixture_context(), {
      ..construction_limits(),
      max_collection_items: 0L,
    })
    is Err(UnsupportedAggregate),
  )
  let wire = semantic(array_program)
  assert_true(
    wire.contains(
      "\"ids\":{\"distinct\":true,\"field\":\"id\",\"fn\":\"array_agg\"",
    ),
  )
  assert_true(
    wire.contains(
      "\"order_by\":[{\"dir\":\"asc\",\"field\":\"id\",\"nulls\":\"first\"}]",
    ),
  )
  match
    @check.check_parsed(
      array_program,
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    NeedsInputs(_) => fail("ordered array bound should be selected")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let string_query = @query.parse_query(
    "SELECT customer_id, STRING_AGG(status, '|' ORDER BY id) AS statuses FROM orders GROUP BY customer_id",
    syntax_limits(),
  ).unwrap()
  let string_program = compile(
    string_query,
    fixture_context(),
    construction_limits(),
  ).unwrap()
  assert_true(semantic(string_program).contains("\"delimiter\":\"|\""))
  assert_true(semantic(string_program).contains("\"max_bytes\":10000"))
  match
    @check.check_parsed(
      string_program,
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    NeedsInputs(_) => fail("ordered string bound should be selected")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  for
    text in [
      "SELECT ARRAY_AGG(id ORDER BY id) AS ids FROM orders", "SELECT ARRAY_AGG(id IGNORE NULLS) AS ids FROM orders",
      "SELECT STRING_AGG(status, id ORDER BY id) AS statuses FROM orders", "SELECT STRING_AGG(status, '|') AS statuses FROM orders",
    ] {
    assert_true(@query.parse_query(text, syntax_limits()) is Err(_), msg=text)
  }
}

///|
test "DISTINCT compares projected fields and refuses inaccessible source order" {
  let accepted = compile(
    @query.parse_query(
      "SELECT DISTINCT amount AS x FROM orders ORDER BY x",
      syntax_limits(),
    ).unwrap(),
    fixture_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(accepted)
  assert_true(wire.contains("\"distinct\":[\"x\"]"))
  assert_true(wire.contains("\"fields\":[\"x\"]"))
  let rejected = @query.parse_query(
    "SELECT DISTINCT id FROM orders ORDER BY amount",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(rejected, fixture_context(), construction_limits())
    is Err(UnsupportedOrdering),
  )
  let selected_expression = compile(
    @query.parse_query(
      "SELECT DISTINCT amount + 1 AS x FROM orders ORDER BY amount+1",
      syntax_limits(),
    ).unwrap(),
    fixture_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(selected_expression)
  assert_true(wire.contains("\"distinct\":[\"x\"]"))
  assert_true(wire.contains("\"sort\":[{\"dir\":\"asc\",\"field\":\"x\""))
  let parenthesized = compile(
    @query.parse_query(
      "SELECT DISTINCT amount + 1 AS x FROM orders ORDER BY (amount + 1)",
      syntax_limits(),
    ).unwrap(),
    fixture_context(),
    construction_limits(),
  ).unwrap()
  assert_true(semantic(parenthesized).contains("\"field\":\"x\""))
  let different_call = @query.parse_query(
    "SELECT DISTINCT LOWER(status) AS x FROM orders ORDER BY LOWER(customer_id)",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(different_call, fixture_context(), construction_limits())
    is Err(UnsupportedOrdering),
  )
}

///|
test "source-free Values context enters the same query Program path" {
  let seed = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"o1","customer_id":"c1","status":"open","amount":120},{"id":"o2","customer_id":"c1","status":"closed","amount":30},{"id":"o3","customer_id":"c2","status":"open","amount":80}]},"as":"orders"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let context = fixture_context()
  let input = { ..context.inputs[0], source: GeneratedValues(seed), }
  let generated = { ..context, inputs: [input], }
  let query = @query.parse_query(
    "SELECT id, customer_id, amount FROM orders WHERE status = 'open' ORDER BY amount DESC, id ASC",
    syntax_limits(),
  ).unwrap()
  let program = compile(query, generated, construction_limits()).unwrap()
  let wire = semantic(program)
  assert_true(wire.contains("\"inputs\":{}"))
  assert_true(wire.contains("\"values\":{\"rows\":["))
  assert_true(wire.contains("\"fields\":[\"id\",\"customer_id\",\"amount\"]"))
  let wrong = { ..input, name: "other", }
  assert_true(
    compile(query, { ..context, inputs: [wrong], }, construction_limits())
    is Err(InvalidContext),
  )
}

///|
test "captured source is read once before the downstream query task" {
  let context = { ..fixture_context(), captured_stage: Some("capture"), }
  for
    text in [
      "SELECT id FROM orders WHERE amount > 10", "FROM orders |> WHERE amount > 10 |> SELECT id",
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    let program = compile(query, context, construction_limits()).unwrap()
    let wire = semantic(program)
    assert_true(wire.contains("\"id\":\"capture\""))
    assert_true(
      wire.contains("\"inputs\":{\"orders\":{\"carrier\":\"relation\""),
    )
    assert_true(
      wire.contains(
        "\"orders\":{\"result\":{\"result\":\"source\",\"stage\":\"capture\"}}",
      ),
    )
    assert_true(
      wire.contains(
        "\"filter\":{\"gt\":[{\"field\":\"amount\"},{\"literal\":10}]}",
      ),
    )
    let mut count = 0
    for _ in wire.split("\"filter\"") {
      count += 1
    }
    assert_eq(count, 2)
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      _ => fail("captured query must use ordinary checker")
    }
  }
}

///|
test "source-free SELECT star preserves direct Values publication" {
  let seed = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"string","nullable":false}},"rows":[{"id":"a"},{"id":"b"}]},"as":"orders"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let context = fixture_context()
  let input = {
    ..context.inputs[0],
    source: GeneratedValues(seed),
    visible_fields: ["id"],
  }
  let query = @query.parse_query("SELECT * FROM orders", syntax_limits()).unwrap()
  let program = compile(
    query,
    { ..context, inputs: [input], },
    construction_limits(),
  ).unwrap()
  let wire = semantic(program)
  assert_true(wire.contains("\"steps\":[{\"as\":\"orders\",\"values\""))
  assert_true(!wire.contains("\"select\""))
  assert_true(wire.contains("\"fields\":[\"id\"]"))
}

///|
test "GROUP BY and HAVING resolve SELECT names in the GoogleSQL scope" {
  let grouped = compile(
    @query.parse_query(
      "SELECT amount AS status, COUNT(*) AS n FROM orders GROUP BY status HAVING n > 1",
      syntax_limits(),
    ).unwrap(),
    fixture_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(grouped)
  assert_true(
    wire.contains(
      "\"group\":{\"aggregates\":{\"n\":{\"fn\":\"count\"}},\"by\":[\"amount\"]}",
    ),
  )
  assert_true(
    wire.contains("\"filter\":{\"gt\":[{\"field\":\"n\"},{\"literal\":1}]}"),
  )
  assert_true(wire.contains("\"select\":[{\"status\":\"amount\"},\"n\"]"))
  match
    @check.check_parsed(grouped, check_environment(), None, check_limits()) {
    Checked(_) => ()
    _ => fail("grouped query failed the ordinary checker")
  }
  let shadowed = compile(
    @query.parse_query(
      "SELECT status AS amount, COUNT(*) AS n FROM orders GROUP BY amount HAVING amount = 'open'",
      syntax_limits(),
    ).unwrap(),
    fixture_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(shadowed)
  assert_true(wire.contains("\"by\":[\"status\"]"))
  assert_true(wire.contains("\"field\":\"status\""))
  match
    @check.check_parsed(shadowed, check_environment(), None, check_limits()) {
    Checked(_) => ()
    _ => fail("shadowed group alias failed the ordinary checker")
  }
  let derived = compile(
    @query.parse_query(
      "SELECT amount + 1 AS bucket, COUNT(DISTINCT customer_id) AS n FROM orders GROUP BY bucket",
      syntax_limits(),
    ).unwrap(),
    fixture_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(derived)
  assert_true(wire.contains("\"derive\":{\"aql_group_key_0\""))
  assert_true(wire.contains("\"by\":[\"aql_group_key_0\"]"))
  assert_true(
    wire.contains(
      "\"n\":{\"distinct\":true,\"field\":\"customer_id\",\"fn\":\"count\"}",
    ),
  )
  assert_true(
    wire.contains("\"select\":[{\"bucket\":\"aql_group_key_0\"},\"n\"]"),
  )
  let parenthesized_key = compile(
    @query.parse_query(
      "SELECT amount + 1 AS bucket, COUNT(*) AS n FROM orders GROUP BY (amount + 1)",
      syntax_limits(),
    ).unwrap(),
    fixture_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(parenthesized_key).contains(
      "\"select\":[{\"bucket\":\"aql_group_key_0\"},\"n\"]",
    ),
  )
}

///|
test "grouped SELECT rejects nongrouped field and invalid aggregate form" {
  let query = @query.parse_query(
    "SELECT customer_id, COUNT(*) AS n FROM orders GROUP BY status",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(query, fixture_context(), construction_limits()) is Err(_),
  )
  for
    text in [
      "SELECT COUNT(DISTINCT *) AS n FROM orders", "SELECT MIN(DISTINCT amount) AS n FROM orders",
      "SELECT COUNT(*) FROM orders",
    ] {
    assert_true(@query.parse_query(text, syntax_limits()) is Err(_), msg=text)
  }
  let ordinal = @query.parse_query(
    "SELECT amount, COUNT(*) AS n FROM orders GROUP BY 1",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(ordinal, fixture_context(), construction_limits())
    is Err(UnsupportedGrouping),
  )
}

///|
test "SQL GROUP BY and Pipe AGGREGATE use the same checked Program" {
  let sql = @query.parse_query(
    "SELECT id, COUNT(*) AS n FROM orders WHERE amount > 0 GROUP BY id",
    syntax_limits(),
  ).unwrap()
  let pipe = @query.parse_query(
    "FROM orders |> WHERE amount > 0 |> AGGREGATE COUNT(*) AS n GROUP BY id |> SELECT id, n",
    syntax_limits(),
  ).unwrap()
  let expected = compile(sql, fixture_context(), construction_limits()).unwrap()
  let actual = compile(pipe, fixture_context(), construction_limits()).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    _ => fail("Pipe aggregate failed the ordinary checker")
  }
}
