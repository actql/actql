///|
fn contract_preflight_original() -> @contract.Contract {
  let number = @contract.primitive(NumberType, nullable=false)
  let array = @contract.array_contract(number, nullable=false).unwrap()
  @contract.object_contract(
    [("a", number), ("b", array)],
    nullable=false,
    max_fields=2,
    max_name_bytes=2,
  ).unwrap()
}

///|
fn contract_preflight_original_budget(depth : Int, text : Int) -> Budget {
  let limits = {
    ..evidence_read_limits(),
    max_work: 100,
    max_text_bytes: text,
    max_depth: depth,
  }
  {
    limits,
    work: 100,
    text,
    nodes: limits.max_nodes,
    tokens: limits.max_tokens,
  }
}

///|
test "original Contract preflight retains one pending stack and exact shared Budget across node returns" {
  let source = evidence_read_cursor("[]")
  let contract = contract_preflight_original()
  let b = contract_preflight_original_budget(2, 100)
  let read = begin_contract_preflight_read(b, source, contract, 0)
  let stack = read.work
  assert_true(physical_equal(read.b, b))
  assert_true(physical_equal(read.source, source))
  assert_true(physical_equal(stack[0].0, contract))
  assert_eq(stack[0].1, 0)
  advance_contract_preflight_read(read)
  assert_true(read.state is Pending)
  assert_eq(read.work.length(), 0)
  assert_eq(b.work, 97)
  assert_eq(b.text, 100)
  // Name admission and each pending write are separate backed boundaries.
  for _ in 0..<4 {
    advance_contract_preflight_read(read)
  }
  assert_eq(read.work.length(), 2)
  assert_eq(b.text, 98)
  // Original field order is pushed unchanged; the Array field remains on top.
  assert_true(read.work[1].0.shape is @contract.Array(_, ..))
  for _ in 0..<4 {
    advance_contract_preflight_read(read)
    assert_true(physical_equal(read.b, b))
    assert_true(physical_equal(read.work, stack))
  }
  assert_true(read.state is Complete)
  assert_eq(b.work, 94)
  assert_eq(b.text, 98)
  let before = b.work
  advance_contract_preflight_read(read)
  assert_eq(b.work, before)
  let sync = contract_preflight_original_budget(2, 100)
  preflight(sync, source, contract) catch {
    Stop(_) => abort("the same original complete preflight must succeed")
  }
  assert_eq(sync.work, 94)
  assert_eq(sync.text, 98)
}

///|
test "original Contract preflight keeps exact depth and partial-text failures without reissuing work" {
  let source = evidence_read_cursor("[]")
  let contract = contract_preflight_original()
  let b = contract_preflight_original_budget(1, 100)
  let read = begin_contract_preflight_read(b, source, contract, 0)
  for _ in 0..<8 {
    advance_contract_preflight_read(read)
  }
  guard read.state is Rejected(issue) else {
    abort("original depth refusal expected")
  }
  assert_eq(issue.kind, BudgetExceeded)
  assert_true(physical_equal(issue.source, source))
  assert_eq(b.work, 95)
  assert_eq(b.text, 98)
  assert_eq(read.work.length(), 1)
  advance_contract_preflight_read(read)
  assert_eq(b.work, 95)
  clear_contract_preflight_read(read)
  assert_true(read.state is Cleared)
  assert_eq(read.work.length(), 0)
  advance_contract_preflight_read(read)
  assert_eq(b.work, 95)
  let text_budget = contract_preflight_original_budget(2, 1)
  let text_read = begin_contract_preflight_read(
    text_budget, source, contract, 0,
  )
  for _ in 0..<4 {
    advance_contract_preflight_read(text_read)
  }
  guard text_read.state is Rejected(issue) else {
    abort("original partial text refusal expected")
  }
  assert_eq(issue.kind, BudgetExceeded)
  assert_true(physical_equal(issue.source, source))
  assert_eq(text_budget.work, 97)
  assert_eq(text_budget.text, 0)
  assert_eq(text_read.work.length(), 1)
  clear_contract_preflight_read(text_read)
  advance_contract_preflight_read(text_read)
  assert_eq(text_budget.work, 97)
  // The same Budget may already have consumed its prefix before this read.
  let remaining = contract_preflight_original_budget(2, 100)
  remaining.work = 2
  let short = begin_contract_preflight_read(remaining, source, contract, 0)
  advance_contract_preflight_read(short)
  guard short.state is Rejected(issue) else {
    abort("the original remaining-work refusal must survive")
  }
  assert_eq(issue.kind, BudgetExceeded)
  assert_eq(remaining.work, 1)
  assert_eq(remaining.text, 100)
  assert_eq(short.work.length(), 0)
  clear_contract_preflight_read(short)
  advance_contract_preflight_read(short)
  assert_eq(remaining.work, 1)
}
