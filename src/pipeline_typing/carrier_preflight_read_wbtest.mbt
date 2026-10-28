///|
test "original Carrier continuation borrows the same rows and Budget without replay" {
  let source = evidence_read_cursor("[]")
  let value = evidence_read_carrier()
  let b = contract_preflight_original_budget(2, 100)
  let read = begin_carrier_preflight_read(b, source, value)
  assert_true(physical_equal(read.b, b))
  assert_true(physical_equal(read.source, source))
  assert_true(physical_equal(read.original, value))
  for _ in 0..<6 {
    advance_carrier_preflight_read(read)
    assert_true(physical_equal(read.b, b))
    assert_true(physical_equal(read.original, value))
  }
  assert_true(read.state is Complete)
  // Row visit1, field slot1, original Number Contract1; original name "id"2B.
  assert_eq(b.work, 97)
  assert_eq(b.text, 98)
  advance_carrier_preflight_read(read)
  assert_eq(b.work, 97)
  let sync = contract_preflight_original_budget(2, 100)
  carrier_preflight(sync, source, value) catch {
    Stop(_) => abort("same original Carrier preflight must complete")
  }
  assert_eq(sync.work, 97)
  assert_eq(sync.text, 98)
}

///|
test "failed Carrier retains the original nested typed refusal and clears the same Contract read" {
  let source = evidence_read_cursor("[]")
  let value = evidence_read_carrier()
  let b = contract_preflight_original_budget(0, 100)
  let read = begin_carrier_preflight_read(b, source, value)
  for _ in 0..<3 {
    advance_carrier_preflight_read(read)
  }
  let nested = read.contract.unwrap()
  advance_carrier_preflight_read(read)
  guard read.state is Rejected(issue) else {
    abort("original nested refusal expected")
  }
  assert_eq(issue.kind, BudgetExceeded)
  assert_true(physical_equal(issue.source, source))
  assert_true(nested.state is Rejected(_))
  assert_eq(b.work, 97)
  assert_eq(b.text, 98)
  advance_carrier_preflight_read(read)
  assert_eq(b.work, 97)
  clear_carrier_preflight_read(read)
  assert_true(nested.state is Cleared)
  assert_true(read.contract is None)
  assert_true(read.state is Cleared)
  advance_carrier_preflight_read(read)
  assert_eq(b.work, 97)
}
