///|
// Existing checked environment with an independently authored source-free
// Program. These quote tests supply no operational admission or test Ledger.
fn source_free_managed_prepared_fixture(
  document? : String = (
    #|{"version":"actql/0.1","id":"source-free-managed","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"}],"results":{"rows":{"from":"seed","fields":["id"]}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
  ),
) -> @publication_host.PreparedClientProgram {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
test "source-free managed Run quotes the existing Local output envelope without a Source" {
  let source_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let prepared = source_free_managed_prepared_fixture()
  assert_true(installed_managed_run_purpose_supported(prepared))
  let required = installed_managed_run_requirements(
    prepared,
    [],
    "",
    "",
    [],
    [],
    source_contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  // One task/holding and one 1MB transfer, with the existing finite 512MiB
  // runtime retention/execution policy. These ceilings are not initial demand.
  assert_eq(required, [100000L, 1L, 1L, 1000000L, 536870912L, 536870912L])
}

///|
test "source-free managed Run refuses supplied Source transport and changed registry" {
  let source_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let prepared = source_free_managed_prepared_fixture()
  assert_true(
    installed_managed_run_requirements(
      prepared,
      [],
      "",
      "",
      [1L],
      [],
      source_contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    )
    is Err(Unsupported),
  )
  assert_true(
    prepare_installed_sequence_contracts(
      "{}",
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    )
    is Err(Unsupported),
  )
}

///|
test "managed Run requires the actual declaration for a single Source instead of treating it as source-free" {
  let source_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let prepared = installed_source_read_prepared_fixture()
  assert_true(installed_managed_run_purpose_supported(prepared))
  assert_true(
    installed_managed_run_requirements(
      prepared,
      [],
      "",
      "",
      [],
      [],
      source_contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    )
    is Err(Unsupported),
  )
}

///|
test "local Mock quote does not relabel ordinary Compute or serialized Model as its purpose" {
  let source_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let plain = source_free_managed_prepared_fixture()
  let (serialized, _, _, _) = original_prefix_execution_fixture()
  for prepared in [plain, serialized] {
    assert_true(!installed_managed_run_shape_supported(prepared, true))
    assert_true(
      installed_mock_model_run_requirements(
        prepared,
        [],
        "",
        "",
        [],
        [],
        source_contracts,
        source_query_original_values,
        Some(source_query_original_fragment),
        None,
      )
      is Err(Unsupported),
    )
  }
  // The existing Compute entry is unchanged, not made dependent on a Model
  // purpose or granted one merely by this shared requirement calculation.
  assert_true(installed_managed_run_purpose_supported(plain))
}

///|
// Projection tests use the existing unaccounted test Ledger, not an installed
// Run, a physical supplier or permission. The public entry additionally requires
// its exact live nominal Run; ordinary callers obtain that original from Host.
test "managed Run usage projection preserves all limits and live Ledger counters" {
  let ledger = @resources.create_ledger({
    planning_work: 10,
    attempts: 3,
    holdings: 2,
    transfer_bytes: 1000L,
    retained_bytes: 2000L,
    execution_bytes: 3000L,
  }).unwrap()
  @resources.charge_planning(ledger, 7).unwrap()
  let reservation = @resources.reserve_attempt(ledger, 400L, 500L, 600L).unwrap()
  @resources.charge_transfer(ledger, reservation, 100L).unwrap()
  @resources.mark_transfer_uncertain(ledger, reservation, 50L).unwrap()
  let holding = @resources.retain_allocation(ledger, reservation, 200L).unwrap()
  let live = installed_managed_run_accounting_values(ledger)
  assert_eq(live, [
    10L, 3L, 2L, 1000L, 2000L, 3000L, 7L, 1L, 0L, 1L, 1L, 0L, 100L, 50L, 250L, 200L,
    300L, 600L, 500L,
  ])
  // Observation neither settles reservations nor retires the actual holding.
  assert_eq(installed_managed_run_accounting_values(ledger), live)
  @resources.settle_reservation(ledger, reservation).unwrap()
  assert_eq(installed_managed_run_accounting_values(ledger), [
    10L, 3L, 2L, 1000L, 2000L, 3000L, 7L, 1L, 0L, 1L, 0L, 0L, 100L, 50L, 0L, 200L,
    0L, 0L, 500L,
  ])
  @resources.release_allocation(ledger, holding).unwrap()
  assert_eq(installed_managed_run_accounting_values(ledger), [
    10L, 3L, 2L, 1000L, 2000L, 3000L, 7L, 1L, 0L, 0L, 0L, 0L, 100L, 50L, 0L, 0L,
    0L, 0L, 500L,
  ])
  assert_eq(live[14], 250L)
  assert_eq(live[15], 200L)
  assert_eq(live[10], 1L)
}

///|
test "managed Run usage projection returns independent exact Int64 snapshots" {
  let ledger = @resources.create_ledger({
    planning_work: 1,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 9007199254740993L,
    retained_bytes: 9007199254740995L,
    execution_bytes: 9007199254740997L,
  }).unwrap()
  let first = installed_managed_run_accounting_values(ledger)
  first[3] = 0L
  first[18] = -1L
  let reservation = @resources.reserve_attempt(
    ledger, 9007199254740993L, 9007199254740995L, 9007199254740997L,
  ).unwrap()
  let again = installed_managed_run_accounting_values(ledger)
  assert_eq(again[3], 9007199254740993L)
  assert_eq(again[4], 9007199254740995L)
  assert_eq(again[5], 9007199254740997L)
  assert_eq(again[14], 9007199254740993L)
  assert_eq(again[16], 9007199254740995L)
  assert_eq(again[17], 9007199254740997L)
  assert_eq(again[18], 9007199254740995L)
  assert_eq(first[7], 0L)
  assert_eq(first[18], -1L)
  @resources.settle_reservation(ledger, reservation).unwrap()
}
