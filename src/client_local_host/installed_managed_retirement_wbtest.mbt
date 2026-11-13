///|
test "installed managed retirement tombstone rejects new borrows" {
  let assets = @publication_host.client_local_product_assets()
  let cid = "sha256:42e2125d9fbac72912fd67d8f619769810d5d4c606a362a4e569a89f32be54e0"
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    cid,
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let lowered = @frontend.lower(
    "SELECT 1 AS x",
    @frontend.Sql,
    Some(@frontend.bind_query_context([], cid).unwrap()),
    public_primary=true,
  ).unwrap()
  let prepared = @publication_host.prepare_effect_free_client_program(
    lowered.document,
    lowered.format,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared, cid, "retirement-tombstone",
  ).unwrap()
  // A terminal owner remains a nominal identity even after heavy fields clear.
  // Successful cleanup transition itself is exercised in physical_resources.
  let value : ClientInstalledManagedRun = {
    original: None,
    preparation: None,
    request,
    ledger: None,
    reads: [],
    content: NoContent,
    serialization_prefix: None,
    keyed_reads: [],
    effect_operations: [],
    effect_operation_opening: false,
    effect_operation_closing: false,
    effect_operation_controls: None,
    source_free_preparation: None,
    captured_preparation: None,
    preparation_retirement: None,
    source_free_captured: None,
    source_free_opening: false,
    publication_invocation_started: false,
    publication_definition: None,
    publication_invocation: None,
    publication_started: false,
    publication: None,
  }
  value.original = Some(value)
  value.source_free_opening = true
  assert_true(retire_installed_managed_run(value) is Err(CleanupPending))
  value.source_free_opening = false
  assert_true(retire_installed_managed_run(value) is Ok(_))
  assert_true(retire_installed_managed_run(value) is Ok(_))
  assert_true(require_installed_managed_run(value) is Err(Retired))
  assert_true(installed_managed_run_owner(value) is Err(Retired))
  assert_true(
    check_installed_managed_run(value, prepared, request) is Err(Retired),
  )
  assert_true(begin_installed_managed_run_source_read(value, 0) is Err(Retired))
  assert_true(
    borrow_installed_managed_dispatch_preparation(value, prepared, request)
    is Err(Retired),
  )
  assert_true(
    installed_managed_publication_dag(value, prepared) is Err(Retired),
  )
  assert_false(installed_preparation_payload_severed(value, request))
}
