///|
fn local_program_source(
  two_stages : Bool,
  bad_later? : Bool = false,
  untyped? : Bool = false,
) -> @parameters.Source {
  let first =
    #|{"id":"first","inputs":{"rows":{"carrier":"relation","schema":{"id":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"derive":{"extra":"id + 1"},"as":"prepared"}],"results":{"out":{"from":"prepared","fields":["id","extra"]}}}
  let second =
    #|{"id":"second","inputs":{"a":{"result":{"stage":"first","result":"out"}},"unused":{"result":{"stage":"first","result":"out"}}},"from":"a","steps":[{"derive":{"more":"extra + 1"},"as":"prepared"}],"results":{"out":{"from":"prepared","fields":["id","more"]}}}
  let second = if bad_later {
    second.replace(old="extra + 1", new="missing + 1")
  } else {
    second
  }
  let text = "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[" +
    first +
    (if two_stages { "," + second } else { "" }) +
    "],\"results\":{\"out\":{\"from\":{\"stage\":\"" +
    (if two_stages { "second" } else { "first" }) +
    "\",\"result\":\"out\"}}}}"
  local_program_parse(
    if untyped {
      text.replace(
        old="{\"carrier\":\"relation\",\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"primary_key\":[\"id\"]}",
        new="\"relation\"",
      )
    } else {
      text
    },
  )
}

///|
fn local_program_parse(text : String) -> @parameters.Source {
  let program = @syntax.parse(
    text,
    {
      source: { max_input_bytes: 100000, max_nodes: 10000, max_depth: 100, },
      tree: {
        max_nodes: 10000,
        max_depth: 100,
        max_string_bytes: 100000,
        max_total_string_bytes: 100000,
      },
      max_stages: 100,
    },
    format=Json,
  ).unwrap()
  @parameters.prepare(program, {
    max_parameters: 100,
    max_nodes: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  }).unwrap()
}

///|
fn local_program_limits() -> LocalProgramLimits {
  {
    max_stages: 100,
    max_steps: 100,
    max_results: 100,
    max_work: 1000000,
    max_nodes: 100000,
    max_tokens: 100000,
    max_text_bytes: 1000000,
    max_depth: 100,
  }
}

///|
test "local Program preparation constructs source-owned pipelines and Result ports" {
  for multiple in [false, true] {
    let source = local_program_source(multiple)
    let (wired, used) = prepare_local_program(source, local_program_limits()).unwrap()
    assert_true(physical_equal(wiring_source(wired), source))
    assert_eq(used.steps, if multiple { 2 } else { 1 })
    assert_eq(used.results, used.steps)
    assert_eq(export_count(wired), 1)
    let owner = wiring_stage_at(wired, used.steps - 1).unwrap()
    assert_true(
      physical_equal(export_stage(export_at(wired, 0).unwrap()), owner),
    )
    let pipeline = @collection.pipeline(
      @parameters.collection(stage_port_source(owner)),
    )
    assert_eq(@pipeline.step_count(pipeline), 1)
    assert_eq(@pipeline.lookup(pipeline, "prepared"), Some(@pipeline.Step(0)))
    let output = @pipeline.output_schema(pipeline).unwrap()
    let added = if multiple { "more" } else { "extra" }
    assert_true(
      @contract.type_equal(
        @schema.lookup(output, @schema.Unqualified(added)).unwrap(),
        @contract.primitive(NumberType, nullable=false),
        100,
      ),
    )
    assert_true(
      @contract.type_equal(
        @schema.lookup(output, @schema.Unqualified("id")).unwrap(),
        @contract.primitive(NumberType, nullable=false),
        100,
      ),
    )
    if multiple {
      let resolved = attached_imports(wiring_imports_at(wired, 1).unwrap())
      assert_eq(import_count(resolved), 2)
      for i in 0..<2 {
        let imported = import_at(resolved, i).unwrap()
        assert_true(
          physical_equal(
            input_stage(imported),
            wiring_stage_at(wired, 0).unwrap(),
          ),
        )
        let index = match
          @pipeline.lookup(pipeline, input_name(imported)).unwrap() {
          @pipeline.Input(index) => index
          _ => {
            fail("expected imported input")
            0
          }
        }
        assert_true(
          physical_equal(
            @pipeline.input_producer(pipeline, index).unwrap(),
            input_producer(imported),
          ),
        )
      }
    }
    // Repeating preparation does not reuse an equal-shaped publication owner.
    let (other, _) = prepare_local_program(source, local_program_limits()).unwrap()
    assert_false(
      physical_equal(
        stage_port_publications(owner),
        stage_port_publications(wiring_stage_at(other, used.steps - 1).unwrap()),
      ),
    )
  }
}

