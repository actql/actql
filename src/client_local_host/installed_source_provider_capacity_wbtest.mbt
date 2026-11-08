///|
test "same Source native constructor quantities remain retained through original material retirement" {
  let source = @execution.execution_capacity(11L, 13L).unwrap()
  let provider = @execution.execution_capacity(5L, 7L).unwrap()
  let combined = compose_installed_source_construction_capacity(source, [
    provider,
  ]).unwrap()
  // Native peak7 is retained on this SAME Source, not just provider's5
  // output or an unbacked later callback. Shared addition owns overflow.
  assert_eq(@execution.execution_capacity_retained_bytes(combined), 18L)
  assert_eq(@execution.execution_capacity_execution_bytes(combined), 20L)
  let same = compose_installed_source_construction_capacity(source, []).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(same), 11L)
  assert_eq(@execution.execution_capacity_execution_bytes(same), 13L)
  let maximum = @execution.execution_capacity(
    9223372036854775807L, 9223372036854775807L,
  ).unwrap()
  assert_true(
    compose_installed_source_construction_capacity(source, [maximum]) is None,
  )
}

///|
test "retained Source constructor DATA cannot invent a completion or refund original work" {
  let original = @execution.execution_capacity(5L, 7L).unwrap()
  let retained = retained_installed_source_construction_capacity(original)
  assert_eq(@execution.execution_capacity_retained_bytes(original), 5L)
  assert_eq(@execution.execution_capacity_execution_bytes(original), 7L)
  assert_eq(@execution.execution_capacity_retained_bytes(retained), 5L)
  assert_eq(@execution.execution_capacity_execution_bytes(retained), 5L)
  let before = compose_installed_source_construction_capacity(
    @execution.execution_capacity(11L, 13L).unwrap(),
    [original],
  ).unwrap()
  let after = compose_installed_source_construction_capacity(
    @execution.execution_capacity(11L, 13L).unwrap(),
    [retained],
  ).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(before), 18L)
  assert_eq(@execution.execution_capacity_execution_bytes(before), 20L)
  assert_eq(@execution.execution_capacity_retained_bytes(after), 16L)
  assert_eq(@execution.execution_capacity_execution_bytes(after), 18L)
}

///|
test "native JSON recipe separates the same original peak from one returned tree" {
  // Independent tariff vector: the old full parse envelope is twice
  // (4*7 node slots*256 + 12*31 text bytes*8 + 41 buffer bytes).
  let original = installed_source_json_construction_capacity(
    7L, 31L, 41L, 5L, 13L,
  ).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(original), 1384L)
  assert_eq(@execution.execution_capacity_execution_bytes(original), 20370L)
  let prefix = @execution.execution_capacity(11L, 11L).unwrap()
  let pending = compose_installed_source_construction_capacity(prefix, [
    original,
  ]).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(pending), 20381L)
  let completed = retained_installed_source_construction_capacity(original)
  let after = compose_installed_source_construction_capacity(prefix, [completed]).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(after), 1395L)
  assert_eq(@execution.execution_capacity_execution_bytes(after), 1395L)
  // DATA projection alone cannot alter a pending original quote.
  assert_eq(@execution.execution_capacity_retained_bytes(pending), 20381L)
}

///|
test "native JSON recipe refuses negative overflow and impossible returned material" {
  for
    args in [
      (-1L, 31L, 41L, 5L, 13L),
      (7L, -1L, 41L, 5L, 13L),
      (7L, 31L, -1L, 5L, 13L),
      (7L, 31L, 41L, -1L, 13L),
      (7L, 31L, 41L, 5L, -1L),
      (9223372036854775807L, 31L, 41L, 5L, 13L),
      (7L, 9223372036854775807L, 41L, 5L, 13L),
      (7L, 31L, 9223372036854775807L, 5L, 13L),
      (7L, 31L, 41L, 500L, 13L),
    ] {
    let (nodes, units, bytes, returned_nodes, returned_text) = args
    assert_true(
      installed_source_json_construction_capacity(
        nodes, units, bytes, returned_nodes, returned_text,
      )
      is None,
    )
  }
}

