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
test "managed source-free preparation retains the quoted original sequences and scalar limits" {
  let prepared = source_free_tasks_original_union()
  let assets = @publication_host.client_local_product_assets()
  let installed = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let original = prepare_installed_managed_source_free_with_contracts(
    prepared,
    installed,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  let quoted = prepared_installed_managed_source_free_requirements(original)
  let legacy = installed_managed_run_requirements(
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
  for index in 0..<4 {
    assert_eq(quoted[index], legacy[index])
  }
  let configuration = original.configuration.unwrap()
  let mut required_retained = 0L
  let mut required_execution = 0L
  for task in 0..<@strategy.graph_task_count(configuration.graph) {
    let actual = @local_driver.local_dispatch_preparation_task_capacity(
      configuration.dispatch,
      task,
    ).unwrap()
    required_retained += actual.retained_bytes
    required_execution += actual.execution_bytes
  }
  assert_eq(quoted[4], required_retained)
  assert_eq(quoted[5], required_execution)
  assert_eq(quoted[1], 8L)
  quoted[0] = 0L
  assert_eq(prepared_installed_managed_source_free_requirements(original), [
    legacy[0],
    legacy[1],
    legacy[2],
    legacy[3],
    required_retained,
    required_execution,
  ])
  assert_true(
    installed_source_free_preparation_matches(
      original,
      Pure(prepared),
      installed,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ),
  )
  let retained = original.sequences
  ignore(prepared_installed_managed_source_free_requirements(original))
  assert_true(physical_equal(original.sequences, retained))
  assert_eq(retained.length(), 8)
}

///|
test "managed source-free preparation executes the same generated originals on one diagnostic Ledger" {
  let prepared = source_free_tasks_original_union()
  let assets = @publication_host.client_local_product_assets()
  let installed = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let original = prepare_installed_managed_source_free_with_contracts(
    prepared,
    installed,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  // Explicit unaccounted test storage only, not an operational Resource
  // admission. The production entry still requires its original admission.
  let ledger = @resources.create_ledger(original.limits).unwrap()
  let setup = open_checked_local_host(
    prepared,
    None,
    installed,
    assets.values,
    1L,
    0L,
    0L,
    0L,
    fragment_body=Some(assets.fragment),
    ordered_body=assets.ordered,
    retained_output=true,
    acquisition_ledger=Some(ledger),
    source_free_preparation=Some(original),
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  let execution = match
    execute_source_free_local_tasks_guarded(setup, 64, 100000, () => true) {
    Ok(value) => value
    Err(failure) => {
      retry_local_values_execution_failure_cleanup(failure) |> ignore
      fail("retained original UNION execution failed")
    }
  }
  assert_eq(execution.rows().unwrap(), ["{\"n\":1}", "{\"n\":2}"])
  assert_eq(@resources.ledger_usage(ledger).attempts, 8)
  assert_true(execution.close())
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}

///|
test "managed source-free preparation refuses a foreign owner or changed contract original" {
  let prepared = source_free_tasks_original_union()
  let assets = @publication_host.client_local_product_assets()
  let installed = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let original = prepare_installed_managed_source_free_with_contracts(
    prepared,
    installed,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  let foreign = source_free_tasks_original_union()
  assert_false(
    installed_source_free_preparation_matches(
      original,
      Pure(foreign),
      installed,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ),
  )
  let independent = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  assert_false(
    installed_source_free_preparation_matches(
      original,
      Pure(prepared),
      independent,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ),
  )
  for
    (values, fragment, ordered) in [
      ("{}", Some(assets.fragment), assets.ordered),
      (assets.values, None, assets.ordered),
      (assets.values, Some(assets.fragment), Some("{}")),
    ] {
    assert_false(
      installed_source_free_preparation_matches(
        original,
        Pure(prepared),
        installed,
        values,
        fragment,
        ordered,
      ),
    )
  }
  assert_true(
    prepare_installed_sequence_contracts(
      "{}",
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    )
    is Err(Unsupported),
  )
  // Use the independently authored Source Environment's declared identity;
  // do not retarget the historical helpers or their original failed vectors.
  guard @json.parse(source_query_original_environment) is Object(fields) &&
    fields.get("evidence_bundle_cid") is Some(String(cid)) else {
    fail("original Source Environment evidence")
  }
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let source = @publication_host.prepare_effect_free_client_program(
    source_query_original_document,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  assert_true(
    prepare_installed_managed_source_free_with_contracts(
      source,
      installed,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      retained_output=true,
      provider_factory=_ => [],
    )
    is Err(Unsupported),
  )
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
