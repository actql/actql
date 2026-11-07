///|
fn hubspot_mapping_initialization_ledger(limit : Int64) -> @resources.Ledger {
  @resources.create_ledger({
    planning_work: 10,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 1048576L,
    retained_bytes: limit,
    execution_bytes: limit,
  }).unwrap()
}

///|
test "HubSpot Mapping Common quote uses same actual initial reservation and shrinks only after success" {
  let ledger = hubspot_mapping_initialization_ledger(536870912L)
  let input = [1]
  let owner : @resources.PreparationCapacity[
    Array[Int],
    (Array[Int], @source_publication.PreparedPublishedQueryEnvironment),
  ] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    0L,
    0L,
    max_borrowers=2,
  ).unwrap()
  let native = client_program_hubspot_mapping_construction_capacity(
    2, 0, 24L, 100, 16, 256, 10000, 1000, 20,
  ).unwrap()
  let original = @execution.execution_capacity(0L, 0L).unwrap()
  let running = client_program_compose_installed_source_construction_capacity(
    original,
    [Some(native)],
  ).unwrap()
  @client_local_host.reserve_installed_source_construction(
    owner, input, running,
  ).unwrap()
  let peak = @execution.execution_capacity_execution_bytes(native)
  let retained = @execution.execution_capacity_retained_bytes(native)
  // The full possible failed prefix remains charged as retention as well.
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, peak)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, peak)
  let successful = client_program_installed_source_retained_construction_capacity(
      Some(native),
    )
    .unwrap()
    .unwrap()
  assert_true(
    @client_local_host.reconcile_installed_source_construction(
      owner,
      [1],
      successful,
    )
    is Err(@resources.ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, peak)
  @client_local_host.reconcile_installed_source_construction(
    owner, input, successful,
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, retained)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, retained)
  assert_true(peak > retained)
  // This component owns only synchronous pure constructor work; it acquired
  // no physical child. No public Client/FD/socket acknowledgement is implied.
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(owner, input).unwrap(),
  )
  assert_false(
    @resources.ledger_usage_has_pending_resources(
      @resources.ledger_usage(ledger),
    ),
  )
}

///|
test "HubSpot Mapping real initial Ledger refuses demand before native projection without changing quota" {
  let ledger = hubspot_mapping_initialization_ledger(1048576L)
  let input = [2]
  let owner : @resources.PreparationCapacity[
    Array[Int],
    (Array[Int], @source_publication.PreparedPublishedQueryEnvironment),
  ] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    0L,
    0L,
    max_borrowers=2,
  ).unwrap()
  let native = client_program_hubspot_mapping_construction_capacity(
    2, 0, 24L, 100, 16, 256, 10000, 1000, 20,
  ).unwrap()
  let running = client_program_compose_installed_source_construction_capacity(
    @execution.execution_capacity(0L, 0L).unwrap(),
    [Some(native)],
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let mut projects = 0
  match
    @client_local_host.reserve_installed_source_construction(
      owner, input, running,
    ) {
    Ok(_) => projects += 1
    Err(@resources.Resource(_)) => ()
    Err(_) => fail("Expected original Ledger capacity refusal")
  }
  assert_eq(projects, 0)
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(owner, input).unwrap(),
  )
  assert_false(
    @resources.ledger_usage_has_pending_resources(
      @resources.ledger_usage(ledger),
    ),
  )
}
