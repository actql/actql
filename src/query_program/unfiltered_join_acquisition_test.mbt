///|
// Pure checked preparation: no Source read, Account grant or physical Run.
fn check_pair_acquisitions(
  program : @program.Program,
  environment : @check.CheckEnvironment,
  supplied : @wire.Cursor?,
  expected_names : Array[String],
  expected_schema : @schema.Schema,
) -> @publication_host.PreparedClientProgram raise {
  let prepared = match
    @publication_host.prepare_parsed_effect_free_client_program(
      program,
      environment,
      supplied,
      @publication_host.client_standard_program_preparation_limits(),
    ) {
    Ok(value) => value
    Err(Check(issue)) => raise @check.diagnostic_cause(issue)
    Err(NeedsInputs(requests)) => {
      let names = []
      for index in 0..<@check.input_request_count(requests) {
        names.push(
          match @check.input_request_at(requests, index).unwrap().kind {
            HostCapacityPolicy => "host capacity"
            ParameterValue(_) => "parameter"
            _ => "other"
          },
        )
      }
      fail("required originals: " + names.join(","))
    }
    Err(Graph(issue)) => fail("graph: " + @debug.to_string(issue))
    Err(_) => fail("preparation outside check/graph")
  }
  assert_eq(@publication_host.prepared_client_acquisition_count(prepared), 2)
  // None of these callers authors TRUE, even when another predicate is real.
  // One Source must not regain an invented Query while the other stays Whole.
  assert_false(semantic(program).contains("\"filter\":{\"literal\":true}"))
  let staged = @stage_parameters.prepare(program, {
    max_parameters: 100,
    max_nodes: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  }).unwrap()
  let originals = @sourceviews.collect(staged, {
    max_work: 100000,
    max_order_keys: 100,
  }).unwrap()
  let counts : Map[Int, Int] = Map([])
  let mut count = 0
  let mut whole_count = 0
  let names = []
  for index in 0..<@sourceviews.count(originals) {
    let original = @sourceviews.at(originals, index).unwrap()
    let source_index = counts.get(original.stage_index).unwrap_or(0)
    let acquisition = @publication_host.prepare_client_source_acquisition(
      prepared,
      original.stage_index,
      source_index,
    ).unwrap()
    assert_true(
      @publication_host.client_source_acquisition_matches_program(
        prepared,
        original.stage_index,
        source_index,
        acquisition,
      ),
    )
    let target = @source_resolution.source_acquisition_input(acquisition)
    guard target is @pipeline.Input(input_index) else {
      fail("Source acquisition must retain its actual input binding")
    }
    let pipeline = @source_resolution.source_acquisition_pipeline(acquisition)
    let (name, _) = @pipeline.input_at(pipeline, input_index).unwrap()
    assert_eq(name, original.input_name)
    names.push(name)
    let schema = @pipeline.schema_at(pipeline, target).unwrap()
    assert_eq(@schema.field_count(schema), @schema.field_count(expected_schema))
    for field_index in 0..<@schema.field_count(expected_schema) {
      let actual = @schema.field_at(schema, field_index).unwrap()
      let expected = @schema.field_at(expected_schema, field_index).unwrap()
      assert_eq(actual.name, expected.name)
      assert_eq(actual.presence, expected.presence)
      assert_true(@contract.type_equal(actual.contract, expected.contract, 100))
    }
    match
      @source_resolution.source_acquisition_route(acquisition, 1000000).unwrap() {
      WholeInputRoute(selected) => {
        whole_count += 1
        assert_true(physical_equal(selected, acquisition))
        assert_true(
          @publication_host.prepare_client_query_acquisition(
            prepared,
            original.stage_index,
            source_index,
          )
          is Err(UnsupportedAcquisition(@source_resolution.UnsupportedShape)),
        )
      }
      QueryRoute(query) => {
        assert_true(
          physical_equal(
            @source_resolution.query_acquisition_owner(query),
            @source_resolution.source_acquisition_owner(acquisition),
          ),
        )
        assert_eq(@source_resolution.query_acquisition_input(query), target)
        assert_eq(@source_resolution.query_acquisition_filter_index(query), 0)
        assert_true(
          @source_resolution.query_acquisition_capture(query)
          is @pipeline.Step(1),
        )
      }
    }
    counts[original.stage_index] = source_index + 1
    count += 1
  }
  assert_eq(count, 2)
  assert_true(whole_count > 0)
  assert_eq(names, expected_names)
  prepared
}

