///|
// Explicit test Ledger: this verifies the common inventory -> existing phase
// owner boundary, not a physical supplier, Host grant or cleanup ACK.
test "composed constructor units grow the same preparation without crediting another live owner" {
  let header : @execution.PreparationRepresentationUnits = {
    record_headers: 1L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let references = { ..header, record_headers: 0L, reference_slots: 2L, }
  let encoded = {
    ..header,
    record_headers: 0L,
    owned_utf16_units: 7L,
    owned_wire_bytes: 17L,
  }
  let inventory = @execution.compose_preparation_representation([
    header, references, encoded,
  ]).unwrap()
  let required = @execution.preparation_representation_cost(inventory).unwrap()
  assert_eq(required, 63L)
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 63L,
    execution_bytes: 4L,
  }).unwrap()
  let input = [1]
  let owner : @resources.PreparationCapacity[Array[Int], Array[Int]] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    16L,
    4L,
    max_borrowers=1,
  ).unwrap()
  let other = @resources.reserve_capacity(ledger, 1L, 0L).unwrap()
  assert_true(
    reserve_closed_values_phase(owner, [1], CheckLowerAndPlan, required, 4L)
    is Err(Capacity(ForeignOriginal)),
  )
  guard reserve_closed_values_phase(
      owner,
      input,
      CheckLowerAndPlan,
      required,
      4L,
    )
    is Err(issue) else {
    fail("the other original owner must keep its one byte")
  }
  assert_eq(
    closed_values_preparation_capacity_refusal(issue),
    Some(("check_lower_and_plan", "retention", 63L, 4L, 62L, 4L)),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 17L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 4L)
  @resources.settle_capacity(ledger, other).unwrap()
  reserve_closed_values_phase(owner, input, CheckLowerAndPlan, required, 4L).unwrap()
  assert_eq(@resources.preparation_capacity_accounting(owner).0, 63L)
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_eq(@resources.ledger_usage(ledger).planning_work, 0)
  assert_eq(
    @resources.abort_preparation_capacity_after_cleanup(owner, input),
    Ok(true),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}
