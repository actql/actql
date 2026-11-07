///|
// Actual original Program/requirements and existing keyed constructor. This
// is completed DATA reuse, not provider I/O, allocation or permission proof.
test "keyed Content keeps the completed original requirements during later ledger selection" {
  let (source, _, _, declaration) = split_keyed_content_limits_fixture()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let (_, execution, measurement) = client_local_execution_limits(max_rows=3)
  let prefix = client_acquired_serialization_prefix_capacity(
    source.prepared,
    source.task,
    source.step,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    execution,
    measurement,
  ).unwrap()
  let selected = prepare_installed_managed_keyed_content(
    source.prepared,
    source.direct,
    source.keyed,
    declaration,
    original_keyed_child_limits(),
    [8192L, 8192L],
    [4096L, 4096L],
    4096,
    1000000,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    source.task,
    source.step,
    @execution.execution_capacity_retained_bytes(prefix),
    @execution.execution_capacity_execution_bytes(prefix),
  ).unwrap()
  let actual = installed_managed_keyed_content_limits(
    selected,
    source.prepared,
    source.direct,
    8192L,
    4096L,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  assert_true(physical_equal(actual, selected.limits))
}

///|
test "keyed Content changed or foreign quote inputs require their own full preparation" {
  let (parent, input, prepared, selected, request) = request_content_fixture()
  let contracts = selected.installed_contracts
  let read = (
    capacity,
    contract,
    transfer,
    executing,
    values,
    fragment,
    ordered,
  ) => {
    installed_managed_keyed_content_limits(
      selected, prepared, capacity, transfer, executing, contract, values, fragment,
      ordered,
    )
  }
  assert_true(
    read(
      selected.direct,
      contracts,
      8193L,
      4096L,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    )
    is None,
  )
  assert_true(
    read(
      selected.direct,
      contracts,
      8192L,
      4097L,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    )
    is None,
  )
  let copied = { ..selected.direct, }
  assert_true(
    read(
      copied,
      contracts,
      8192L,
      4096L,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    )
    is None,
  )
  assert_true(
    read(
      selected.direct,
      contracts,
      8192L,
      4096L,
      source_query_original_values,
      None,
      None,
    )
    is None,
  )
  assert_true(
    read(
      selected.direct,
      contracts,
      8192L,
      4096L,
      "foreign-values",
      Some(source_query_original_fragment),
      None,
    )
    is None,
  )
  let other = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  assert_true(
    read(
      selected.direct,
      other,
      8192L,
      4096L,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    )
    is None,
  )
  let (task, step) = @publication_host.prepared_client_serialization_occurrences(
      prepared,
    )[0]
  let (_, execution, measurement) = client_local_execution_limits(max_rows=3)
  let prefix = client_acquired_serialization_prefix_capacity(
    prepared,
    task,
    step,
    other,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    execution,
    measurement,
  ).unwrap()
  let admitted = prepare_installed_managed_keyed_content(
    prepared,
    copied,
    selected.keyed,
    selected.declaration,
    selected.row_limits,
    [8193L, 8192L],
    [4096L, 4096L],
    4096,
    1000000,
    other,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    task,
    step,
    @execution.execution_capacity_retained_bytes(prefix),
    @execution.execution_capacity_execution_bytes(prefix),
  ).unwrap()
  let distinct = installed_managed_keyed_content_limits(
    admitted,
    prepared,
    copied,
    8193L,
    4096L,
    other,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  assert_true(physical_equal(distinct, admitted.limits))
  assert_false(physical_equal(distinct, selected.limits))
  complete_request_content_preparation(parent, input, request, selected).unwrap()
  let run = begin_request_content_managed_run(parent, request).unwrap()
  retire_installed_managed_run(run).unwrap()
}

///|
test "same-parent keyed Content Core tuple and later ledger keep the selected originals" {
  let calls = Ref(0)
  let (parent, input, prepared, selected, request) = request_content_fixture(current=() => {
    calls.val += 1
    true
  })
  complete_request_content_preparation(parent, input, request, selected).unwrap()
  let run = begin_request_content_managed_run(parent, request).unwrap()
  // The existing C WholeSource input-kind/publication getter assertions are
  // retained as an unexecuted required consumer fixture in the source handoff.
  // This public-base component proves only the original Core tuple/ledger.
  let before = calls.val
  let (read, requirement, acquisition, capacity) = begin_installed_managed_capture_source_read(
    run,
    prepared,
    request,
    selected.declaration,
    selected.direct_stage,
  ).unwrap()
  assert_eq(calls.val, before + 1)
  assert_true(physical_equal(capacity, selected.direct))
  assert_true(physical_equal(requirement, selected.direct.requirement))
  assert_true(
    selected.direct.acquisition is Some(original) &&
    physical_equal(original, acquisition),
  )
  let before = calls.val
  let ledger = prepare_installed_managed_run_ledger(
    run,
    prepared,
    request,
    [capacity],
    [8192L],
    [4096L],
    selected.installed_contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  assert_eq(calls.val, before + 1)
  assert_true(physical_equal(ledger, parent.ledger))
  assert_true(
    physical_equal(
      installed_managed_keyed_content_limits(
        selected,
        prepared,
        capacity,
        8192L,
        4096L,
        selected.installed_contracts,
        source_query_original_values,
        Some(source_query_original_fragment),
        None,
      ).unwrap(),
      selected.limits,
    ),
  )
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
}

///|
test "keyed Content Source tuple does not escape after current retires its selected payload" {
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (parent, input, prepared, selected, request) = request_content_fixture(current=() => {
    if action.val is Some(run) {
      action.val = None
      run()
    }
    true
  })
  complete_request_content_preparation(parent, input, request, selected).unwrap()
  let run = begin_request_content_managed_run(parent, request).unwrap()
  let retired = Ref(false)
  action.val = Some(() => {
    retired.val = retire_installed_managed_run(run) is Ok(_)
  })
  assert_true(
    begin_installed_managed_capture_source_read(
      run,
      prepared,
      request,
      selected.declaration,
      selected.direct_stage,
    )
    is Err(_),
  )
  assert_true(retired.val)
  assert_true(run.ledger is None && run.content is NoContent)
  assert_true(run.reads.is_empty())
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
}
