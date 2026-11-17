///|
// The actual existing caller_material owner admits the new fixed-shell DATA,
// not a reserve-always-succeeds port. No SDK/HTTP/GC adequacy is proved here.
test "Node async shell remains on the same original Request through Graph completion" {
  let storage = installed_node_model_caller_control_inventory(
    @model.install_async_model_provider("models/async").unwrap(),
    2,
  ).unwrap()
  let extra = @execution.preparation_representation_cost(storage).unwrap()
  let mut baseline = (0L, 0L)
  for supplied in [false, true] {
    let (parent, input, prepared, holder, occurrence, execution) = request_effect_model_graph_inputs()
    let capacity = parent.effect_capacity.unwrap()
    let before = @resources.preparation_capacity_working_extents(
      capacity, input,
    ).unwrap()
    prepare_request_model_graph(
      parent,
      input,
      occurrence,
      execution,
      request_program_module_contracts(),
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
      caller_material=if supplied { Some(storage) } else { None },
    ).unwrap()
    |> ignore
    let after = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
    if supplied {
      assert_eq(after.0 - before.0, baseline.0 + extra)
      assert_eq(after.1 - before.1, baseline.1 + extra)
    } else {
      baseline = (after.0 - before.0, after.1 - before.1)
    }
    assert_true(physical_equal(parent.effect_capacity.unwrap(), capacity))
    assert_true(physical_equal(parent.compiled_effect.unwrap(), prepared))
    assert_true(parent.program_domain_quote is None)
    assert_true(
      parent.program_domain_compilation_inputs
      is Some(RequestModelGraph(_, _, _, _)),
    )
    @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    assert_eq(@resources.ledger_usage(parent.ledger).held_bytes, 0L)
  }
}

///|
test "Node async shell exact capacity succeeds and one-short retains original failed cleanup" {
  let storage = installed_node_model_caller_control_inventory(
    @model.install_async_model_provider("models/async").unwrap(),
    2,
  ).unwrap()
  let mut required = (0L, 0L)
  for dimension in [-1, 2, 0, 1] {
    let (parent, input, _, holder, occurrence, execution) = request_effect_model_graph_inputs()
    let capacity = parent.effect_capacity.unwrap()
    let before = @resources.preparation_capacity_working_extents(
      capacity, input,
    ).unwrap()
    let sibling = if dimension < 0 {
      None
    } else {
      let limits = @resources.ledger_admission_limits(parent.ledger)
      let usage = @resources.ledger_usage(parent.ledger)
      let retained = limits.retained_bytes -
        usage.held_bytes -
        usage.reserved_retention_bytes
      let execution = limits.execution_bytes - usage.reserved_execution_bytes
      let remaining = if dimension == 0 || dimension == 2 {
        limits.retained_bytes -
        usage.held_bytes -
        usage.reserved_retention_bytes
      } else {
        limits.execution_bytes - usage.reserved_execution_bytes
      }
      let needed = if dimension == 0 || dimension == 2 {
        required.0
      } else {
        required.1
      }
      assert_true(remaining >= needed && needed > 0L)
      Some(
        @resources.reserve_capacity(
          parent.ledger,
          if dimension == 2 {
            retained - required.0
          } else if dimension == 0 {
            remaining - needed + 1L
          } else {
            0L
          },
          if dimension == 2 {
            execution - required.1
          } else if dimension == 1 {
            remaining - needed + 1L
          } else {
            0L
          },
        ).unwrap(),
      )
    }
    let result = prepare_request_model_graph(
      parent,
      input,
      occurrence,
      execution,
      request_program_module_contracts(),
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
      caller_material=Some(storage),
    )
    if dimension < 0 || dimension == 2 {
      result.unwrap() |> ignore
      let after = @resources.preparation_capacity_working_extents(
        capacity, input,
      ).unwrap()
      if dimension < 0 {
        required = (after.0 - before.0, after.1 - before.1)
      } else {
        assert_eq((after.0 - before.0, after.1 - before.1), required)
        @resources.settle_capacity(parent.ledger, sibling.unwrap()).unwrap()
      }
    } else {
      assert_true(result is Err(Preparation(Capacity(_))))
      assert_true(parent.phase == EffectBodyFailed)
      assert_true(
        parent.program_domain_compilation_inputs
        is Some(RequestModelGraphConstruction(_, _, _, _)),
      )
      @resources.settle_capacity(parent.ledger, sibling.unwrap()).unwrap()
    }
    assert_true(physical_equal(parent.effect_capacity.unwrap(), capacity))
    @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    assert_eq(@resources.ledger_usage(parent.ledger).held_bytes, 0L)
  }
  assert_true(installed_node_model_async_control_inventory(-1) is None)
}

