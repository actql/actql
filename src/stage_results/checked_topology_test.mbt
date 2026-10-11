///|
fn topology_control_source(
  two_stages : Bool,
  required_order? : Bool = false,
  bad_type? : Bool = false,
) -> @parameters.Source {
  let first =
    #|{"id":"first","inputs":{"rows":{"carrier":"relation","schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}}}}},"steps":[{"from":"rows","filter":{"literal":true}},{"select":["id","payload"],"as":"captured"}],"results":{"source":{"from":"captured","fields":["id","payload"]}}}
  let first = if bad_type {
    first.replace(old="{\"literal\":true}", new="{\"literal\":1}")
  } else {
    first
  }
  let second =
    #|{"id":"second","inputs":{"a":{"result":{"stage":"first","result":"source"}},"b":{"result":{"stage":"first","result":"source"}}},"from":"a","steps":[{"derive":{"more":"id + 1"},"as":"answer"}],"results":{"rows":{"from":"answer","fields":["id","more"]}}}
  let second = if required_order {
    second
    .replace(
      old="{\"derive\":{\"more\":\"id + 1\"},\"as\":\"answer\"}",
      new="{\"take\":1,\"as\":\"answer\"}",
    )
    .replace(old="[\"id\",\"more\"]", new="[\"id\"]")
  } else {
    second
  }
  let constant =
    #|{"id":"second","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"answer"}],"results":{"rows":{"from":"answer","fields":["id"]}}}
  local_program_parse(
    "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[" +
    first +
    "," +
    (if two_stages { second } else { constant }) +
    "],\"results\":{\"answer\":{\"from\":{\"stage\":\"second\",\"result\":\"rows\"}}}}",
  )
}

///|
test "check-only topology retains original capture and unresolved Result order" {
  for imported in [false, true] {
    let source = topology_control_source(imported)
    let (topology, used) = check_local_program(source, local_program_limits()).unwrap()
    assert_true(physical_equal(topology_source(topology), source))
    assert_eq(used, topology_usage(topology))
    let first = topology_stage_at(topology, 0).unwrap()
    let checked = @results.checked_inputs_results(topology_stage_results(first))
    let definition = @results.result_at(checked, 0).unwrap()
    assert_eq(@results.pending_validations(definition), [
      @results.TotalDeterministicOrder,
    ])
    assert_eq(@decode.cursor_path(@results.definition_source(definition)), [
      Key("stages"),
      Index(0),
      Key("results"),
      Key("source"),
    ])
    let pipeline = @collection.pipeline(
      @parameters.collection(topology_stage_source(first)),
    )
    let projected = @results.checked_input_at(topology_stage_results(first), 0).unwrap()
    assert_true(
      physical_equal(@pipeline.producer_pipeline(projected), pipeline),
    )
    assert_eq(@pipeline.producer_target(projected), Step(1))
    assert_true(@pipeline.producer_projection(projected) is Some(_))
    assert_true(topology_local_input_at(topology, 0) is Some(_))
    assert_true(topology_local_environment(topology) is None)
    let second = topology_stage_at(topology, 1).unwrap()
    let imports = topology_imports_at(topology, 1).unwrap()
    assert_eq(topology_import_count(imports), if imported { 2 } else { 0 })
    if imported {
      let consumer = @collection.pipeline(
        @parameters.collection(topology_stage_source(second)),
      )
      for i in 0..<2 {
        let edge = topology_import_at(imports, i).unwrap()
        assert_true(physical_equal(topology_input_stage(edge), first))
        assert_true(physical_equal(topology_input_producer(edge), projected))
        let index = match
          @pipeline.lookup(consumer, topology_input_name(edge)).unwrap() {
          Input(index) => index
          _ => abort("expected actual import")
        }
        assert_true(
          physical_equal(
            @pipeline.input_producer(consumer, index).unwrap(),
            projected,
          ),
        )
      }
    }
    assert_eq(topology_export_count(topology), 1)
    assert_true(
      physical_equal(
        topology_export_stage(topology_export_at(topology, 0).unwrap()),
        second,
      ),
    )
    guard prepare_local_program(source, local_program_limits())
      is Err(Order(0, ResultOrder(issue))) else {
      abort("publication must remain strict")
    }
    assert_eq(issue.kind, @results.UnresolvedOrder)
  }
}

///|
test "check-only still rejects an invalid expression in an unused capture" {
  guard check_local_program(
      topology_control_source(false, bad_type=true),
      local_program_limits(),
    )
    is Err(Pipeline(0, issue)) else {
    abort("unused pipeline must be fully typed")
  }
  assert_eq(@decode.cursor_path(issue.source), [
    Key("stages"),
    Index(0),
    Key("steps"),
    Index(0),
    Key("filter"),
  ])
}

///|
test "deferred Result publication never excuses required input order" {
  guard check_local_program(
      topology_control_source(true, required_order=true),
      local_program_limits(),
    )
    is Err(Order(1, PipelineOrder(issue))) else {
    abort("take requires actual input order")
  }
  assert_eq(issue.kind, @pipeline.UnresolvedOrder)
  assert_eq(issue.path, [Key("stages"), Index(1), Key("steps"), Index(0)])
}

///|
test "check-only preserves bounded accounting and foreign owner checks" {
  let source = topology_control_source(true)
  let (topology, used) = check_local_program(source, local_program_limits()).unwrap()
  let exact = {
    ..local_program_limits(),
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
    max_tokens: used.tokens,
    max_steps: used.steps,
    max_results: used.results,
  }
  assert_true(check_local_program(source, exact) is Ok(_))
  for
    short in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_nodes: used.nodes - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
      { ..exact, max_steps: used.steps - 1, },
      { ..exact, max_results: used.results - 1, },
    ] {
    assert_true(check_local_program(source, short) is Err(_))
  }
  assert_true(topology_reconciled_input_at(topology, 0) is None)
}
