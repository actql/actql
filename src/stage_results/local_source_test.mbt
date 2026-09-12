///|
test "Local source preparation owns declarations bindings and topology with shared admission caps" {
  for multiple in [false, true] {
    let parsed = @parameters.program(local_program_source(multiple))
    let original = local_program_limits()
    let prepared = prepare_local_source(
      parsed,
      None,
      max_parameters=0,
      original,
    ).unwrap()
    let source = local_source_source(prepared)
    let bound = local_source_operations(prepared)
    let operations = @parameters.bound_operations(bound)
    let results = local_source_results(prepared)
    assert_true(physical_equal(@stage_results.operations(results), operations))
    assert_true(
      physical_equal(@parameters.operations_source(operations), source),
    )
    assert_true(
      physical_equal(
        @references.bound_values(@parameters.bound_program_index(bound)),
        local_source_values(prepared),
      ),
    )
    let mut shared_work = 0
    for i in 0..<@syntax.stage_count(parsed) {
      let stage = @parameters.operations_stage_at(operations, i).unwrap()
      assert_true(
        physical_equal(
          stage,
          stage_port_source(
            wiring_stage_at(local_source_wiring(prepared), i).unwrap(),
          ),
        ),
      )
      shared_work += @parameters.collection_work(stage)
      let port = wiring_stage_at(local_source_wiring(prepared), i).unwrap()
      let port_result = @results.publication_orders_results(
        @results.checked_publication_orders(
          @results.ports_orders(stage_port_publications(port)),
        ),
      )
      assert_true(physical_equal(stage_at(results, i).unwrap(), port_result))
      assert_true(
        physical_equal(
          @references.bound_values(
            @parameters.bound_stage_at(bound, i).unwrap(),
          ),
          local_source_values(prepared),
        ),
      )
    }
    assert_true(physical_equal(@parameters.program(source), parsed))
    assert_true(
      physical_equal(wiring_source(local_source_wiring(prepared)), source),
    )
    assert_true(
      physical_equal(
        @binding.bound_declarations(local_source_values(prepared)),
        @parameters.declarations(source),
      ),
    )
    let usage = local_source_usage(prepared)
    let (_, topology_usage) = prepare_local_program(source, original).unwrap()
    assert_true(
      prepare_local_source(parsed, None, max_parameters=0, {
        ..original,
        max_work: topology_usage.work + @syntax.stage_count(parsed) + 1,
      })
      is Err(BudgetExceeded),
    )
    assert_eq(
      usage.work,
      topology_usage.work +
      4 * @syntax.stage_count(parsed) +
      1 +
      @parameters.bindings_usage(bound).work -
      shared_work,
    )
    let exact : LocalProgramLimits = {
      ..original,
      max_work: usage.work,
      max_nodes: usage.nodes,
      max_tokens: usage.tokens,
      max_text_bytes: usage.text_bytes,
      max_steps: usage.steps,
      max_results: usage.results,
      max_stages: if multiple {
        2
      } else {
        1
      },
    }
    assert_true(
      prepare_local_source(parsed, None, max_parameters=0, {
        ..exact,
        max_work: usage.work - 1,
      })
      is Err(ResultCollection(BudgetExceeded(_))),
    )
    assert_true(
      prepare_local_source(parsed, None, max_parameters=0, exact) is Ok(_),
    )
    for
      short in [
        { ..exact, max_work: usage.work - 1, },
        { ..exact, max_nodes: usage.nodes - 1, },
        { ..exact, max_text_bytes: usage.text_bytes - 1, },
        { ..exact, max_stages: 0, },
      ] {
      assert_true(
        prepare_local_source(parsed, None, max_parameters=0, short) is Err(_),
      )
    }
    assert_true(
      prepare_local_source(parsed, None, max_parameters=-1, exact)
      is Err(InvalidLimits),
    )
  }
  let bad = @parameters.program(local_program_source(true, bad_later=true))
  assert_true(
    prepare_local_source(bad, None, max_parameters=0, local_program_limits())
    is Err(Program(Pipeline(1, _))),
  )
}

///|
test "Local source preparation never treats missing or invalid Parameters as prepared values" {
  let text =
    #|{"version":"actql/0.1","id":"p","params":{"n":{"type":"number"}},"stages":[{"id":"s","inputs":{"rows":{"carrier":"relation","schema":{"id":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[],"results":{"out":{"from":"rows","fields":["id"]}}}],"results":{"out":{"from":{"stage":"s","result":"out"}}}}
  let source = local_program_parse(text)
  let program = @parameters.program(source)
  let limits = local_program_limits()
  assert_true(
    prepare_local_source(program, None, max_parameters=1, limits)
    is Err(NeedsBindings(_)),
  )
  let with_default = @parameters.program(
    local_program_parse(
      text
      .replace(
        old="\"type\":\"number\"}",
        new="\"type\":\"number\",\"default\":2}",
      )
      .replace(
        old="\"steps\":[]",
        new="\"steps\":[{\"derive\":{\"extra\":\"id + $n\"}}]",
      ),
    ),
  )
  let prepared = prepare_local_source(
    with_default,
    None,
    max_parameters=1,
    limits,
  ).unwrap()
  let (decl_nodes, decl_text) = @binding.declaration_usage(
    @parameters.declarations(local_source_source(prepared)),
  )
  let values = local_source_values(prepared)
  let bound = local_source_operations(prepared)
  assert_eq(
    @references.reference_count(
      @parameters.operations_index(@parameters.bound_operations(bound)),
    ),
    1,
  )
  assert_true(
    physical_equal(
      @references.bound_values(@parameters.bound_program_index(bound)),
      values,
    ),
  )
  assert_eq(@binding.bound_value_count(values), 1)
  assert_eq(@binding.bound_value_at(values, 0).unwrap().name, "n")
  let (bind_nodes, bind_text) = @binding.binding_usage(
    @binding.bind(
      @parameters.declarations(local_source_source(prepared)),
      None,
      {
        max_nodes: limits.max_nodes,
        max_text_bytes: limits.max_text_bytes,
        max_depth: limits.max_depth,
      },
    ).unwrap(),
  )
  let (_, topology) = prepare_local_program(
    local_source_source(prepared),
    limits,
  ).unwrap()
  let used = local_source_usage(prepared)
  assert_eq(used.nodes, decl_nodes + bind_nodes + topology.nodes)
  assert_eq(used.text_bytes, decl_text + bind_text + topology.text_bytes)
  let exact = {
    ..limits,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
    max_work: used.work,
  }
  assert_true(
    prepare_local_source(with_default, None, max_parameters=1, exact) is Ok(_),
  )
  assert_true(
    prepare_local_source(with_default, None, max_parameters=1, {
      ..exact,
      max_nodes: used.nodes - 1,
    })
    is Err(_),
  )
  assert_true(
    prepare_local_source(with_default, None, max_parameters=1, {
      ..exact,
      max_text_bytes: used.text_bytes - 1,
    })
    is Err(_),
  )
  assert_true(
    prepare_local_source(with_default, None, max_parameters=0, limits)
    is Err(Declarations(_)),
  )
  let supplied = @decode.lookup(
    @decode.open_object(@syntax.program_body(program)).unwrap(),
    "params",
  )
  // The map contains n, but its object value cannot satisfy number. A default
  // must not hide this supplied type error.
  assert_true(
    prepare_local_source(with_default, supplied, max_parameters=1, limits)
    is Err(Binding(_)),
  )
}