///|
fn node_shell_original_mock_fixture() -> @model.ModelMockInstallation {
  let limits : @environment.ModelTaskLimits = {
    bodies: {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 16,
      max_members: 100,
    },
    contracts: { max_nodes: 100, max_depth: 16, max_text_bytes: 1000, },
    max_work: 100000,
  }
  let task = @environment.read_public_model_task_document(
    "{\"task\":\"model-task:shell-fixture\",\"input\":{\"text\":\"string\"},\"output\":{\"enabled\":\"boolean\"},\"instructions\":\"original\"}",
    "json", limits,
  ).unwrap()
  let profile = @environment.install_model_mock_profile(limits).unwrap()
  let normalized = @environment.normalize_public_mock_model_task(
    task, profile, limits,
  ).unwrap()
  let answers = @model.read_model_mock_answer_document(
    task,
    "{\"task\":\"model-task:shell-fixture\",\"answers\":{\"default\":{\"enabled\":true}}}",
    "json",
    {
      document: limits.bodies,
      values: { max_nodes: 100, max_depth: 16, max_text_bytes: 1000, },
      max_entries: 1,
      max_work: 100000,
    },
  ).unwrap()
  @model.install_original_model_mock(profile, task, normalized, answers, () => {
    "2026-11-18T00:00:00.000Z"
  }).unwrap()
}

///|
test "synchronous Source0 Mock and legacy keep their original exact Graph capacity" {
  let mock = node_shell_original_mock_fixture()
  let providers = [
    @model.install_model_provider("mock", _ => Err(@model.ProviderError)).unwrap(),
    @model.original_model_mock_provider(mock).unwrap(),
  ]
  let mut required = (0L, 0L)
  for mode in 0..<3 {
    let (parent, input, prepared) = request_model_input_fixture(captured=false)
    let holder = borrow_request_model_plan_input(parent, input).unwrap()
    let (occurrence, execution) = request_model_graph_inputs(prepared)
    let capacity = parent.program_capacity.unwrap()
    let before = @resources.preparation_capacity_working_extents(
      capacity, input,
    ).unwrap()
    let material = if mode == 0 {
      None
    } else {
      let selected = installed_node_model_caller_control_inventory(
        providers[mode - 1],
        2,
      )
      assert_true(selected is None)
      selected
    }
    let sibling = if mode == 0 {
      None
    } else {
      let limits = @resources.ledger_admission_limits(parent.ledger)
      let usage = @resources.ledger_usage(parent.ledger)
      let r = limits.retained_bytes -
        usage.held_bytes -
        usage.reserved_retention_bytes
      let e = limits.execution_bytes - usage.reserved_execution_bytes
      assert_true(r >= required.0 && e >= required.1)
      Some(
        @resources.reserve_capacity(
          parent.ledger,
          r - required.0,
          e - required.1,
        ).unwrap(),
      )
    }
    prepare_request_model_graph(
      parent,
      input,
      occurrence,
      execution,
      request_program_module_contracts(),
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
      caller_material=material,
    ).unwrap()
    |> ignore
    let after = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
    if mode == 0 {
      required = (after.0 - before.0, after.1 - before.1)
    } else {
      assert_eq(after.0 - before.0, required.0)
      assert_eq(after.1 - before.1, required.1)
      @resources.settle_capacity(parent.ledger, sibling.unwrap()).unwrap()
    }
    @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    assert_eq(@resources.ledger_usage(parent.ledger).held_bytes, 0L)
  }
  assert_true(@model.retire_original_model_mock(mock).unwrap())
}
