///|
fn prefix_control_source(
  required_order? : Bool = false,
  bad_type? : Bool = false,
) -> @parameters.Source {
  // Independent input: a real capture with nullable object evidence followed
  // by an unfinished consumer. No unit Relation or synthetic Result is added.
  let text =
    #|{"version":"actql/0.1","id":"prefix","stages":[{"id":"capture","inputs":{"rows":{"carrier":"relation","schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}}}}},"steps":[{"from":"rows","filter":{"literal":true}},{"select":["id","payload"],"as":"saved"}],"results":{"out":{"from":"saved","fields":["id","payload"]}}},{"id":"open","inputs":{"a":{"result":{"stage":"capture","result":"out"}},"b":{"result":{"stage":"capture","result":"out"}}},"from":"a","steps":[{"derive":{"n":{"literal":1}},"as":"prefix"}],"results":{}}],"results":{}}
  let text = if required_order {
    text.replace(
      old="{\"derive\":{\"n\":{\"literal\":1}},\"as\":\"prefix\"}",
      new="{\"take\":1,\"as\":\"prefix\"}",
    )
  } else {
    text
  }
  let text = if bad_type {
    text.replace(old="{\"literal\":true}", new="{\"literal\":1}")
  } else {
    text
  }
  prefix_control_parse(text)
}

///|
fn prefix_control_parse(text : String) -> @parameters.Source {
  let caps : @syntax.Limits = {
    source: { max_input_bytes: 100000, max_nodes: 10000, max_depth: 100, },
    tree: {
      max_nodes: 10000,
      max_depth: 100,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    },
    max_stages: 100,
  }
  let document = @origin.document(text, caps.source.max_input_bytes, source_path="prefix-control.aql").unwrap()
  let builder = @builder.create(document, {
    source: caps.source,
    tree: caps.tree,
    max_origin_entries: 100000,
    max_output_bytes: 1000000,
  }).unwrap()
  let parsed = @source.parse_json_measured(text, caps.source, source_path="prefix-control.aql").unwrap()
  let generated = @builder.finish(
    builder,
    @builder.import_parsed(builder, parsed).unwrap(),
  ).unwrap()
  let prefix = @syntax.admit_generated_prefix(generated, caps).unwrap()
  @parameters.prepare_prefix(prefix, {
    max_parameters: 100,
    max_nodes: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  }).unwrap()
}

///|
test "check-only prefix preserves capture projection imports and unresolved debts" {
  let source = prefix_control_source()
  assert_true(@parameters.complete_program(source) is None)
  assert_true(@parameters.prefix(source) is Some(_))
  let (topology, used) = check_local_program(source, local_program_limits()).unwrap()
  assert_true(physical_equal(topology_source(topology), source))
  assert_eq(used, topology_usage(topology))
  assert_eq(used.steps, 3)
  assert_eq(used.results, 1)
  assert_eq(topology_export_count(topology), 0)
  let capture = topology_stage_at(topology, 0).unwrap()
  let results = topology_stage_results(capture)
  let definition = @results.result_at(
    @results.checked_inputs_results(results),
    0,
  ).unwrap()
  assert_eq(@results.pending_validations(definition), [
    @results.TotalDeterministicOrder,
  ])
  let projected = @results.checked_input_at(results, 0).unwrap()
  let producer = @collection.pipeline(
    @parameters.collection(topology_stage_source(capture)),
  )
  assert_true(physical_equal(@pipeline.producer_pipeline(projected), producer))
  assert_eq(@pipeline.producer_target(projected), Step(1))
  assert_true(@pipeline.producer_projection(projected) is Some(_))
  let consumer = topology_stage_at(topology, 1).unwrap()
  assert_eq(
    @results.count(
      @results.checked_inputs_results(topology_stage_results(consumer)),
    ),
    0,
  )
  let pipeline = @collection.pipeline(
    @parameters.collection(topology_stage_source(consumer)),
  )
  let imports = topology_imports_at(topology, 1).unwrap()
  assert_eq(topology_import_count(imports), 2)
  for i in 0..<2 {
    let edge = topology_import_at(imports, i).unwrap()
    assert_true(physical_equal(topology_input_stage(edge), capture))
    assert_true(physical_equal(topology_input_producer(edge), projected))
    assert_true(
      physical_equal(@pipeline.input_producer(pipeline, i).unwrap(), projected),
    )
  }
  let steps = @decode.required(
    @decode.open_object(
      @syntax.stage_body(@parameters.stage_at(source, 1).unwrap()),
    ).unwrap(),
    "steps",
  ).unwrap()
  // Cursors are views, so compare owned-tree coordinates rather than wrapper
  // allocation. A foreign tree cannot discharge this ownership check.
  assert_eq(@decode.tree_index(steps, @pipeline.source(pipeline)),
    @decode.tree_index(steps, steps))
  assert_true(
    prepare_local_program(source, local_program_limits())
    is Err(CheckOnlyPrefix),
  )
  assert_true(
    wire_results(source, [], [], {
      max_work: 100,
      max_text_bytes: 100,
      max_imports: 100,
      max_exports: 100,
    })
    is Err(CheckOnlyPrefix),
  )
}

///|
test "prefix checks unused type failures and operation required order" {
  guard check_local_program(
      prefix_control_source(bad_type=true),
      local_program_limits(),
    )
    is Err(Pipeline(0, issue)) else {
    fail("unused capture is still typed")
  }
  assert_eq(@decode.cursor_path(issue.source), [
    Key("stages"),
    Index(0),
    Key("steps"),
    Index(0),
    Key("filter"),
  ])
  guard check_local_program(
      prefix_control_source(required_order=true),
      local_program_limits(),
    )
    is Err(Order(1, PipelineOrder(issue))) else {
    fail("take cannot defer input order")
  }
  assert_eq(issue.kind, @pipeline.UnresolvedOrder)
}

///|
test "prefix check preserves bounded accounting and actual local ownership" {
  let source = prefix_control_source()
  let (topology, used) = check_local_program(source, local_program_limits()).unwrap()
  assert_true(topology_local_input_at(topology, 0) is Some(_))
  let exact = {
    ..local_program_limits(),
    max_work: used.work,
    max_nodes: used.nodes,
    max_tokens: used.tokens,
    max_text_bytes: used.text_bytes,
    max_steps: used.steps,
    max_results: used.results,
  }
  let (_, again) = check_local_program(source, exact).unwrap()
  assert_eq(again, used)
  let short = check_local_program(source, { ..exact, max_work: used.work - 1, })
  // The shared closure checks each real import occurrence. One-less work
  // exhausts the capture producer on the second consumer input, not publication.
  guard short is Err(Order(1, ProducerOrder(issue))) else {
    fail("one-less work must refuse the actual captured producer closure")
  }
  assert_eq(issue.issue.kind, @pipeline.BudgetExceeded)
  let capture = topology_stage_at(topology, 0).unwrap()
  let producer = @collection.pipeline(
    @parameters.collection(topology_stage_source(capture)),
  )
  assert_true(physical_equal(issue.pipeline, producer))
}
