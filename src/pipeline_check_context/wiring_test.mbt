///|
fn wired_fixture() -> (
  StageContexts,
  @stage_results.ResultWiring,
  @stage_results.ResultWiring,
  Array[@local_inputs.Attached],
) {
  let (stages, wiring, alternative, locals, _, _) = wired_inputs_fixture(false)
  (stages, wiring, alternative, locals)
}

///|
fn wired_inputs_fixture(
  use_snapshots : Bool,
  profile? : String = "{}",
  expression? : String = "$n",
  parameters? : String = "{\"n\":{\"type\":\"number\",\"default\":1}}",
  supplied? : @decode.Cursor? = None,
) -> (
  StageContexts,
  @stage_results.ResultWiring,
  @stage_results.ResultWiring,
  Array[@local_inputs.Attached],
  Array[@local_inputs.ReconciledAttachment],
  @local_inputs.ProgramEnvironmentInputs?,
) {
  let program = @syntax.parse(
    (
      #|{"version":"actql/0.1","id":"p","params":{"n":{"type":"number","default":1}},"stages":[{"id":"first","inputs":{"a":{"carrier":"relation","schema":{"id":{"type":"number","nullable":false}}}},"steps":[{"derive":{"x":"$n"}}],"results":{"out":{"from":"a","fields":["id"]}}},{"id":"second","inputs":{"a":{"result":{"stage":"first","result":"out"}}},"steps":[{"derive":{"x":"$n"}}],"results":{"out":{"from":"a","fields":["id"]}}}],"results":{"out":{"from":{"stage":"second","result":"out"}}}}
    )
    .replace(
      old="\"params\":{\"n\":{\"type\":\"number\",\"default\":1}}",
      new="\"params\":" + parameters,
    )
    .replace(old="\"x\":\"$n\"", new="\"x\":\"" + expression + "\"")
    .replace(old="\"x\":\"$n\"", new="\"x\":\"" + expression + "\""),
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
  let declarations = @stages.declarations(source)
  let (environment, snapshot) = snapshot_wire(profile~)
  let source_index = @refs.prepare(source, {
    max_work: 100000,
    max_text_bytes: 100000,
  }).unwrap()
  let environment_inputs = []
  let local_limits : @local_inputs.Limits = {
    max_work: 100000,
    max_nodes: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  }
  guard @parameter.bind(declarations, supplied, {
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 1000,
    }).unwrap()
    is Ready(values) else {
    abort("missing default")
  }
  let local_declarations = []
  let pipelines = []
  let results = []
  let contexts = []
  let ports = []
  let imports = []
  let alternative_ports = []
  let collection_limits : @parameter_slots.Limits = {
    max_work: 10000,
    max_slots: 100,
    max_references: 100,
    max_pointer_units: 10000,
    max_direct_text_bytes: 10000,
  }
  let order_limits : @results.OrderCheckLimits = {
    max_steps: 10,
    max_results: 10,
    max_work: 10000,
    max_text_bytes: 10000,
  }
  let port_limits : @results.PortLimits = {
    max_results: 10,
    max_work: 20000,
    max_nodes: 1000,
    max_text_bytes: 20000,
    max_depth: 100,
  }
  for i in 0..<2 {
    let prepared = @local_inputs.prepare(source, i, {
      max_work: 10000,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    }).unwrap()
    local_declarations.push(prepared)
    if use_snapshots {
      environment_inputs.push(
        @local_inputs.reconcile_environment(
          prepared,
          source_index,
          environment,
          if i == 0 {
            [snapshot]
          } else {
            []
          },
          local_limits,
        ).unwrap(),
      )
    }
    let resolved = @stage_results.resolve_imports(source, i, ports, {
      max_work: 10000,
      max_imports: 10,
      max_text_bytes: 10000,
    }).unwrap()
    let input = if i == 0 {
      if use_snapshots {
        @local_inputs.environment_input_at(environment_inputs[i], 0).unwrap().1
      } else {
        @local_inputs.input_at(prepared, 0).unwrap().1
      }
    } else {
      @pipeline.ProducedInput(
        @stage_results.input_producer(
          @stage_results.import_at(resolved, 0).unwrap(),
        ),
      )
    }
    let body = @decode.open_object(
      @syntax.stage_body(@stages.stage_at(source, i).unwrap()),
    ).unwrap()
    let pipeline = @pipeline.check_with_evidence(
      @decode.required(body, "steps").unwrap(),
      [("a", input)],
      Some(declarations),
      None,
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap()
    pipelines.push(pipeline)
    let stage = @stages.collect(source, i, pipeline, collection_limits).unwrap()
    imports.push(
      @stage_results.attach_imports(resolved, stage, max_work=20000).unwrap(),
    )
    let result = @results.check(
      pipeline,
      @decode.required(body, "results").unwrap(),
      {
        max_results: 10,
        max_work: 20000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_depth: 100,
      },
    ).unwrap()
    results.push(result)
    let orders = @results.resolve_all_orders(result, order_limits).unwrap()
    let publication = @stage_results.bind_ports(
      stage,
      @results.prepare_ports(orders, port_limits).unwrap(),
    ).unwrap()
    ports.push(publication)
    // Only replace the last publication: its imports still use the original first owner.
    alternative_ports.push(
      if i == 0 {
        publication
      } else {
        @stage_results.bind_ports(
          stage,
          @results.prepare_ports(
            @results.resolve_all_orders(result, order_limits).unwrap(),
            port_limits,
          ).unwrap(),
        ).unwrap()
      },
    )
    let closure = @results.checked_producer_orders(orders)
    let applications = []
    let bindings = []
    for j in 0..<@pipeline.contextual_closure_count(closure) {
      applications.push(
        capacity(
          @pipeline.contextual_orders_pipeline(
            @pipeline.contextual_closure_at(closure, j).unwrap(),
          ),
        ),
      )
      bindings.push(Some(values))
    }
    let context = check_resolved_orders(
      orders,
      bindings,
      applications,
      policy(),
      max_work=50000,
      max_text_bytes=50000,
    ).unwrap()
    contexts.push(
      check_parameter_bindings(context, max_work=100000, max_text_bytes=100000).unwrap(),
    )
  }
  let operations = @stages.collect_operations(
    source, pipelines, collection_limits,
  ).unwrap()
  let bound = @stages.bind_operations(operations, values, max_work=100000).unwrap()
  let local_attachments = []
  let reconciled = []
  for i in 0..<2 {
    if use_snapshots {
      reconciled.push(
        @local_inputs.attach_reconciled(
          environment_inputs[i],
          @stages.operations_stage_at(operations, i).unwrap(),
          max_work=1000000,
        ).unwrap(),
      )
      continue
    }
    local_attachments.push(
      @local_inputs.attach(
        local_declarations[i],
        @stages.operations_stage_at(operations, i).unwrap(),
        max_work=100000,
      ).unwrap(),
    )
  }
  let checked = @stage_results.collect_checked(operations, results, {
    max_results: 10,
    max_work: 100000,
    max_nodes: 10000,
    max_text_bytes: 100000,
  }).unwrap()
  let stages = attach_stage_contexts(
    bound,
    checked,
    contexts,
    policy(),
    max_work=1000000,
    max_text_bytes=1000000,
  ).unwrap()
  let limits : @stage_results.WiringLimits = {
    max_work: 100000,
    max_text_bytes: 100000,
    max_imports: 10,
    max_exports: 10,
  }
  let wiring = @stage_results.wire_results(source, ports, imports, limits).unwrap()
  let alternative = @stage_results.wire_results(
    source, alternative_ports, imports, limits,
  ).unwrap()
  ports.clear()
  imports.clear()
  contexts.clear()
  let coverage = if use_snapshots {
    Some(
      @local_inputs.assemble_environment(
        source, environment, environment_inputs, local_limits,
      ).unwrap(),
    )
  } else {
    None
  }
  (stages, wiring, alternative, local_attachments, reconciled, coverage)
}

///|
test "Result imports and root exports attach to exact staged publication owners" {
  let (stages, wiring, alternative, _) = wired_fixture()
  let attached = attach_result_wiring(
    stages,
    wiring,
    max_work=1000000,
    max_text_bytes=1000000,
  ).unwrap()
  assert_true(physical_equal(wired_stage_contexts(attached), stages))
  assert_true(physical_equal(result_wiring(attached), wiring))
  let imported = @stage_results.import_at(
    @stage_results.attached_imports(
      @stage_results.wiring_imports_at(wiring, 1).unwrap(),
    ),
    0,
  ).unwrap()
  assert_true(
    physical_equal(
      @stage_results.input_stage(imported),
      @stage_results.wiring_stage_at(wiring, 0).unwrap(),
    ),
  )
  assert_eq(@stage_results.export_count(wiring), 1)
  assert_true(
    physical_equal(
      @stage_results.export_stage(@stage_results.export_at(wiring, 0).unwrap()),
      @stage_results.wiring_stage_at(wiring, 1).unwrap(),
    ),
  )
  let (sw, st) = stage_usage(stages)
  let (ww, wt) = @stage_results.wiring_usage(wiring)
  let mut shared_work = 0
  let mut shared_text = 0
  for i in 0..<2 {
    let (w, t) = @results.checked_orders_usage(
      checked_orders(parameter_context(stage_context_at(stages, i).unwrap())),
    )
    shared_work += w
    shared_text += t
  }
  let (work, text) = wired_usage(attached)
  assert_eq((work, text), (sw + ww - shared_work + 2, st + wt - shared_text))
  assert_true(
    attach_result_wiring(stages, wiring, max_work=work, max_text_bytes=text)
    is Ok(_),
  )
  assert_true(
    attach_result_wiring(stages, wiring, max_work=work - 1, max_text_bytes=text)
    is Err(BudgetExceeded),
  )
  assert_true(
    attach_result_wiring(stages, wiring, max_work=work, max_text_bytes=text - 1)
    is Err(BudgetExceeded),
  )
  assert_true(
    attach_result_wiring(stages, wiring, max_work=0, max_text_bytes=text)
    is Err(BudgetExceeded),
  )
  assert_true(
    attach_result_wiring(stages, wiring, max_work=-1, max_text_bytes=text)
    is Err(InvalidLimits),
  )
  assert_true(
    attach_result_wiring(stages, wiring, max_work=work, max_text_bytes=-1)
    is Err(InvalidLimits),
  )
  assert_true(
    attach_result_wiring(
      stages,
      alternative,
      max_work=1000000,
      max_text_bytes=1000000,
    )
    is Err(ForeignOrders(1)),
  )
  let (_, foreign, _, _) = wired_fixture()
  assert_true(
    attach_result_wiring(
      stages,
      foreign,
      max_work=1000000,
      max_text_bytes=1000000,
    )
    is Err(ForeignSource),
  )
}
