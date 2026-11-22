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
test "HubSpot shared Source constructor retains exact digest and target quantities" {
  let identity = client_program_hubspot_metadata_identity_capacity(2, 100L, 10L).unwrap()
  let target = client_program_hubspot_read_target_capacity(2, 6L).unwrap()
  // Independent original inventory: two CID nodes plus 71 text units,
  // identity render peak for 31 nodes/672 units, and 27 target slots.
  assert_eq(@execution.execution_capacity_retained_bytes(identity), 1080L)
  assert_eq(@execution.execution_capacity_execution_bytes(identity), 379968L)
  assert_eq(@execution.execution_capacity_retained_bytes(target), 6912L)
  assert_eq(@execution.execution_capacity_execution_bytes(target), 13824L)
  for capacity in [identity, target] {
    let r = @execution.execution_capacity_retained_bytes(capacity)
    let e = @execution.execution_capacity_execution_bytes(capacity)
    for (r_short, e_short) in [(0L, 0L), (1L, 0L), (0L, 1L)] {
      let ledger = @resources.create_ledger({
        planning_work: 0,
        attempts: 1,
        holdings: 0,
        transfer_bytes: 0L,
        retained_bytes: r - r_short,
        execution_bytes: e - e_short,
      }).unwrap()
      let result = @resources.reserve_attempt(ledger, 0L, r, e)
      if r_short == 1L {
        assert_true(result is Err(@resources.RetentionLimit))
      } else if e_short == 1L {
        assert_true(result is Err(@resources.ExecutionLimit))
      } else {
        @resources.settle_reservation(ledger, result.unwrap()).unwrap()
      }
      assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
    }
  }
  assert_true(
    client_program_hubspot_metadata_identity_capacity(1, 0L, -1L)
    is Err(@resources.InvalidExtent),
  )
  assert_true(
    client_program_hubspot_read_target_capacity(1, 9223372036854775807L)
    is Err(@resources.InvalidExtent),
  )
}

///|
test "HubSpot shared Source constructor preserves independent response and target bounds" {
  assert_eq(
    client_program_hubspot_read_sequence_bounds(8, 8192, 22, 1, 9, 21L).unwrap(),
    (65536, 1342),
  )
  assert_eq(
    client_program_hubspot_read_sequence_bounds(
      2, 1073741823, 1, 1, 1, 357913767L,
    ).unwrap(),
    (2147483646, 2147483644),
  )
  assert_true(
    client_program_hubspot_read_sequence_bounds(
      2, 1073741824, 1, 1, 1, 357913767L,
    )
    is Err(@resources.InvalidExtent),
  )
  assert_true(
    client_program_hubspot_read_sequence_bounds(
      2, 1073741823, 1, 1, 1, 357913768L,
    )
    is Err(@resources.InvalidExtent),
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

///|
test "HubSpot managed tiny input does not reserve future rows pages or requests" {
  let protocol = [
    4096, 1000, 20, 10, 100, 2, 2, 5, 1, 3, 64, 100, 4096, 4096, 100, 10,
  ]
  let wider = protocol.copy()
  wider[5] = 1000000
  wider[6] = 1000000
  wider[7] = 1000003
  let selected = @hubspot_catalog.source_read_construction_capacity(
    protocol,
    4096,
    [],
  ).unwrap()
  let initial = @hubspot_catalog.source_read_construction_capacity(
    wider,
    4096,
    [],
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_execution_bytes(selected),
    @execution.execution_capacity_execution_bytes(initial),
  )
  let limit = @execution.execution_capacity_execution_bytes(initial)
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
    [Some(initial)],
  ).unwrap()
  @client_local_host.reserve_installed_source_construction(
    owner, input, running,
  ).unwrap()
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(owner, input).unwrap(),
  )
  let small = @hubspot_catalog.source_read_construction_capacity(
    protocol,
    4096,
    [32],
  ).unwrap()
  let large = @hubspot_catalog.source_read_construction_capacity(wider, 4096, [
    32,
  ]).unwrap()
  assert_eq(
    @execution.execution_capacity_execution_bytes(small),
    @execution.execution_capacity_execution_bytes(large),
  )
}

///|
test "HubSpot query construction is separately funded on the same reader without a body allowance" {
  let limits = [
    4096, 20480, 1000, 20, 1, 2, 5, 1, 64, 4096, 7000, 100, 4096, 4096, 100, 10,
  ]
  let native = @execution.execution_capacity(0L, 0L)
  let original = @client_local_host.installed_native_source_reader_capacity(
    limits, 3, 128, native,
  ).unwrap()
  let query = @client_local_host.installed_native_source_reader_capacity(
    limits,
    3,
    128,
    native,
    max_query_bytes=6767,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(query) >
    @execution.execution_capacity_retained_bytes(original),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(query) >
    @execution.execution_capacity_execution_bytes(original),
  )
  for bound in [-1, 7001] {
    assert_true(
      @client_local_host.installed_native_source_reader_capacity(
        limits,
        3,
        128,
        native,
        max_query_bytes=bound,
      )
      is None,
    )
  }
  assert_true(
    @client_local_host.installed_native_source_reader_capacity(
      limits,
      3,
      128,
      None,
      max_query_bytes=6767,
    )
    is None,
  )
}