///|
fn direct_pair_context() -> Context {
  let base = chain_right_context(direct=true, captured=true, parameters=false)
  let original = base.inputs[0]
  {
    ..base,
    inputs: [
      original,
      {
        ..original,
        name: "second",
        relation: [{ value: "second", quoted: false, }],
      },
    ],
    input_schemas: [base.input_schemas[0], ("second", base.input_schemas[0].1)],
  }
}

///|
test "unfiltered SQL and Pipe JOIN retain two independent Source acquisitions" {
  let environment = @check.checking_environment(
    chain_right_wire(host_capacity=true),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let context = direct_pair_context()
  for
    text in [
      "SELECT l.id AS id FROM remote AS l JOIN second AS r ON l.id = r.id MAX_OUTPUT_ROWS 4",
      "FROM remote AS l |> JOIN second AS r ON l.id = r.id MAX_OUTPUT_ROWS 4 |> SELECT l.id AS id",
    ] {
    let program = compile_query_script(
      @query.parse_query_script(text, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    check_pair_acquisitions(
      program,
      environment,
      None,
      ["remote", "second"],
      context.input_schemas[0].1,
    )
    |> ignore
  }
}

///|
test "simple JOIN preserves keyed right occurrence instead of direct capture" {
  let query = "FROM (SELECT 1 AS id) AS l |> JOIN remote AS r ON l.id = r.id MAX_OUTPUT_ROWS 4 |> SELECT l.id AS id"
  let program = compile_query_script(
    @query.parse_query_script(query, syntax_limits()).unwrap(),
    chain_right_context(direct=false, captured=true, parameters=false),
    construction_limits(),
  ).unwrap()
  assert_eq(@program.stage_count(program), 1)
  assert_true(semantic(program).contains("\"with\":\"remote\""))
  assert_false(semantic(program).contains("\"id\":\"capture\""))
}

///|
test "independent JOIN acquisition preserves authored parameter identity" {
  let base = direct_pair_context()
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"minimum\":{\"type\":\"number\",\"nullable\":false}}",
      ),
    ),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let context = { ..base, parameter_declarations: Some(declarations), }
  let program = compile_query_script(
    @query.parse_query_script(
      "FROM remote AS l |> WHERE l.id > @minimum |> JOIN second AS r ON l.id = r.id MAX_OUTPUT_ROWS 4 |> WHERE r.extra > 0 |> SELECT l.id AS id",
      syntax_limits(),
    ).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  let environment = @check.checking_environment(
    chain_right_wire(host_capacity=true),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let first = check_pair_acquisitions(
    program,
    environment,
    Some(from_unpivot_public_cursor("{\"minimum\":0}")),
    ["remote", "second"],
    base.input_schemas[0].1,
  )
  let second = check_pair_acquisitions(
    program,
    environment,
    Some(from_unpivot_public_cursor("{\"minimum\":1}")),
    ["remote", "second"],
    base.input_schemas[0].1,
  )
  let first_identity = @publication_host.prepared_client_identity(first)
  let second_identity = @publication_host.prepared_client_identity(second)
  assert_eq(
    first_identity.program_definition_cid,
    second_identity.program_definition_cid,
  )
  assert_not_eq(
    first_identity.parameter_values_cid,
    second_identity.parameter_values_cid,
  )
  assert_true(semantic(program).contains("\"$param\":\"minimum\""))
}

///|
test "unfiltered scan JOIN captures both Sources before local computation" {
  let environment = source_infer_member_environment()
  let base = source_infer_member_context(environment)
  let original = { ..base.inputs[0], visible_fields: ["id"], }
  let context = {
    ..base,
    captured_stage: Some("capture"),
    inputs: [
      original,
      {
        ..original,
        name: "second",
        relation: [{ value: "second", quoted: false, }],
      },
    ],
    input_schemas: [base.input_schemas[0], ("second", base.input_schemas[0].1)],
  }
  let program = compile_query_script(
    @query.parse_query_script(
      "SELECT l.id AS id FROM objects AS l JOIN second AS r ON l.id = r.id MAX_OUTPUT_ROWS 4",
      syntax_limits(),
    ).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  check_pair_acquisitions(
    program,
    environment,
    None,
    ["objects", "second"],
    base.input_schemas[0].1,
  )
  |> ignore
}
