///|
// Literal fixture identities independently hashed from sorted JSON with Python
// hashlib; no compiler output supplies an expected contract or environment CID.
fn infer_shorthand_environment() -> @check.CheckEnvironment {
  let wire = @environment.read(
    @utf8.encode(
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:d48cc3627d11eb81515fa52f4c9733159decff519a62c673a4c2e7997581a559","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_analytic_frame_memberships":1000,"max_analytic_input_wire_bytes":1000,"max_analytic_output_wire_bytes":1000,"max_analytic_partition_wire_bytes":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[{"authored_model_selector":"fixture-risk-model","connector_id":"models/fixture","contract_cid":"sha256:8f269aa69711da72cdd9f85aa193160bbb346a097ff32d1564e06329cefe631a","data_handling":{"accepted_classifications":["public","internal"],"allowed_regions":["fixture-region"],"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention":"none","training_use":"forbidden"},"generation_config":{"max_output_tokens":32,"seed_requested":-7,"temperature":0,"top_p":1},"input_contract":{"additional_properties":false,"fields":{"SELECT":{"nullable":false,"type":"string"},"n":{"nullable":false,"type":"number"},"text":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"input_schema_cid":"sha256:33e38fc7b487e1b7e6765fa80589ccdcf622813b74f4dd0292070820fb8064bc","max_items":2,"output_contract":{"additional_properties":false,"fields":{"reason":{"nullable":true,"type":"string"},"risk":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3","prompt_template_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retrieval_policy":"none","schema":"actql.model_task/0.1","streaming":false,"task_id":"model-task:risk-score.v1","task_kind":"structured_generate","tool_policy":"none","version":"1"}],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
      ),
    ),
    "sha256:d48cc3627d11eb81515fa52f4c9733159decff519a62c673a4c2e7997581a559",
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 10, },
  ).unwrap()
  let tasks = @environment.check_model_tasks(wire, {
    bodies: {
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
      max_members: 10,
    },
    contracts: { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
    max_work: 100000,
  }).unwrap()
  @check.checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    model_tasks=Some(tasks),
  )
}

///|
fn infer_shorthand_source(input : String) -> String {
  "SELECT DISTINCT 'a' AS id |> EXTEND 'urgent' AS text, 1 AS n, 'reserved' AS `SELECT` |> INFER `model-task:risk-score.v1` ITEM KEY (id) INPUT (" +
  input +
  ") KEEP (*) AS assessment"
}

///|
test "same-name mixed and quoted INFER inputs normalize to the same checked Program" {
  let environment = infer_shorthand_environment()
  let context = infer_member_context(environment)
  let expanded = compile_query_script(
    @query.parse_query_script(
      infer_shorthand_source("text = text, n = n, SELECT = `SELECT`"),
      syntax_limits(),
    ).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  // Expected ModelTask keys and source roles come from the independent fixture.
  assert_true(
    semantic(expanded).contains(
      "\"input\":{\"SELECT\":{\"field\":\"SELECT\"},\"n\":{\"field\":\"n\"},\"text\":{\"field\":\"text\"}}",
    ),
  )
  for
    input in [
      "text, n, `SELECT`", "text, n = n, `SELECT`", "`TeXt`, N, `SELECT`",
    ] {
    let actual = compile_query_script(
      @query.parse_query_script(infer_shorthand_source(input), syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expanded), msg=input)
    match @check.check_parsed(actual, environment, None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      NeedsInputs(_) => fail("closed Values and ModelTask control")
    }
  }
}

///|
test "INFER shorthand retains closed input schema and typed field refusals" {
  let environment = infer_shorthand_environment()
  let context = infer_member_context(environment)
  for
    (input, expected) in [
      ("text, n", @evidence.MissingInputRole("SELECT")),
      ("text, n, `SELECT`, id", @evidence.UnknownInputRole("id")),
    ] {
    let actual = compile_query_script(
      @query.parse_query_script(infer_shorthand_source(input), syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    guard @check.check_parsed(actual, environment, None, check_limits())
      is Rejected(error) else {
      fail(input)
    }
    assert_eq(@check.diagnostic_category(error), @check.InvalidInput)
    match @check.diagnostic_cause(error) {
      Source(SourceView(Program(Program(Pipeline(_, issue))))) =>
        assert_eq(issue.kind, @pipeline.Infer(expected))
      other => raise other
    }
  }
  assert_true(
    compile_query_script(
      @query.parse_query_script(
        infer_shorthand_source("text, TEXT = text, n, `SELECT`"),
        syntax_limits(),
      ).unwrap(),
      context,
      construction_limits(),
    )
    is Err(DuplicateOutput),
  )
  assert_true(
    compile_query_script(
      @query.parse_query_script(
        infer_shorthand_source("absent, n, `SELECT`"),
        syntax_limits(),
      ).unwrap(),
      context,
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}

///|
test "INFER shorthand wrong types are rejected by the existing ModelTask checker" {
  let environment = infer_shorthand_environment()
  let text = infer_shorthand_source("text, n, `SELECT`").replace(
    old="1 AS n",
    new="'wrong' AS n",
  )
  let actual = compile_query_script(
    @query.parse_query_script(
      text,
      syntax_limits(),
      source_path="wrong-type.sql",
    ).unwrap(),
    infer_member_context(environment),
    construction_limits(),
  ).unwrap()
  guard @check.check_parsed(actual, environment, None, check_limits())
    is Rejected(error) else {
    fail("wrong type was admitted")
  }
  assert_eq(@check.diagnostic_category(error), @check.InvalidInput)
  match @check.diagnostic_cause(error) {
    Source(SourceView(Program(Program(Pipeline(_, issue))))) =>
      assert_eq(
        issue.kind,
        @pipeline.Infer(@evidence.Expression(@typing.TypeMismatch("number"))),
      )
    other => raise other
  }
}

///|
test "unknown shorthand references retain original UTF-8 diagnostic ranges" {
  let environment = infer_member_environment()
  let text = "/*😀é*/\r\nFROM tickets |> ASSERT UNIQUE BY (id) |> INFER `model-task:risk-score.v1` ITEM KEY (id) INPUT (missing) KEEP (*) AS assessment"
  guard compile(
      @query.parse_query(text, syntax_limits(), source_path="original.sql").unwrap(),
      infer_input_field_context(environment),
      construction_limits(),
    )
    is Err(
      Expression({ issue: @expression.UnknownReference, origin: Some(origin), })
    ) else {
    fail("unknown reference")
  }
  let span = @origin.span(origin)
  assert_eq(span.source_path, "original.sql")
  assert_eq(span.start_byte, 108)
  assert_eq(span.end_byte, 115)
}
