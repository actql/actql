///|
// Actual ordinary Root import with no physical Source opened. This tests the
// existing admission/Ledger consumer, not native backing or a database read.
extern "js" fn capture_parent_original(
  loader : PublicationTestLoader,
  prepared : @publication_host.PreparedClientProgram,
  quote : FixedArray[Int64],
) -> @resources.OriginalNodeManagedRunReference =
  #|(loader,prepared,quote) => loader('../../../../../adapters/host-node/ordinary-node-resource-runtime.cjs').retainOrdinaryManagedRun(prepared,{planningWork:Number(quote[0]),attempts:Number(quote[1]),holdings:Number(quote[2]),transferBytes:quote[3],retainedBytes:quote[4],executionBytes:quote[5]},()=>{},()=>false)

///|
extern "js" fn capture_parent_contract(
  loader : PublicationTestLoader,
  name : String,
) -> String =
  #|(loader,name) => loader('node:fs').readFileSync(loader.resolve('../../../../../spec/contracts/'+name),'utf8')

///|
test "ordinary DuckDB capture demand uses the same admitted parent Ledger and refuses one-short capacity" {
  let prepared = installed_source_read_prepared_fixture()
  let requirement = original_row_requirement(prepared)
  let loader = publication_test_loader(publication_test_url())
  let pending = prepare_client_duckdb_capture_capacity(
    requirement,
    "main",
    "records",
    capture_parent_contract(loader, "actql-query-acquisition.json"),
    capture_parent_contract(loader, "actql-query-process-evidence.json"),
    capture_parent_contract(loader, "actql-query-two-receipt.json"),
  ).unwrap()
  let capacity = installed_pending_duckdb_capture_capacity(pending)
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let quote = installed_managed_capture_run_requirements(
    prepared,
    [capacity],
    [4096L],
    [2048L],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let request = @publication_host.prepare_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "capture-parent",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  let original = capture_parent_original(
    loader,
    prepared,
    FixedArray::makei(quote.length(), i => quote[i]),
  )
  let admission = @resources.prepare_node_managed_run_admission(
    original, prepared,
  ).unwrap()
  let run = begin_installed_managed_run(admission, prepared, request).unwrap()
  let ledger = prepare_installed_managed_run_ledger(
    run,
    prepared,
    request,
    [capacity],
    [4096L],
    [2048L],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  assert_true(
    physical_equal(ledger, require_installed_managed_run(run).unwrap()),
  )
  let foreign_request = @publication_host.prepare_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "capture-parent-other",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  assert_true(
    check_installed_managed_run(run, prepared, foreign_request)
    is Err(ForeignOriginal),
  )
  assert_true(
    check_installed_managed_run(
      run,
      installed_source_read_prepared_fixture(),
      request,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  retire_installed_managed_run(run).unwrap()
  assert_true(require_installed_managed_run(run) is Err(Retired))
  let short_quote = quote.map(value => value)
  short_quote[4] -= 1L
  let short_original = capture_parent_original(
    loader,
    prepared,
    FixedArray::makei(short_quote.length(), i => short_quote[i]),
  )
  let short_admission = @resources.prepare_node_managed_run_admission(
    short_original, prepared,
  ).unwrap()
  let short_run = begin_installed_managed_run(
    short_admission, prepared, request,
  ).unwrap()
  assert_true(
    prepare_installed_managed_run_ledger(
      short_run,
      prepared,
      request,
      [capacity],
      [4096L],
      [2048L],
      contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    )
    is Err(InsufficientCapacity),
  )
  retire_installed_managed_run(short_run).unwrap()
}

///|
test "ordinary captured parent preserves RowSource binding and pending-child retirement" {
  let prepared = installed_source_read_prepared_fixture()
  let capacity = installed_row_capture_capacity(
    original_row_acquisition_fixture(original_row_requirement(prepared)),
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let quote = installed_managed_capture_run_requirements(
    prepared,
    [capacity],
    [4096L],
    [2048L],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let request = @publication_host.prepare_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "row-parent",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  let original = capture_parent_original(
    publication_test_loader(publication_test_url()),
    prepared,
    FixedArray::makei(quote.length(), i => quote[i]),
  )
  let admission = @resources.prepare_node_managed_run_admission(
    original, prepared,
  ).unwrap()
  let run = begin_installed_managed_run(admission, prepared, request).unwrap()
  assert_true(
    prepare_installed_managed_run_ledger(
      run,
      prepared,
      request,
      [capacity],
      [4096L],
      [2048L],
      contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    )
    is Err(ForeignOriginal),
  )
  let read = begin_installed_managed_run_source_read(run, 0).unwrap()
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(run).unwrap()
  assert_true(require_installed_managed_run(run) is Err(Retired))
}
