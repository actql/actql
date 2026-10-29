///|
fn original_literal_domains_admission(
  source : @decode.Cursor,
  domains : LiteralDomains,
  limits : TransferLimits,
) -> Result[LiteralTransfer, Issue] {
  try {
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    for (name, domain) in domains.fields {
      spend(b, source, 1)
      let bytes = @scalar.admit_utf8_length(name, b.text).unwrap_or(-1)
      if bytes < 0 {
        fail(source, LimitExceeded)
      }
      b.text -= bytes
      for value in domain.values {
        literal_charge(b, source, value)
      }
    }
    Ok({
      domains,
      work: limits.max_work - b.work,
      text_bytes: limits.max_name_bytes - b.text,
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
fn original_literal_domains_fixture() -> LiteralDomains {
  let schema = @row.from_fields(
    [(@row.Unqualified("id"), @contract.primitive(NumberType, nullable=false))],
    max_fields=1,
    max_name_bytes=2,
  ).unwrap()
  let operation = @relation.check(
    Derive,
    graph_order_cursor("{\"tag\":\"'é'\",\"flag\":\"TRUE\",\"qty\":\"1\"}"),
    schema,
    None,
    {
      max_work: 1000,
      max_nodes: 1000,
      max_text_bytes: 1000,
      max_tokens: 1000,
      max_depth: 20,
    },
  ).unwrap()
  transfer_literal_domains(None, operation, {
    max_work: 1000,
    max_name_bytes: 1000,
  }).unwrap().domains
}

///|
test "original literal admission retains source domain and exact independently counted work and UTF8 charges" {
  let domains = original_literal_domains_fixture()
  let source = graph_order_cursor("null")
  // Three fields and three values. Original internal keys are u:flag/u:qty/u:tag:
  // names6+5+5, Boolean1, Number8 and text2, totaling27bytes.
  let limits : TransferLimits = { max_work: 6, max_name_bytes: 27, }
  let original = original_literal_domains_admission(source, domains, limits).unwrap()
  assert_eq(original.work, 6)
  assert_eq(original.text_bytes, 27)
  let read = begin_literal_domains_read(source, domains, limits).unwrap()
  let mut old = literal_domains_read_retained_extent(read).unwrap()
  let entry = literal_domains_read_entry_construction(0L).unwrap()
  assert_true(old.record_headers <= entry.record_headers)
  let mut work = 0
  while literal_domains_read_phase(read) == Pending {
    let quote = literal_domains_read_step_construction(read).unwrap()
    let _ = advance_literal_domains_read(read)
    assert_true(literal_domains_read_phase(read) != Failed)
    let held = literal_domains_read_retained_extent(read).unwrap()
    assert_true(
      held.record_headers <= old.record_headers + quote.record_headers,
    )
    assert_true(
      held.reference_slots <= old.reference_slots + quote.reference_slots,
    )
    assert_true(held.scalar_words <= old.scalar_words + quote.scalar_words)
    let consumed = literal_domains_read_consumed_work(read).unwrap()
    assert_true(consumed >= work)
    work = consumed
    old = held
  }
  assert_eq(work, 6)
  let actual = take_literal_domains_read(read).unwrap().unwrap()
  assert_eq(actual.work, original.work)
  assert_eq(actual.text_bytes, original.text_bytes)
  assert_true(physical_equal(actual.domains, domains))
  assert_eq(literal_domains_read_phase(read), Taken)
  assert_true(literal_domains_read_consumed_work(read) is None)
  assert_true(take_literal_domains_read(read) is None)
}

///|
test "literal admission preserves first refusal and retains actual failed prefix without successful transfer" {
  let domains = original_literal_domains_fixture()
  let source = graph_order_cursor("null")
  for
    (limits, work) in [
      ({ max_work: 5, max_name_bytes: 27, }, 5),
      ({ max_work: 6, max_name_bytes: 26, }, 6),
    ] {
    let original = original_literal_domains_admission(source, domains, limits)
    guard original is Err(expected) else { abort("original refusal expected") }
    let read = begin_literal_domains_read(source, domains, limits).unwrap()
    while literal_domains_read_phase(read) == Pending {
      let _ = advance_literal_domains_read(read)
    }
    assert_eq(literal_domains_read_phase(read), Failed)
    assert_eq(literal_domains_read_consumed_work(read), Some(work))
    let issue = literal_domains_read_issue(read).unwrap()
    assert_eq(issue.kind, expected.kind)
    assert_eq(issue.path, expected.path)
    assert_eq(issue.span, expected.span)
    assert_eq(advance_literal_domains_read(read), Failed)
    assert_true(take_literal_domains_read(read) is Some(Err(_)))
    assert_true(literal_domains_read_consumed_work(read) is None)
  }
  for
    limits in [
      { max_work: -1, max_name_bytes: 27, },
      { max_work: 6, max_name_bytes: -1, },
    ] {
    assert_true(
      begin_literal_domains_read(source, domains, limits)
      is Err({ kind: InvalidLimits, .. }),
    )
  }
}

///|
test "clearing original literal continuation drops only its iterator and current roots" {
  let domains = original_literal_domains_fixture()
  let source = graph_order_cursor("null")
  for steps in 0..<8 {
    let read = begin_literal_domains_read(source, domains, {
      max_work: 6,
      max_name_bytes: 21,
    }).unwrap()
    for _ in 0..<steps {
      let _ = advance_literal_domains_read(read)
    }
    clear_literal_domains_read(read)
    assert_eq(literal_domains_read_phase(read), Cleared)
    assert_eq(advance_literal_domains_read(read), Cleared)
    assert_true(literal_domains_read_consumed_work(read) is None)
    assert_true(take_literal_domains_read(read) is None)
    assert_eq(domains.fields.length(), 3)
  }
}