///|
test "local Program preparation bills all stages and retained prefixes exactly once" {
  for multiple in [false, true] {
    let source = local_program_source(multiple)
    let (_, used) = prepare_local_program(source, local_program_limits()).unwrap()
    let exact = {
      ..local_program_limits(),
      max_stages: used.steps,
      max_steps: used.steps,
      max_results: used.results,
      max_work: used.work,
      max_nodes: used.nodes,
      max_tokens: used.tokens,
      max_text_bytes: used.text_bytes,
    }
    let (_, again) = prepare_local_program(source, exact).unwrap()
    assert_eq(used, again)
    for
      cap in [
        { ..exact, max_stages: exact.max_stages - 1, },
        { ..exact, max_steps: exact.max_steps - 1, },
        { ..exact, max_results: exact.max_results - 1, },
        { ..exact, max_work: exact.max_work - 1, },
        { ..exact, max_nodes: exact.max_nodes - 1, },
        { ..exact, max_tokens: exact.max_tokens - 1, },
        { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
        { ..exact, max_depth: 0, },
      ] {
      assert_true(prepare_local_program(source, cap) is Err(_))
    }
    assert_true(
      prepare_local_program(source, { ..exact, max_work: -1, })
      is Err(InvalidLimits),
    )
  }
}

///|
test "local Program preparation rejects late failures and unsupported receipt inputs" {
  let invalid = local_program_source(true, bad_later=true)
  assert_true(
    prepare_local_program(invalid, local_program_limits())
    is Err(Pipeline(1, _)),
  )
  // Receipt imports must not disappear just because resolve_imports handles
  // Result ports only. Their separate admission boundary has not run here.
  let receipts = local_program_parse(
    (
      #|{"version":"actql/0.1","id":"p","stages":[{"id":"a","inputs":{"r":{"carrier":"relation","schema":{"id":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[],"effects":{"e":{}},"results":{"r":{"from":"r","fields":["id"]}}},{"id":"b","inputs":{"r":{"receipt":{"stage":"a","effect":"e"}}},"steps":[],"results":{"r":{"from":"r","fields":["id"]}}}],"results":{"out":{"from":{"stage":"b","result":"r"}}}}
    ),
  )
  assert_true(
    prepare_local_program(receipts, local_program_limits())
    is Err(UnsupportedReceipt(1, "r")),
  )
}

///|
test "local Program preparation does not skip unused invalid local declarations" {
  let source = local_program_parse(
    (
      #|{"version":"actql/0.1","id":"p","stages":[{"id":"s","inputs":{"rows":{"carrier":"relation","schema":{"id":{"type":"number","nullable":false}},"primary_key":["id"]},"unused":{"carrier":"relation","schema":{"bad":{"type":"decimal","precision":1,"scale":2,"nullable":false}}}},"from":"rows","steps":[],"results":{"r":{"from":"rows","fields":["id"]}}}],"results":{"out":{"from":{"stage":"s","result":"r"}}}}
    ),
  )
  assert_true(
    prepare_local_program(source, local_program_limits())
    is Err(LocalInput(0, _)),
  )
}

///|
test "local Program wiring retains input proofs and the same stages in whole-Program collection" {
  let source = local_program_source(true)
  let (wired, _) = prepare_local_program(source, local_program_limits()).unwrap()
  let stages = []
  for i in 0..<2 {
    let stage = stage_port_source(wiring_stage_at(wired, i).unwrap())
    let attachment = wiring_local_input_at(wired, i).unwrap()
    assert_true(physical_equal(@local.attached_stage(attachment), stage))
    let inputs = @local.attached_inputs(attachment)
    assert_true(physical_equal(@local.source(inputs), source))
    assert_eq(@local.stage_index(inputs), i)
    assert_eq(@local.count(inputs), if i == 0 { 1 } else { 0 })
    stages.push(stage)
  }
  let operations = @parameters.collect_prepared_operations(source, stages, {
    max_work: 1000000,
    max_slots: 100,
    max_references: 100,
    max_pointer_units: 100000,
    max_direct_text_bytes: 100000,
  }).unwrap()
  for i in 0..<2 {
    assert_true(
      physical_equal(
        @parameters.operations_stage_at(operations, i).unwrap(),
        @local.attached_stage(wiring_local_input_at(wired, i).unwrap()),
      ),
    )
  }
  let publications = []
  for i in 0..<2 {
    publications.push(
      @results.publication_orders_results(
        @results.checked_publication_orders(
          @results.ports_orders(
            stage_port_publications(wiring_stage_at(wired, i).unwrap()),
          ),
        ),
      ),
    )
  }
  let all_results = collect_checked(operations, publications, {
    max_results: 2,
    max_work: 1000000,
    max_nodes: 100000,
    max_text_bytes: 100000,
  }).unwrap()
  for i in 0..<2 {
    assert_true(
      physical_equal(stage_at(all_results, i).unwrap(), publications[i]),
    )
  }
  stages.clear()
  assert_true(wiring_local_input_at(wired, -1) is None)
  assert_true(wiring_local_input_at(wired, 2) is None)
  let (generic_source, generic_stages, generic_imports) = wiring_fixture()
  let generic = wire_results(
    generic_source,
    generic_stages,
    generic_imports,
    wiring_limits(),
  ).unwrap()
  assert_true(wiring_local_input_at(generic, 0) is None)
}
