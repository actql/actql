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
    inputs: [
      {
        relation: [{ value: "orders", quoted: false, }],
        name: "orders",
        declaration,
      },
    ],
  }
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
        stages: 2,
        steps: 20,
        results: 2,
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
fn check_environment() -> @check.CheckEnvironment {
  let cid = "sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904"
  let wire = @environment.read(
    @utf8.encode(
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
      ),
    ),
    cid,
    { max_bytes: 10000, max_nodes: 1000, max_depth: 100, max_members: 10, },
  ).unwrap()
  @check.checking_environment(wire, { text_time: false, veca: false, }, {
    rela: true,
    sga: false,
    tea: false,
    calendar: false,
    text_rank: false,
  })
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
}
