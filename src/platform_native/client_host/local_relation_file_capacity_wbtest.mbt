///|
fn relation_work_capacity_inputs() -> (
  @row_file.NativeRelationFileSelection,
  @row_file.NativeRelationFileLimits,
) {
  (
    {
      directory: "/fixture",
      name: "records.json",
      resource: "records",
      items_path: ["items"],
      key_path: None,
      primary_identity: "id",
    },
    {
      page: { max_bytes: 8192, max_nodes: 512, max_depth: 8, max_rows: 2, },
      max_work: 1000000,
      chunk_bytes: 7,
      diagnostic_ceiling: 128,
    },
  )
}

///|
// Arithmetic only. These unfunded test Ledgers cannot enter the original Work
// route and do not establish installed Read/Account/Source execution evidence.
test "relation Work preflight requires Source and Compute simultaneous dimensions" {
  let limits : @resources.LedgerLimits = {
    planning_work: 5,
    attempts: 3,
    holdings: 2,
    transfer_bytes: 500L,
    retained_bytes: 700L,
    execution_bytes: 900L,
  }
  let ledger = @resources.create_ledger(limits).unwrap()
  let source : @resources.LedgerLimits = {
    planning_work: 1,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 100L,
    retained_bytes: 200L,
    execution_bytes: 300L,
  }
  let compute : @resources.LedgerLimits = {
    planning_work: 4,
    attempts: 3,
    holdings: 2,
    transfer_bytes: 400L,
    retained_bytes: 500L,
    execution_bytes: 600L,
  }
  assert_true(relation_file_inventory_available(ledger, source, compute))
  for
    short in [
      { ..limits, planning_work: 4, },
      { ..limits, attempts: 2, },
      { ..limits, holdings: 1, },
      { ..limits, transfer_bytes: 499L, },
      { ..limits, retained_bytes: 699L, },
      { ..limits, execution_bytes: 899L, },
    ] {
    assert_false(
      relation_file_inventory_available(
        @resources.create_ledger(short).unwrap(),
        source,
        compute,
      ),
    )
  }
  let reserved = @resources.reserve_capacity(ledger, 1L, 1L).unwrap()
  assert_false(relation_file_inventory_available(ledger, source, compute))
  @resources.settle_capacity(ledger, reserved).unwrap()
  assert_true(relation_file_inventory_available(ledger, source, compute))
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 0L)
}

///|
test "relation Work preflight refuses quote overflow without reserving an attempt" {
  let limits : @resources.LedgerLimits = {
    planning_work: 1,
    attempts: 2,
    holdings: 2,
    transfer_bytes: 1L,
    retained_bytes: 1L,
    execution_bytes: 1L,
  }
  let ledger = @resources.create_ledger(limits).unwrap()
  assert_false(
    relation_file_inventory_available(
      ledger,
      {
        ..limits,
        attempts: 1,
        holdings: 1,
        execution_bytes: 9223372036854775807L,
      },
      limits,
    ),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_attempts, 0)
}

///|
test "relation Work composes the Common captured control exactly once" {
  let native = relation_file_work_control_bytes().unwrap()
  let common = @local.captured_local_tasks_control_capacity().unwrap()
  let (selection, limits) = relation_work_capacity_inputs()
  let combined = native_relation_file_work_control_capacity(selection, limits).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(common), 128L)
  assert_eq(@execution.execution_capacity_execution_bytes(common), 128L)
  assert_eq(
    @execution.execution_capacity_retained_bytes(combined) - native - 23076038L,
    128L,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(combined) - native - 23076038L,
    128L,
  )
}

///|
test "relation entry Read constructor component is distinct from the reserved business bytes" {
  let (selection, limits) = relation_work_capacity_inputs()
  let read = native_relation_file_entry_read_capacity(selection, limits).unwrap()
  // Independently authored H80/R83/S168 central-tariff vector. This is
  // constructor arithmetic, not a physical-entry or normal-profile proof.
  assert_eq(@execution.execution_capacity_retained_bytes(read), 29346L)
  assert_eq(@execution.execution_capacity_execution_bytes(read), 29346L)
  let pending_prepare = 58L * 16L + 70L * 8L + 109L * 8L
  let never_entered_cancel = 22L * 16L + 13L * 8L + 59L * 8L
  assert_eq(pending_prepare, 2360L)
  assert_eq(never_entered_cancel, 928L)
  assert_eq(
    @execution.execution_capacity_retained_bytes(read),
    pending_prepare +
    never_entered_cancel +
    288L +
    23832L +
    192L +
    552L +
    914L +
    280L,
  )
}

///|
test "relation entry authored minimum fixture and maximum constructor totals" {
  let (selection, limits) = relation_work_capacity_inputs()
  assert_eq(relation_file_work_control_bytes().unwrap(), 47890L)
  let minimum = {
    ..limits,
    page: { max_bytes: 1, max_nodes: 1, max_depth: 1, max_rows: 1, },
  }
  let maximal = {
    ..limits,
    page: { max_bytes: 65536, max_nodes: 8192, max_depth: 32, max_rows: 100, },
  }
  let paths = {
    ..selection,
    items_path: Array::make(16, "items"),
    key_path: Some(Array::make(16, "key")),
  }
  for
    (selected, bounded, work_bytes, read_bytes) in [
      (selection, minimum, 270557L, 29346L),
      (selection, limits, 23124056L, 29346L),
      (paths, maximal, 296458808L, 32770L),
    ] {
    let work = native_relation_file_work_control_capacity(selected, bounded).unwrap()
    let read = native_relation_file_entry_read_capacity(selected, bounded).unwrap()
    assert_eq(@execution.execution_capacity_retained_bytes(work), work_bytes)
    assert_eq(@execution.execution_capacity_execution_bytes(work), work_bytes)
    assert_eq(@execution.execution_capacity_retained_bytes(read), read_bytes)
    assert_eq(@execution.execution_capacity_execution_bytes(read), read_bytes)
  }
  let outer = native_relation_file_entry_outer_capacity().unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(outer), 2842L)
  assert_eq(@execution.execution_capacity_execution_bytes(outer), 2842L)
  let excessive = { ..paths, items_path: Array::make(17, "items"), }
  assert_true(
    native_relation_file_work_control_capacity(excessive, maximal) is None,
  )
  assert_true(
    native_relation_file_entry_read_capacity(excessive, maximal) is None,
  )
}
