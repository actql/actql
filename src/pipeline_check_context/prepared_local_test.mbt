///|
fn prepared_local_source_fixture(
  first_by_order? : Bool = false,
  unused_operation? : Bool = false,
  third_stage? : Bool = false,
  environment? : @environment.WireEnvironment? = None,
) -> @stage_results.PreparedLocalSource {
  let stage_count = if third_stage { 3 } else { 2 }
  let program = @syntax.parse(
    (
      #|{"version":"actql/0.1","id":"prepared","params":{"n":{"type":"number","default":2}},"stages":[{"id":"first","inputs":{"rows":{"carrier":"relation","schema":{"id":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"derive":{"value":"id + $n"},"as":"derived"}],"results":{"out":{"from":"derived","fields":["id","value"]}}},{"id":"second","inputs":{"rows":{"result":{"stage":"first","result":"out"}},"again":{"result":{"stage":"first","result":"out"}}},"from":"rows","steps":[{"derive":{"next":"value + $n"},"as":"derived"}],"results":{"out":{"from":"derived","fields":["id","next"]}}}],"results":{"out":{"from":{"stage":"second","result":"out"}}}}
    )
    .replace(
      old="}],\"results\":{\"out\":{\"from\":{\"stage\":\"second\",\"result\":\"out\"}}}}",
      new=if third_stage {
        "},{\"id\":\"third\",\"inputs\":{\"rows\":{\"result\":{\"stage\":\"second\",\"result\":\"out\"}}},\"steps\":[],\"results\":{\"out\":{\"from\":\"rows\",\"fields\":[\"id\",\"next\"]}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"third\",\"result\":\"out\"}}}}"
      } else {
        "}],\"results\":{\"out\":{\"from\":{\"stage\":\"second\",\"result\":\"out\"}}}}"
      },
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
      max_stages: stage_count,
    },
    format=Json,
  ).unwrap()
  @stage_results.prepare_local_source(
    program,
    None,
    max_parameters=1,
    {
      max_stages: stage_count,
      max_steps: if unused_operation {
        3
      } else {
        2
      },
      max_results: stage_count,
      max_work: 1000000,
      max_nodes: 100000,
      max_tokens: 10000,
      max_text_bytes: 1000000,
      max_depth: 100,
    },
    environment~,
  ).unwrap()
}

///|
fn prepared_local_context_fixture(
  first_by_order? : Bool = false,
  unused_operation? : Bool = false,
  third_stage? : Bool = false,
  environment? : @environment.WireEnvironment? = None,
) -> (
  StageContexts,
  @stage_results.ResultWiring,
  Array[@local_inputs.Attached],
  @stages.BoundOperations,
  @stage_results.Checked,
  Array[BoundParameters],
) {
  let stage_count = if third_stage { 3 } else { 2 }
  let prepared_source = prepared_local_source_fixture(
    first_by_order~,
    unused_operation~,
    third_stage~,
    environment~,
  )
  let wiring = @stage_results.local_source_wiring(prepared_source)
  let locals = []
  let stage_materials = []
  for i in 0..<stage_count {
    let port = @stage_results.wiring_stage_at(wiring, i).unwrap()
    if @stage_results.wiring_local_input_at(wiring, i) is Some(input) {
      locals.push(input)
    }
    let orders = @results.ports_orders(
      @stage_results.stage_port_publications(port),
    )
    let closure = @results.checked_producer_orders(orders)
    let materials = []
    for _ in 0..<@pipeline.contextual_closure_count(closure) {
      // These two scalar derives have no acquired inputs or capacity claims.
      // The existing admission fixture still runs application coverage; this
      // is not a generic empty-proof default for other operations.
      materials.push(CapacityMaterial::{
        sources: empty_capacity_sources(),
        consumers: [],
      })
    }
    stage_materials.push(materials)
  }
  let bound = @stage_results.local_source_operations(prepared_source)
  let checked = @stage_results.local_source_results(prepared_source)
  let stages = prepare_local_stage_contexts(
    prepared_source,
    stage_materials,
    policy(),
    {
      max_work: 10000000,
      max_text_bytes: 10000000,
      max_name_bytes: 1000000,
      max_input_work: 1000000,
      max_operand_work: 1000000,
    },
  ).unwrap()
  let contexts = Array::makei(stage_count, i => {
    stage_context_at(stages, i).unwrap()
  })
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
