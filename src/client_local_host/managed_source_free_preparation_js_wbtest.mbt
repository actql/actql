///|
test "managed ledger preparation retains its first capacity original through open and retirement" {
  let prepared = single_source_free_capacity_prepared()
  let assets = @publication_host.client_local_product_assets()
  let installed = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  // This explicit ordinary Root fixture supplies its original admission;
  // neither preparation nor reading its plan creates physical backing.
  let quote = installed_managed_run_requirements(
    prepared,
    [],
    "{}",
    "{}",
    [],
    [],
    installed,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let reference = capture_parent_original(
    publication_test_loader(publication_test_url()),
    prepared,
    FixedArray::from_array(quote),
  )
  let admission = @resources.prepare_node_managed_run_admission(
    reference, prepared,
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "first-capacity-original",
  ).unwrap()
  let run = begin_installed_managed_run(admission, prepared, request).unwrap()
  assert_true(run.source_free_preparation is None)
  let ledger = prepare_installed_managed_run_ledger(
    run,
    prepared,
    request,
    [],
    [],
    [],
    installed,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  guard run.source_free_preparation is Some(first) else {
    fail("the first checked plan must survive its Ledger projection")
  }
  let sequences = first.sequences
  let before = @resources.ledger_usage(ledger)
  assert_true(
    physical_equal(
      prepare_installed_managed_run_ledger(
        run,
        prepared,
        request,
        [],
        [],
        [],
        installed,
        assets.values,
        Some(assets.fragment),
        assets.ordered,
      ).unwrap(),
      ledger,
    ),
  )
  assert_true(physical_equal(run.source_free_preparation.unwrap(), first))
  let setup = open_installed_managed_source_free_host(
      run,
      prepared,
      request,
      installed,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      true,
    )
    .unwrap()
    .unwrap()
  assert_true(physical_equal(run.source_free_preparation.unwrap(), first))
  assert_true(physical_equal(first.sequences, sequences))
  assert_eq(@resources.ledger_usage(ledger).attempts, before.attempts)
  let execution = execute_source_free_local_tasks_guarded(setup, 64, 100000, () => {
    true
  }).unwrap()
  assert_eq(execution.rows().unwrap(), ["{\"id\":1}", "{\"id\":2}"])
  assert_true(execution.close())
  retire_installed_managed_run(run).unwrap()
  assert_true(run.source_free_preparation is None)
  assert_true(require_installed_managed_run(run) is Err(Retired))
}

///|
test "Pure prepared module selects its original factory before Run and never calls the late factory" {
  for retained_output in [false, true] {
    let prepared = single_source_free_capacity_prepared()
    let assets = @publication_host.client_local_product_assets()
    let contracts = prepare_installed_sequence_contracts(
      assets.registry,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ).unwrap()
    let prepared_calls = Ref(0)
    let late_calls = Ref(0)
    let original = prepare_installed_managed_source_free_with_contracts(
      prepared,
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      retained_output~,
      provider_factory=_ => {
        prepared_calls.val += 1
        []
      },
    ).unwrap()
    assert_eq(prepared_calls.val, 1)
    let selected = original.configuration.unwrap()
    let quote = prepared_installed_managed_source_free_requirements(original)
    ignore(prepared_installed_managed_source_free_requirements(original))
    assert_eq(prepared_calls.val, 1)
    let request = @publication_host.prepare_source_free_client_request_identity(
      prepared,
      "sha256:" + "a".repeat(64),
      "pure-module-original",
    ).unwrap()
    // Explicit imported admission ports, not a physical allocator/ACK fixture.
    let reference = capture_parent_original(
      publication_test_loader(publication_test_url()),
      prepared,
      FixedArray::from_array(quote),
    )
    let admission = @resources.prepare_node_managed_run_admission(
      reference, prepared,
    ).unwrap()
    let raw = source_free_installed_managed_preparation_owned(
      Pure(prepared),
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      false,
    ).unwrap()
    assert_true(
      begin_prepared_installed_managed_source_free_run(
        admission, prepared, request, raw,
      )
      is Err(ForeignOriginal),
    )
    let run = begin_prepared_installed_managed_source_free_run(
      admission, prepared, request, original,
    ).unwrap()
    assert_true(
      open_installed_managed_source_free_host(
        run,
        prepared,
        request,
        contracts,
        assets.values,
        Some(assets.fragment),
        assets.ordered,
        !retained_output,
      )
      is Err(ForeignOriginal),
    )
    assert_true(run.source_free_captured is None)
    let host = open_installed_managed_source_free_host(
        run,
        prepared,
        request,
        contracts,
        assets.values,
        Some(assets.fragment),
        assets.ordered,
        retained_output,
        provider_factory=_ => {
          late_calls.val += 1
          []
        },
      )
      .unwrap()
      .unwrap()
    assert_eq(prepared_calls.val, 1)
    assert_eq(late_calls.val, 0)
    let installed = @builtin.configured_local_module(
      @builtin.configured_host_modules(host),
    ).unwrap()
    assert_true(
      physical_equal(
        @local_driver.local_dispatch_original_preparation(installed).unwrap(),
        selected.dispatch,
      ),
    )
    assert_true(
      open_installed_managed_source_free_host(
        run,
        prepared,
        request,
        contracts,
        assets.values,
        Some(assets.fragment),
        assets.ordered,
        retained_output,
      )
      is Err(AlreadyBound),
    )
    let execution = if retained_output {
      execute_source_free_local_tasks_guarded(host, 64, 100000, () => true).unwrap()
    } else {
      execute_source_free_values_guarded(host, 64, 100000, () => true).unwrap()
    }
    assert_eq(execution.rows().unwrap(), ["{\"id\":1}", "{\"id\":2}"])
    assert_true(execution.close())
    retire_installed_managed_run(run).unwrap()
    assert_true(run.source_free_preparation is None)
    assert_eq(prepared_calls.val, 1)
    assert_eq(late_calls.val, 0)
  }
}

///|
test "Pure prepared failed module binding retains the only issued graph until original retirement" {
  let prepared = single_source_free_capacity_prepared()
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let calls = Ref(0)
  let original = prepare_installed_managed_source_free_with_contracts(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    retained_output=true,
    provider_factory=_ => {
      calls.val += 1
      []
    },
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "pure-module-bind-failure",
  ).unwrap()
  let reference = capture_parent_original(
    publication_test_loader(publication_test_url()),
    prepared,
    FixedArray::from_array(
      prepared_installed_managed_source_free_requirements(original),
    ),
  )
  let admission = @resources.prepare_node_managed_run_admission(
    reference, prepared,
  ).unwrap()
  let run = begin_prepared_installed_managed_source_free_run(
    admission, prepared, request, original,
  ).unwrap()
  // This is module registration liveness, not Account/current authority.
  @connector.close_capability_registry(original.configuration.unwrap().registry)
  assert_true(
    open_installed_managed_source_free_host(
      run,
      prepared,
      request,
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      true,
    )
    is Ok(None),
  )
  let issued = run.source_free_captured.unwrap()
  assert_true(
    open_installed_managed_source_free_host(
      run,
      prepared,
      request,
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      true,
    )
    is Err(AlreadyBound),
  )
  assert_true(physical_equal(run.source_free_captured.unwrap(), issued))
  assert_eq(calls.val, 1)
  assert_eq(@resources.ledger_usage(run.ledger.unwrap()).attempts, 0)
  retire_installed_managed_run(run).unwrap()
  assert_true(run.source_free_preparation is None)
  assert_true(run.source_free_captured is None)
}
