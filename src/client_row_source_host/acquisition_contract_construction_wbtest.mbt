///|
test "Source protocol constructor replaces the measured escaped-node duplication without changing the original quota" {
  // Exact query/evidence UTF16 lengths at the 8e1 failed Source boundary.
  // These are quoted input DATA, not parsed body acceptance or an I/O grant.
  let native = row_acquisition_contracts_construction_capacity(12465, 5365).unwrap()
  let peak = @execution.execution_capacity_execution_bytes(native)
  assert_true(peak > 0L)
  let original_prefix = 367549522L
  let total = @execution.execution_capacity(
    original_prefix + peak,
    original_prefix + peak,
  ).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 536870912L,
    execution_bytes: 536870912L,
  }).unwrap()
  // The original generic escaped-byte/node quote requested 602189970E and
  // failed the same 512MiB execution quota. No quota is lowered or raised.
  assert_true(
    @resources.reserve_capacity(ledger, 484869746L, 602189970L)
    is Err(@resources.ExecutionLimit),
  )
  let reservation = @resources.reserve_capacity(
    ledger,
    @execution.execution_capacity_retained_bytes(total),
    @execution.execution_capacity_execution_bytes(total),
  ).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    original_prefix + peak,
  )
  @resources.settle_capacity(ledger, reservation).unwrap()
  assert_true(row_acquisition_contracts_construction_capacity(-1, 5365) is None)
  // Empty and malformed actual bodies still reach the SAME original law.
  assert_true(row_acquisition_contracts_construction_capacity(0, 0) is Some(_))
  assert_true(admit_row_acquisition_contracts("", "") is Err(InvalidContracts))
  assert_true(
    admit_row_acquisition_contracts("{}", "{}") is Err(InvalidContracts),
  )
}
