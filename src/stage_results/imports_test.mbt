///|
fn import_fixture() -> (
  @parameters.Source,
  @parameters.CollectedStage,
  @results.ResultPorts,
) {
  let program = @syntax.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"a\",\"inputs\":{\"rows\":{}},\"steps\":[],\"results\":{\"r\":{\"from\":\"rows\",\"fields\":[\"amount\"]}}},{\"id\":\"b\",\"inputs\":{\"first\":{\"result\":{\"stage\":\"a\",\"result\":\"r\"}},\"second\":{\"result\":{\"stage\":\"a\",\"result\":\"r\"}}},\"from\":\"first\",\"steps\":[{\"take\":1}],\"results\":{\"r\":{\"from\":\"first\",\"fields\":[\"amount\"]}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"b\",\"result\":\"r\"}}}}",
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
  let body = @decode.open_object(
    @syntax.stage_body(@parameters.stage_at(source, 0).unwrap()),
  ).unwrap()
  let schema = @schema.from_fields(
    [
      (
        @schema.Unqualified("amount"),
        @contract.primitive(NumberType, nullable=false),
      ),
    ],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let pipeline = @pipeline.check(
    @decode.required(body, "steps").unwrap(),
    [("rows", schema)],
    Some(@parameters.declarations(source)),
    None,
    import_pipeline_limits(),
  ).unwrap()
  let stage = @parameters.collect(source, 0, pipeline, {
    max_work: 10000,
    max_slots: 100,
    max_references: 100,
    max_pointer_units: 10000,
    max_direct_text_bytes: 10000,
  }).unwrap()
  let checked = @results.check(
    pipeline,
    @decode.required(body, "results").unwrap(),
    limits(),
  ).unwrap()
  (source, stage, import_ports(checked))
}

///|
fn import_pipeline_limits() -> @pipeline.Limits {
  {
    max_steps: 100,
    max_work: 100000,
    max_nodes: 10000,
    max_depth: 100,
    max_text_bytes: 10000,
    max_tokens: 1000,
  }
}

///|
fn import_ports(checked : @results.CheckedResults) -> @results.ResultPorts {
  let orders = @results.resolve_all_orders(checked, {
    max_steps: 100,
    max_results: 100,
    max_work: 100000,
    max_text_bytes: 100000,
  }).unwrap()
  @results.prepare_ports(orders, {
    max_results: 100,
    max_work: 100000,
    max_nodes: 10000,
    max_text_bytes: 100000,
    max_depth: 100,
  }).unwrap()
}

///|
test "Result imports retain repeated named ports and source-bound downstream steps" {
  let (source, stage, ports) = import_fixture()
  let owner = bind_ports(stage, ports).unwrap()
  let supplied = [owner]
  let result = resolve_imports(source, 1, supplied, {
    max_work: 100,
    max_imports: 10,
    max_text_bytes: 1000,
  }).unwrap()
  supplied.clear()
  assert_true(physical_equal(import_source(result), source))
  assert_eq(import_stage(result), 1)
  assert_eq(import_count(result), 2)
  let first = import_at(result, 0).unwrap()
  let second = import_at(result, 1).unwrap()
  assert_true(physical_equal(input_port(first), input_port(second)))
  assert_true(physical_equal(input_stage(first), owner))
  assert_true(physical_equal(stage_port_source(owner), stage))
  assert_true(physical_equal(stage_port_publications(owner), ports))
  assert_true(input_name(first) != input_name(second))
  let inputs = []
  for i in 0..<import_count(result) {
    let entry = import_at(result, i).unwrap()
    inputs.push(
      (input_name(entry), @pipeline.ProducedInput(input_producer(entry))),
    )
  }
  let body = @decode.open_object(
    @syntax.stage_body(@parameters.stage_at(source, 1).unwrap()),
  ).unwrap()
  let pipeline = @pipeline.check_with_evidence(
    @decode.required(body, "steps").unwrap(),
    inputs,
    Some(@parameters.declarations(source)),
    @decode.lookup(body, "from"),
    import_pipeline_limits(),
  ).unwrap()
  assert_true(@pipeline.take_order(pipeline, 0) is Some(_))
  let collection_limits : @collection.Limits = {
    max_work: 10000,
    max_slots: 100,
    max_references: 100,
    max_pointer_units: 10000,
    max_direct_text_bytes: 10000,
  }
  let consumer = @parameters.collect(source, 1, pipeline, collection_limits).unwrap()
  let attached = attach_imports(result, consumer, max_work=100).unwrap()
  assert_true(physical_equal(attached_imports(attached), result))
  assert_true(physical_equal(attached_stage(attached), consumer))
  assert_true(
    attach_imports(result, consumer, max_work=attached_work(attached)) is Ok(_),
  )
  assert_true(
    attach_imports(result, consumer, max_work=attached_work(attached) - 1)
    is Err(BudgetExceeded),
  )
  assert_true(attach_imports(result, stage, max_work=100) is Err(InvalidStage))
  let (_, _, foreign_ports) = import_fixture()
  inputs[0] = (
    inputs[0].0,
    @pipeline.ProducedInput(
      @results.port_input(@results.lookup_port(foreign_ports, "r").unwrap()),
    ),
  )
  let replaced = @pipeline.check_with_evidence(
    @decode.required(body, "steps").unwrap(),
    inputs,
    Some(@parameters.declarations(source)),
    @decode.lookup(body, "from"),
    import_pipeline_limits(),
  ).unwrap()
  let replaced_stage = @parameters.collect(
    source, 1, replaced, collection_limits,
  ).unwrap()
  assert_true(
    attach_imports(result, replaced_stage, max_work=100) is Err(ForeignInput(_)),
  )
  let (work, text) = import_usage(result)
  let exact : ImportLimits = {
    max_work: work,
    max_imports: 2,
    max_text_bytes: text,
  }
  assert_true(resolve_imports(source, 1, [owner], exact) is Ok(_))
  for
    cap in [
      { ..exact, max_work: work - 1, },
      { ..exact, max_imports: 1, },
      { ..exact, max_text_bytes: text - 1, },
    ] {
    assert_true(resolve_imports(source, 1, [owner], cap) is Err(BudgetExceeded))
  }
  assert_true(import_at(result, -1) is None)
  assert_true(import_at(result, 2) is None)
}

///|
test "Result imports reject substituted source owners and incomplete producer registries" {
  let (source, stage, ports) = import_fixture()
  let (other_source, other_stage, other_ports) = import_fixture()
  let owner = bind_ports(stage, ports).unwrap()
  let cap : ImportLimits = {
    max_work: 100,
    max_imports: 10,
    max_text_bytes: 1000,
  }
  assert_true(bind_ports(stage, other_ports) is Err(ForeignPipeline))
  let other_body = @decode.open_object(
    @syntax.stage_body(@parameters.stage_at(other_source, 0).unwrap()),
  ).unwrap()
  let substituted = @results.check(
    @collection.pipeline(@parameters.collection(stage)),
    @decode.required(other_body, "results").unwrap(),
    limits(),
  ).unwrap()
  assert_true(
    bind_ports(stage, import_ports(substituted)) is Err(ForeignResults),
  )
  assert_true(
    resolve_imports(
      source,
      1,
      [bind_ports(other_stage, other_ports).unwrap()],
      cap,
    )
    is Err(ForeignSource),
  )
  assert_true(
    resolve_imports(source, 0, [owner], cap) is Err(NotEarlierStage(0)),
  )
  assert_true(resolve_imports(source, 1, [], cap) is Err(MissingProducer("a")))
  assert_true(
    resolve_imports(source, 1, [owner, owner], cap)
    is Err(DuplicateProducer("a")),
  )
  assert_true(resolve_imports(source, -1, [], cap) is Err(InvalidStage))
  assert_true(
    resolve_imports(source, 1, [owner], { ..cap, max_work: -1, })
    is Err(InvalidLimits),
  )
}