///|
test "native JSON completion shrinks only its same real Source reservation" {
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 30000L,
    execution_bytes: 30000L,
  }).unwrap()
  let input = [1]
  let owner : @resources.PreparationCapacity[
    Array[Int],
    (Unit, @source_publication.PreparedPublishedQueryEnvironment),
  ] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    11L,
    11L,
    max_borrowers=1,
  ).unwrap()
  let quote = installed_source_json_construction_capacity(7L, 31L, 41L, 5L, 13L).unwrap()
  let prefix = @execution.execution_capacity(11L, 11L).unwrap()
  let pending = compose_installed_source_construction_capacity(prefix, [quote]).unwrap()
  reserve_installed_source_construction(owner, input, pending).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 20381L)
  let failed = @resources.ledger_usage(ledger)
  assert_true(
    reconcile_installed_source_construction(owner, [1], prefix)
    is Err(@resources.ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger), failed)
  // An active/failed recipe is not retained-only and cannot shrink itself.
  assert_true(
    reconcile_installed_source_construction(owner, input, quote)
    is Err(@resources.InvalidExtent),
  )
  assert_eq(@resources.ledger_usage(ledger), failed)
  let completed = compose_installed_source_construction_capacity(prefix, [
    retained_installed_source_construction_capacity(quote),
  ]).unwrap()
  reconcile_installed_source_construction(owner, input, completed).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 1395L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 1395L)
  // The next constructor is admitted only after releasing completed scratch.
  let next = @execution.execution_capacity(25000L, 25000L).unwrap()
  reserve_installed_source_construction(owner, input, next).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 25000L)
  assert_true(retire_installed_source_material(owner, input).unwrap())
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "shared profile recipe preserves original Source inventory for both native roles" {
  let quotes = installed_profile_construction_capacities(7L, 31L).unwrap()
  let quote = quotes[0]
  // Independently enumerated original inventory: 34 retained node slots,
  // 112 retained text bytes; 147 workspace slots and1506 workspace text bytes.
  assert_eq(@execution.execution_capacity_retained_bytes(quote), 9600L)
  assert_eq(@execution.execution_capacity_execution_bytes(quote), 59280L)
  assert_eq(@execution.execution_capacity_retained_bytes(quotes[1]), 8704L)
  assert_eq(@execution.execution_capacity_execution_bytes(quotes[1]), 59280L)
  let longer = installed_profile_construction_capacities(7L, 310L).unwrap()[0]
  let wider = installed_profile_construction_capacities(70L, 31L).unwrap()[0]
  assert_true(@execution.execution_capacity_retained_bytes(longer) > 9600L)
  assert_true(@execution.execution_capacity_execution_bytes(wider) > 59280L)
  assert_true(installed_profile_construction_capacities(-1L, 1L) is None)
  assert_true(installed_profile_construction_capacities(1L, -1L) is None)
  assert_true(
    installed_profile_construction_capacities(9223372036854775807L, 1L) is None,
  )
  assert_true(
    installed_profile_construction_capacities(1L, 9223372036854775807L) is None,
  )
}

///|
test "same profile inspection has workspace but no escaping variable material" {
  let original = installed_profile_construction_capacities(7L, 31L).unwrap()[0]
  let inspection = installed_source_inspection_construction_capacity(original)
  assert_eq(@execution.execution_capacity_retained_bytes(inspection), 0L)
  assert_eq(@execution.execution_capacity_execution_bytes(inspection), 59280L)
  let prefix = @execution.execution_capacity(11L, 11L).unwrap()
  let active = compose_installed_source_construction_capacity(prefix, [
    inspection,
  ]).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(active), 59291L)
  let after = compose_installed_source_construction_capacity(prefix, [
    retained_installed_source_construction_capacity(inspection),
  ]).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(after), 11L)
  assert_eq(@execution.execution_capacity_retained_bytes(active), 59291L)
}

///|
test "Table construction inventory preserves original profile writer and frame roles" {
  assert_eq(
    installed_table_construction_inventory(7L, 31L, 13L, 41L),
    Some([49L, 310L, 97L]),
  )
  for
    args in [
      (-1L, 31L, 13L, 41L),
      (7L, -1L, 13L, 41L),
      (7L, 31L, -1L, 41L),
      (7L, 31L, 13L, -1L),
      (9223372036854775807L, 31L, 13L, 41L),
      (7L, 9223372036854775807L, 13L, 41L),
      (7L, 31L, 9223372036854775807L, 41L),
      (7L, 31L, 13L, 9223372036854775807L),
    ] {
    let (nodes, wire, strings, recursive) = args
    assert_true(
      installed_table_construction_inventory(nodes, wire, strings, recursive)
      is None,
    )
  }
}
