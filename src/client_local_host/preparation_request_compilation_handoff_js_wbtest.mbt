///|
// Actual Request/compiler/module/Run with explicit factory and capture ports.
// This proves neither Source IO nor complete ordinary constructor backing.
test "ordinary compiler artifact precedes module and transfers once without another writer receipt" {
  for captured in [false, true] {
    let (parent, input, prepared) = if captured {
      request_capture_fixture()
    } else {
      request_program_body_fixture()
    }
    let capacity = parent.program_capacity.unwrap()
    let construction = borrow_request_program_plan_input(parent, input).unwrap()
    let contracts = if captured {
      prepare_installed_sequence_contracts(
        source_query_original_registry,
        source_query_original_values,
        Some(source_query_original_fragment),
        None,
      ).unwrap()
    } else {
      request_program_module_contracts()
    }
    let manifests = request_program_module_manifests()
    let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
    let calls = Ref(0)
    let factory = (_ : @execution.ExecutionCapacity) => {
      calls.val += 1
      []
    }
    let artifact = prepare_request_program_compilation(
      parent,
      input,
      contracts,
      manifests~,
      compilation_limits~,
      retained_output=true,
      provider_factory=factory,
    ).unwrap()
    assert_eq(calls.val, 0)
    assert_true(physical_equal(parent.program_compilation.unwrap(), artifact))
    assert_true(
      parent.program_source_free is None && parent.program_captured is None,
    )
    assert_true(physical_equal(parent.program_capacity.unwrap(), capacity))
    let spent = parent.program_artifact_work_spent
    assert_true(spent > 0L)
    // The real Owner already closed this named phase. A second compiler would
    // be refused, not hidden behind an entry counter or overwritten node count.
    assert_true(
      @resources.begin_preparation_phase_work64(
        capacity,
        input,
        @resources.ExecutionPlan,
        1L,
      )
      is Err(AlreadyClaimed),
    )
    assert_true(
      prepare_request_program_compilation(
        parent,
        input,
        contracts,
        manifests~,
        compilation_limits~,
        retained_output=true,
        provider_factory=factory,
      )
      is Err(Preparation(WrongPhase)),
    )
    let request = if captured {
      let (plan, request) = request_capture_plan_fixture(
        prepared,
        original_contracts=Some(contracts),
        factory~,
      )
      prepare_request_capture_module_body(
        parent,
        input,
        plan,
        manifests~,
        compilation_limits~,
        provider_factory=factory,
      ).unwrap()
      assert_true(physical_equal(plan.compilation.unwrap(), artifact))
      request
    } else {
      prepare_request_program_module_body(
        parent,
        input,
        contracts,
        manifests~,
        compilation_limits~,
        retained_output=true,
        provider_factory=factory,
      ).unwrap()
      assert_true(
        physical_equal(
          parent.program_source_free.unwrap().compilation.unwrap(),
          artifact,
        ),
      )
      @publication_host.prepare_source_free_client_request_identity(
        prepared,
        "sha256:" + "a".repeat(64),
        "compilation-before-module",
      ).unwrap()
    }
    assert_eq(calls.val, 1)
    assert_true(parent.program_compilation is None)
    assert_eq(parent.program_artifact_work_spent, spent)
    @resources.return_preparation_body_borrow(construction).unwrap() |> ignore
    let run = if captured {
      begin_request_capture_managed_run(parent, request).unwrap()
    } else {
      begin_request_program_managed_run(parent, request).unwrap()
    }
    assert_true(
      physical_equal(
        installed_managed_run_compilation_original(run, prepared).unwrap(),
        artifact,
      ),
    )
    retire_installed_managed_run(run).unwrap()
    assert_eq(parent.program_artifact_work_spent, spent)
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "early compilation refuses changed module originals before any factory or second emission" {
  let (parent, input, _) = request_program_body_fixture()
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
  let calls = Ref(0)
  let factory = (_ : @execution.ExecutionCapacity) => {
    calls.val += 1
    []
  }
  assert_true(
    prepare_request_program_compilation(
      parent,
      [999],
      contracts,
      manifests~,
      compilation_limits~,
      retained_output=true,
      provider_factory=factory,
    )
    is Err(Preparation(ForeignOriginal)),
  )
  let artifact = prepare_request_program_compilation(
    parent,
    input,
    contracts,
    manifests~,
    compilation_limits~,
    retained_output=true,
    provider_factory=factory,
  ).unwrap()
  let spent = parent.program_artifact_work_spent
  assert_true(
    prepare_request_program_module_body(
      parent,
      input,
      request_program_module_contracts(),
      manifests~,
      compilation_limits~,
      retained_output=true,
      provider_factory=factory,
    )
    is Err(Preparation(ForeignOriginal)),
  )
  assert_true(
    prepare_request_program_module_body(
      parent,
      input,
      contracts,
      manifests~,
      compilation_limits~,
      retained_output=false,
      provider_factory=factory,
    )
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(calls.val, 0)
  assert_true(physical_equal(parent.program_compilation.unwrap(), artifact))
  assert_eq(parent.program_artifact_work_spent, spent)
  prepare_request_program_module_body(
    parent,
    input,
    contracts,
    manifests~,
    compilation_limits~,
    retained_output=true,
    provider_factory=factory,
  ).unwrap()
  assert_eq(calls.val, 1)
  assert_true(
    physical_equal(
      parent.program_source_free.unwrap().compilation.unwrap(),
      artifact,
    ),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(parent.program_artifact_work_spent, spent)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "module throw after early compilation retains its spent artifact until original abort" {
  let (parent, input, _) = request_program_body_fixture()
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
  let calls = Ref(0)
  let factory = (_ : @execution.ExecutionCapacity) => {
    calls.val += 1
    closed_module_test_throw()
  }
  let artifact = prepare_request_program_compilation(
    parent,
    input,
    contracts,
    manifests~,
    compilation_limits~,
    retained_output=true,
    provider_factory=factory,
  ).unwrap()
  let spent = parent.program_artifact_work_spent
  assert_eq(calls.val, 0)
  assert_true(
    closed_module_test_catch(() => {
      prepare_request_program_module_body(
        parent,
        input,
        contracts,
        manifests~,
        compilation_limits~,
        retained_output=true,
        provider_factory=factory,
      ).unwrap()
      |> ignore
    }),
  )
  assert_eq(calls.val, 1)
  assert_true(physical_equal(parent.program_compilation.unwrap(), artifact))
  assert_true(parent.phase == ProgramBodyFailed)
  assert_true(parent.program_artifact_work is None)
  assert_eq(parent.program_artifact_work_spent, spent)
  assert_true(
    prepare_request_program_compilation(
      parent,
      input,
      contracts,
      manifests~,
      compilation_limits~,
      retained_output=true,
      provider_factory=factory,
    )
    is Err(Preparation(WrongPhase)),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(parent.program_compilation is None)
  assert_eq(parent.program_artifact_work_spent, spent)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "single Values compilation uses the same original output slot through module and Run" {
  let document =
    #|{"version":"actql/0.1","id":"single-values-compilation","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"}],"results":{"rows":{"from":"seed","fields":["id"]}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
  let (parent, check, _, input) = registration_parent_fixture(text=document)
  finish_program_check_preparation(check).unwrap() |> ignore
  let prepared = compile_program_check_preparation(
    check,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  continue_request_program_preparation(parent, input).unwrap() |> ignore
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
  let calls = Ref(0)
  let factory = (_ : @execution.ExecutionCapacity) => {
    calls.val += 1
    []
  }
  let artifact = prepare_request_program_compilation(
    parent,
    input,
    contracts,
    manifests~,
    compilation_limits~,
    retained_output=true,
    provider_factory=factory,
  ).unwrap()
  assert_true(artifact is @publication_host.Values(_))
  assert_eq(calls.val, 0)
  let spent = parent.program_artifact_work_spent
  assert_true(spent > 0L)
  prepare_request_program_module_body(
    parent,
    input,
    contracts,
    manifests~,
    compilation_limits~,
    retained_output=true,
    provider_factory=factory,
  ).unwrap()
  assert_true(
    physical_equal(
      parent.program_source_free.unwrap().compilation.unwrap(),
      artifact,
    ),
  )
  assert_eq(calls.val, 1)
  assert_eq(parent.program_artifact_work_spent, spent)
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "single-values-original",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  assert_true(
    physical_equal(
      installed_managed_run_compilation_original(run, prepared).unwrap(),
      artifact,
    ),
  )
  retire_installed_managed_run(run).unwrap()
  assert_eq(parent.program_artifact_work_spent, spent)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
