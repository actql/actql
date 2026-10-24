///|
test "installed managed retirement tombstone rejects new borrows" {
  let assets = @publication_host.client_local_product_assets()
  let cid = "sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f"
  let environment = @publication_host.admit_client_check_environment(
    assets.environment, cid,
    { text_time: true, veca: false },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false },
  ).unwrap()
  let lowered = @frontend.lower("SELECT 1 AS x", @frontend.Sql,
    Some(@frontend.bind_query_context([], cid).unwrap()), public_primary=true).unwrap()
  let prepared = @publication_host.prepare_effect_free_client_program(
    lowered.document, lowered.format, environment, None,
    @publication_host.client_standard_program_preparation_limits()).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared, cid, "retirement-tombstone").unwrap()
  // A terminal owner remains a nominal identity even after heavy fields clear.
  // Successful cleanup transition itself is exercised in physical_resources.
  let value : ClientInstalledManagedRun = {
    original: None, preparation: None, request, ledger: None,
    reads: [], keyed: None, keyed_reads: [], source_free_preparation: None, preparation_retirement: None,
  }
  value.original = Some(value)
  assert_true(retire_installed_managed_run(value) is Ok(_))
  assert_true(retire_installed_managed_run(value) is Ok(_))
  assert_true(require_installed_managed_run(value) is Err(Retired))
  assert_true(installed_managed_run_owner(value) is Err(Retired))
  assert_true(check_installed_managed_run(value, prepared, request) is Err(Retired))
  assert_true(begin_installed_managed_run_source_read(value, 0) is Err(Retired))
  assert_true(borrow_installed_managed_dispatch_preparation(value, prepared, request) is Err(Retired))
  assert_false(installed_preparation_payload_severed(value, request))
}
