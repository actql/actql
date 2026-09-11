///|
fn caps() -> Limits {
  { max_work: 10000, max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, }
}

///|
fn collect_caps() -> @collection.Limits {
  {
    max_work: 10000,
    max_slots: 100,
    max_references: 100,
    max_pointer_units: 10000,
    max_direct_text_bytes: 10000,
  }
}

///|
fn parsed() -> @stages.Source {
  let program = @syntax.parse(
    (
      #|{"version":"actql/0.1","id":"p","stages":[{"id":"s","inputs":{"a":{"carrier":"relation","schema":{"id":{"type":"number","nullable":false}},"primary_key":["id"]},"b":"relation"},"from":"a","steps":[],"results":{"out":{"from":"a","fields":["id"]}}}],"results":{"out":{"from":{"stage":"s","result":"out"}}}}
    ),
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
  @stages.prepare(program, {
    max_parameters: 10,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
}

///|
fn checked(
  source : @stages.Source,
  inputs : Array[(String, @pipeline.InputContract)],
) -> @stages.CollectedStage {
  let body = @decode.open_object(
    @syntax.stage_body(@stages.stage_at(source, 0).unwrap()),
  ).unwrap()
  let pipeline = @pipeline.check_with_evidence(
    @decode.required(body, "steps").unwrap(),
    inputs,
    Some(@stages.declarations(source)),
    @decode.lookup(body, "from"),
    {
      max_steps: 0,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @stages.collect(source, 0, pipeline, collect_caps()).unwrap()
}

///|
test "source local input handles survive pipeline registration and attach exactly" {
  let source = parsed()
  let prepared = prepare(source, 0, caps()).unwrap()
  assert_eq(count(prepared), 2)
  assert_true(physical_equal(@stage_local_inputs.source(prepared), source))
  let a = input_at(prepared, 0).unwrap()
  let b = input_at(prepared, 1).unwrap()
  let supplied = [b, a]
  let stage = checked(source, supplied)
  supplied.clear()
  let attached = attach(prepared, stage, max_work=100000).unwrap()
  assert_true(physical_equal(attached_inputs(attached), prepared))
  assert_true(physical_equal(attached_stage(attached), stage))
  assert_eq(
    attached_work(attached),
    usage(prepared).work + @stages.collection_work(stage) + 4,
  )
  assert_true(
    attach(prepared, stage, max_work=attached_work(attached)) is Ok(_),
  )
  assert_true(
    attach(prepared, stage, max_work=attached_work(attached) - 1)
    is Err(BudgetExceeded),
  )
  let pipeline = @collection.pipeline(@stages.collection(stage))
  guard a.1 is @pipeline.KeyedInput(key) else { fail("expected declared key") }
  assert_true(
    @pipeline.input_contract_at(pipeline, 1)
    is Some(@pipeline.KeyedInput(actual)) &&
    physical_equal(actual, key),
  )
  assert_true(@pipeline.input_contract_at(pipeline, -1) is None)
  assert_true(@pipeline.input_contract_at(pipeline, 2) is None)
  let reread = prepare(source, 0, caps()).unwrap()
  assert_true(attach(reread, stage, max_work=100000) is Err(ForeignInput("a")))
  let foreign = prepare(parsed(), 0, caps()).unwrap()
  assert_true(attach(foreign, stage, max_work=100000) is Err(ForeignStage))
}

///|
test "equal Carrier types cannot substitute for declared keys or source handles" {
  let source = parsed()
  let prepared = prepare(source, 0, caps()).unwrap()
  let (name, declaration) = entry_at(prepared, 0).unwrap()
  let b = input_at(prepared, 1).unwrap()
  let without_key = checked(source, [
    (name, @pipeline.CarrierInput(@local_input.carrier(declaration))),
    b,
  ])
  assert_true(
    attach(prepared, without_key, max_work=100000) is Err(ForeignInput("a")),
  )
  let key = @local_input.primary_key(declaration).unwrap()
  let candidate_registration = checked(source, [
    (name, @pipeline.CandidateKeysInput(@evidence.singleton_key(key))),
    b,
  ])
  assert_true(
    attach(prepared, candidate_registration, max_work=100000)
    is Err(ForeignInput("a")),
  )
  let same_fields = @carrier.relation(
    @carrier.typed_rows(
      @carrier.complete_schema(
        @carrier.relation_rows(@local_input.carrier(declaration)).unwrap(),
      ).unwrap(),
    ),
  )
  let substituted = checked(source, [
    input_at(prepared, 0).unwrap(),
    ("b", @pipeline.CarrierInput(same_fields)),
  ])
  assert_true(
    attach(prepared, substituted, max_work=100000) is Err(ForeignInput("b")),
  )
  assert_true(attach(prepared, without_key, max_work=-1) is Err(InvalidLimits))
}

///|
test "all local declarations share exact source budgets" {
  let source = parsed()
  let prepared = prepare(source, 0, caps()).unwrap()
  let used = usage(prepared)
  let exact = {
    ..caps(),
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
  }
  assert_true(prepare(source, 0, exact) is Ok(_))
  for
    limits in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_nodes: used.nodes - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
      { ..exact, max_depth: 1, },
      { ..exact, max_work: -1, },
    ] {
    assert_true(prepare(source, 0, limits) is Err(_))
  }
  assert_true(prepare(source, -1, caps()) is Err(InvalidStage))
  assert_true(prepare(source, 1, caps()) is Err(InvalidStage))
  assert_true(input_at(prepared, -1) is None)
  assert_true(entry_at(prepared, 2) is None)
  assert_eq(stage_index(prepared), 0)
}

///|
test "import declarations remain owned by their separate passes" {
  let program = @syntax.parse(
    (
      #|{"version":"actql/0.1","id":"p","stages":[{"id":"s","inputs":{"unsupported":"events"},"steps":[],"results":{"out":{}},"effects":{"e":{}}},{"id":"t","inputs":{"r":{"result":{"stage":"s","result":"out"}},"receipt":{"receipt":{"stage":"s","effect":"e"}},"rows":"relation"},"steps":[],"results":{"out":{}}}],"results":{"out":{"from":{"stage":"t","result":"out"}}}}
    ),
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
  let source = @stages.prepare(program, {
    max_parameters: 10,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
  assert_true(
    prepare(source, 0, caps())
    is Err(
      Declaration("unsupported", @local_input.UnsupportedCarrier("events"))
    ),
  )
  let second = prepare(source, 1, caps()).unwrap()
  assert_eq(count(second), 1)
  assert_eq(entry_at(second, 0).unwrap().0, "rows")
  assert_eq(usage(second).work, 6)
  assert_eq(usage(second).nodes, 1)
  assert_eq(usage(second).text_bytes, 8)
}
