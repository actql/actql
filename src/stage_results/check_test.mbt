///|
fn prepared(
  body : String,
  effects? : String = "",
  reference_nullable? : Bool? = None,
) -> @parameters.CollectedOperations {
  let text = "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[" +
    "{\"id\":\"a\",\"inputs\":{\"rows\":{}},\"steps\":[],\"results\":{\"r\":" +
    body +
    "}" +
    effects +
    "}," +
    "{\"id\":\"b\",\"inputs\":{\"rows\":{}},\"steps\":[],\"results\":{\"r\":" +
    body +
    "}" +
    effects +
    "}]," +
    "\"results\":{\"out\":{\"from\":{\"stage\":\"b\",\"result\":\"r\"}}}}"
  let program = @syntax.parse(
    text,
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
  let source = @parameters.prepare(program, {
    max_parameters: 10,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
  let fields = [
    (
      @schema.Unqualified("amount"),
      @contract.primitive(NumberType, nullable=false),
    ),
  ]
  if reference_nullable is Some(nullable) {
    let reference = @contract.read_author(
      @decode.admit(
        @source.parse_json(
          "{\"type\":\"resource_ref\",\"nullable\":" +
          nullable.to_string() +
          ",\"resource_kind\":\"crm/account\"}",
          { max_input_bytes: 200, max_nodes: 10, max_depth: 4, },
        ).unwrap(),
        {
          max_nodes: 10,
          max_depth: 4,
          max_string_bytes: 200,
          max_total_string_bytes: 200,
        },
      ).unwrap(),
      { max_nodes: 10, max_depth: 4, max_text_bytes: 200, },
    ).unwrap()
    fields.push((@schema.Unqualified("ref"), reference))
  }
  let schema = @schema.from_fields(fields, max_fields=2, max_name_bytes=100).unwrap()
  let pipelines = []
  for i in 0..<@parameters.stage_count(source) {
    let body = @decode.open_object(
      @syntax.stage_body(@parameters.stage_at(source, i).unwrap()),
    ).unwrap()
    pipelines.push(
      @pipeline.check(
        @decode.required(body, "steps").unwrap(),
        [("rows", schema)],
        Some(@parameters.declarations(source)),
        None,
        {
          max_steps: 10,
          max_work: 10000,
          max_nodes: 10000,
          max_depth: 100,
          max_text_bytes: 10000,
          max_tokens: 1000,
        },
      ).unwrap(),
    )
  }
  @parameters.collect_operations(source, pipelines, {
    max_work: 10000,
    max_slots: 100,
    max_references: 100,
    max_pointer_units: 10000,
    max_direct_text_bytes: 10000,
  }).unwrap()
}

///|
fn limits() -> @results.Limits {
  {
    max_results: 100,
    max_work: 100000,
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 100,
  }
}

///|
test "source-bound stage Results preserve owners and share admission budgets" {
  let input = prepared(
    "{\"from\":\"rows\",\"fields\":[\"amount\"],\"meta\":{\"$param\":\"business-data\"}}",
  )
  let checked = check(input, limits()).unwrap()
  assert_true(physical_equal(operations(checked), input))
  for i in 0..<2 {
    let result = stage_at(checked, i).unwrap()
    assert_eq(@results.count(result), 1)
    assert_true(
      physical_equal(
        @results.pipeline(result),
        @collection.pipeline(
          @parameters.collection(
            @parameters.operations_stage_at(input, i).unwrap(),
          ),
        ),
      ),
    )
    let definition = @results.result_at(result, 0).unwrap()
    assert_true(@results.metadata(definition) is Some(_))
    assert_eq(@results.pending_validations(definition), [
      @results.TotalDeterministicOrder,
    ])
  }
  assert_true(stage_at(checked, -1) is None)
  assert_true(stage_at(checked, 2) is None)
  let used = usage(checked)
  assert_eq(used.results, 2)
  assert_true(used.work > @parameters.operations_usage(input).work)
  let exact : @results.Limits = {
    max_results: used.results,
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
    max_depth: limits().max_depth,
  }
  assert_true(check(input, exact) is Ok(_))
  for
    limit in [
      { ..exact, max_results: exact.max_results - 1, },
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
      { ..exact, max_depth: 0, },
    ] {
    assert_true(check(input, limit) is Err(_))
  }
  assert_true(check(input, { ..limits(), max_work: 0, }) is Err(WorkLimit))
  assert_true(
    check(input, { ..limits(), max_results: -1, }) is Err(InvalidLimits),
  )
}

///|
test "Result structural selectors cannot introduce Parameter holes" {
  for
    body in [
      "{\"from\":{\"$param\":\"p\"},\"fields\":[\"amount\"]}", "{\"from\":\"rows\",\"fields\":[{\"$param\":\"p\"}]}",
      "{\"from\":\"rows\",\"fields\":[\"amount\"],\"order_by\":[{\"field\":\"amount\",\"dir\":{\"$param\":\"p\"},\"nulls\":\"last\"}]}",
      "{\"from\":\"rows\",\"fields\":[\"amount\"],\"$param\":\"p\"}",
    ] {
    assert_true(check(prepared(body), limits()) is Err(Stage(0, _)))
  }
}
