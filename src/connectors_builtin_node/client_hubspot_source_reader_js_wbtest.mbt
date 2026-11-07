///|
fn hubspot_managed_reader_quote(
  received : Array[Int],
) -> @execution.ExecutionCapacity? {
  client_program_hubspot_source_reader_capacity(
    [
      4096, 20480, 1000, 20, 1, 2, 5, 1, 64, 4096, 4096, 100, 4096, 4096, 100, 10,
    ],
    3,
    128,
    [4096, 1000, 20, 10, 100, 2, 2, 5, 1, 3, 64, 100, 4096, 4096, 100, 10],
    4096,
    received,
  )
}

///|
test "HubSpot managed original reader grows complete received prefixes without a private allowance" {
  let initial = hubspot_managed_reader_quote([]).unwrap()
  let first = hubspot_managed_reader_quote([32]).unwrap()
  let later = hubspot_managed_reader_quote([32, 128, 256, 128]).unwrap()
  assert_true(@execution.execution_capacity_retained_bytes(initial) > 0L)
  assert_true(
    @execution.execution_capacity_retained_bytes(first) >
    @execution.execution_capacity_retained_bytes(initial),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(later) >
    @execution.execution_capacity_execution_bytes(first),
  )
  assert_true(hubspot_managed_reader_quote([4097]) is None)
  assert_true(hubspot_managed_reader_quote([-1]) is None)
  assert_true(hubspot_managed_reader_quote([1, 1, 1, 1, 1, 1]) is None)
  assert_true(
    client_program_hubspot_source_reader_capacity([], 3, 128, [], 1, []) is None,
  )
}

///|
test "HubSpot managed reader real Ledger rejects one-short before native response projection" {
  let quote = hubspot_managed_reader_quote([32, 128]).unwrap()
  let peak = @execution.execution_capacity_execution_bytes(quote)
  for limit in [peak - 1L, peak] {
    let ledger = hubspot_mapping_initialization_ledger(limit)
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
    let running = client_program_compose_installed_source_construction_capacity(
      @execution.execution_capacity(0L, 0L).unwrap(),
      [Some(quote)],
    ).unwrap()
    let before = @resources.ledger_usage(ledger)
    let mut entered = 0
    match
      @client_local_host.reserve_installed_source_construction(
        owner, input, running,
      ) {
      Ok(_) => entered += 1
      Err(@resources.Resource(_)) => ()
      Err(_) => fail("Expected same original Ledger refusal")
    }
    assert_eq(entered, if limit == peak { 1 } else { 0 })
    if limit < peak {
      assert_eq(@resources.ledger_usage(ledger), before)
    }
    assert_true(
      @resources.abort_preparation_capacity_after_cleanup(owner, input).unwrap(),
    )
  }
}
