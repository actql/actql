///|
test "original configured module transfers to actual managed Run and survives until last manager borrow" {
  let (owner, ledger, environment, public_environment, contracts, manifests) = closed_module_fixture()
  let calls = Ref(0)
  prepare_closed_values_module_body(
    owner,
    environment,
    public_environment,
    contracts,
    manifests,
    retained_output=false,
    provider_factory=_ => {
      calls.val += 1
      []
    },
    family_retained=closed_module_no_family,
    family_array=closed_module_empty_factory_array,
    family_temporary=closed_module_no_family,
  ).unwrap()
  let prepared = owner.prepared.unwrap()
  let original = owner.source_free.unwrap()
  let original_module = original.configuration.unwrap()
  let manager = complete_closed_values_body(owner).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "module-original-request",
  ).unwrap()
  let run = begin_closed_values_owned_run(owner, prepared, request).unwrap()
  assert_true(
    physical_equal(require_installed_managed_run(run).unwrap(), ledger),
  )
  assert_true(physical_equal(run.source_free_preparation.unwrap(), original))
  let setup = open_installed_managed_source_free_host(
      run,
      prepared,
      request,
      contracts,
      contracts.original.values_body,
      contracts.original.fragment_body,
      contracts.original.ordered_body,
      false,
    )
    .unwrap()
    .unwrap()
  assert_true(
    physical_equal(
      run.source_free_preparation.unwrap().configuration.unwrap(),
      original_module,
    ),
  )
  assert_eq(calls.val, 1)
  let execution = execute_source_free_local_tasks_guarded(setup, 64, 100000, () => {
    true
  }).unwrap()
  assert_eq(execution.rows().unwrap(), ["{\"id\":1}"])
  assert_true(execution.close())
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(sever_closed_values_body(owner, manager))
  assert_true(@resources.return_preparation_body_borrow(manager).unwrap())
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_true(run.source_free_preparation is None)
}
