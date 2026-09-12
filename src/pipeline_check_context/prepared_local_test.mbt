///|
fn prepared_local_context_fixture(
  first_by_order? : Bool = false,
  unused_operation? : Bool = false,
) -> (
  StageContexts,
  @stage_results.ResultWiring,
  Array[@local_inputs.Attached],
  @stages.BoundOperations,
  @stage_results.Checked,
  Array[BoundParameters],
) {
  let program = @syntax.parse(
    (
      #|{"version":"actql/0.1","id":"prepared","params":{"n":{"type":"number","default":2}},"stages":[{"id":"first","inputs":{"rows":{"carrier":"relation","schema":{"id":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"derive":{"value":"id + $n"},"as":"derived"}],"results":{"out":{"from":"derived","fields":["id","value"]}}},{"id":"second","inputs":{"rows":{"result":{"stage":"first","result":"out"}},"again":{"result":{"stage":"first","result":"out"}}},"from":"rows","steps":[{"derive":{"next":"value + $n"},"as":"derived"}],"results":{"out":{"from":"derived","fields":["id","next"]}}}],"results":{"out":{"from":{"stage":"second","result":"out"}}}}
    )
    .replace(
      old="\"steps\":[{\"derive\":{\"value\":\"id + $n\"},\"as\":\"derived\"}]",
      new=if unused_operation {
        "\"steps\":[{\"derive\":{\"discard\":\"id\"},\"as\":\"unused\"},{\"derive\":{\"value\":\"id + $n\"},\"from\":\"rows\",\"as\":\"derived\"}]"
      } else {
        "\"steps\":[{\"derive\":{\"value\":\"id + $n\"},\"as\":\"derived\"}]"
      },
    )
    .replace(
      old="\"primary_key\":[\"id\"]",
      new=if first_by_order {
        "\"primary_key\":[\"id\"],\"duplicates\":{\"first_by_order\":{\"order_by\":[{\"id\":\"asc\"}]}}"
      } else {
        "\"primary_key\":[\"id\"]"
      },
    ),
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 2,
    },
    format=Json,
  ).unwrap()
  let source = @stages.prepare(program, {
    max_parameters: 1,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
  guard @parameter.bind(@stages.declarations(source), None, {
      max_nodes: 100,
      max_depth: 100,
      max_text_bytes: 10000,
    }).unwrap()
    is Ready(values) else {
    abort("fixture default")
  }
  let (wiring, _) = @stage_results.prepare_local_program(source, {
    max_stages: 2,
    max_steps: if unused_operation {
      3
    } else {
      2
    },
    max_results: 2,
    max_work: 1000000,
    max_nodes: 100000,
    max_tokens: 10000,
    max_text_bytes: 1000000,
    max_depth: 100,
  }).unwrap()
  let prepared = []
  let publications = []
  let locals = []
  let contexts = []
  for i in 0..<2 {
    let port = @stage_results.wiring_stage_at(wiring, i).unwrap()
    prepared.push(@stage_results.stage_port_source(port))
    locals.push(@stage_results.wiring_local_input_at(wiring, i).unwrap())
    let orders = @results.ports_orders(
      @stage_results.stage_port_publications(port),
    )
    publications.push(
      @results.publication_orders_results(
        @results.checked_publication_orders(orders),
      ),
    )
    let closure = @results.checked_producer_orders(orders)
    let applications = []
    let bindings = []
    for j in 0..<@pipeline.contextual_closure_count(closure) {
      // These two scalar derives have no acquired inputs or capacity claims.
      // The existing admission fixture still runs application coverage; this
      // is not a generic empty-proof default for other operations.
      applications.push(
        capacity(
          @pipeline.contextual_orders_pipeline(
            @pipeline.contextual_closure_at(closure, j).unwrap(),
          ),
        ),
      )
      bindings.push(Some(values))
    }
    let checked = check_resolved_orders(
      orders,
      bindings,
      applications,
      policy(),
      max_work=1000000,
      max_text_bytes=1000000,
    ).unwrap()
    contexts.push(
      check_parameter_bindings(
        checked,
        max_work=1000000,
        max_text_bytes=1000000,
      ).unwrap(),
    )
  }
  let operations = @stages.collect_prepared_operations(source, prepared, {
    max_work: 1000000,
    max_slots: 100,
    max_references: 100,
    max_pointer_units: 100000,
    max_direct_text_bytes: 100000,
  }).unwrap()
  let bound = @stages.bind_operations(operations, values, max_work=1000000).unwrap()
  let checked = @stage_results.collect_checked(operations, publications, {
    max_results: 2,
    max_work: 1000000,
    max_nodes: 100000,
    max_text_bytes: 1000000,
  }).unwrap()
  let stages = attach_stage_contexts(
    bound,
    checked,
    contexts,
    policy(),
    max_work=10000000,
    max_text_bytes=10000000,
  ).unwrap()
  (stages, wiring, locals, bound, checked, contexts)
}

///|
test "prepared Local Program composes binding order capacity and input checks without reissuing stages" {
  let (stages, wiring, locals, bound, _, _) = prepared_local_context_fixture()
  let wired = attach_result_wiring(
    stages,
    wiring,
    max_work=10000000,
    max_text_bytes=10000000,
  ).unwrap()
  let checked = attach_local_inputs(
    wired,
    locals,
    max_work=10000000,
    max_text_bytes=10000000,
    max_local_input_nodes=100000,
  ).unwrap()
  let operations = @stages.bound_operations(bound)
  let refs = @stages.operations_index(operations)
  assert_eq(@references.reference_count(refs), 2)
  for i in 0..<2 {
    let retained = local_inputs_at(checked, i).unwrap()
    assert_true(
      physical_equal(
        @local_inputs.attached_stage(retained),
        @stages.operations_stage_at(operations, i).unwrap(),
      ),
    )
    assert_true(
      physical_equal(
        retained,
        @stage_results.wiring_local_input_at(wiring, i).unwrap(),
      ),
    )
  }
  assert_eq(@stage_results.export_count(wiring), 1)
  let imported = @stage_results.attached_imports(
    @stage_results.wiring_imports_at(wiring, 1).unwrap(),
  )
  assert_eq(@stage_results.import_count(imported), 2)
  let used = input_usage(checked)
  assert_true(
    attach_local_inputs(
      wired,
      locals,
      max_work=used.work,
      max_text_bytes=used.text_bytes,
      max_local_input_nodes=used.local_input_nodes,
    )
    is Ok(_),
  )
  assert_true(
    attach_local_inputs(
      wired,
      locals,
      max_work=used.work - 1,
      max_text_bytes=used.text_bytes,
      max_local_input_nodes=used.local_input_nodes,
    )
    is Err(BudgetExceeded(_)),
  )
  locals.clear()
  assert_true(local_inputs_at(checked, 1) is Some(_))
}

///|
test "prepared Local Program rejects equal-content foreign contexts and missing later-stage checks" {
  let (stages, wiring, locals, bound, checked, contexts) = prepared_local_context_fixture()
  let (_, other_wiring, other_locals, _, _, other_contexts) = prepared_local_context_fixture()
  assert_true(
    attach_result_wiring(
      stages,
      other_wiring,
      max_work=10000000,
      max_text_bytes=10000000,
    )
    is Err(ForeignSource),
  )
  assert_true(
    attach_stage_contexts(
      bound,
      checked,
      [contexts[0]],
      policy(),
      max_work=10000000,
      max_text_bytes=10000000,
    )
    is Err(StageCount),
  )
  assert_true(
    attach_stage_contexts(
      bound,
      checked,
      [contexts[0], other_contexts[1]],
      policy(),
      max_work=10000000,
      max_text_bytes=10000000,
    )
    is Err(ForeignResults(1)),
  )
  let wired = attach_result_wiring(
    stages,
    wiring,
    max_work=10000000,
    max_text_bytes=10000000,
  ).unwrap()
  assert_true(
    attach_local_inputs(
      wired,
      [locals[0], other_locals[1]],
      max_work=10000000,
      max_text_bytes=10000000,
      max_local_input_nodes=100000,
    )
    is Err(ForeignStage(1)),
  )
}

///|
test "prepared Local Program cannot substitute another effective binding into retained contexts" {
  let (_, _, _, bound, checked, contexts) = prepared_local_context_fixture()
  let operations = @stages.bound_operations(bound)
  let source = @stages.operations_source(operations)
  guard @parameter.bind(
      @stages.declarations(source),
      Some(cursor("{\"n\":3}")),
      { max_nodes: 100, max_depth: 100, max_text_bytes: 10000, },
    ).unwrap()
    is Ready(values) else {
    abort("fixture supplied value")
  }
  let substituted = @stages.bind_operations(
    operations,
    values,
    max_work=1000000,
  ).unwrap()
  assert_true(
    attach_stage_contexts(
      substituted,
      checked,
      contexts,
      policy(),
      max_work=10000000,
      max_text_bytes=10000000,
    )
    is Err(ForeignBindings(0, 0)),
  )
}
