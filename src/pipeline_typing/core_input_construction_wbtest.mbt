///|
fn input_construction_bytes(
  value : @shape.CollectionConstructionExtent,
) -> Int64 {
  16L * value.record_headers +
  8L * value.reference_slots +
  8L * value.scalar_words
}

///|
test "original input quantities replace the same Map and nested stack rather than accumulate retired snapshots" {
  let source = evidence_read_cursor("[]")
  let read = original_core_fixture(source)
  guard read.state is Reading(body) else { abort("original Core expected") }
  let mut parent_held = input_construction_bytes(
    core_input_retained(body).unwrap(),
  )
  let initial = parent_held
  let mut retired = false
  while body.phase == Inputs {
    let q = core_input_step_construction(body).unwrap()
    let old = input_construction_bytes(q.replaced)
    assert_eq(old, parent_held)
    let peak = input_construction_bytes(q.peak) + 2L * q.peak_utf16_units
    let _ = advance_pipeline_core_read(read)
    assert_true(pipeline_core_read_phase(read) != Failed)
    let new = input_construction_bytes(core_input_retained(body).unwrap())
    assert_true(new <= old + peak)
    if new < old {
      retired = true
    }
    // The SAME domain replaces old/new; no loop-local capacity grant or refund.
    parent_held = old + peak - (old + peak - new)
    assert_eq(parent_held, new)
  }
  assert_true(retired)
  assert_true(parent_held > initial)
  assert_true(body.names.contains("rows"))
}

///|
test "a failed original input retains exact consumed work and typed Issue until clear" {
  let source = evidence_read_cursor("[]")
  let carrier = evidence_read_carrier()
  let read = begin_pipeline_evidence_read(
    source,
    [("rows", CarrierInput(carrier))],
    None,
    None,
    { ..evidence_read_limits(), max_depth: 0, },
  ).unwrap()
  while pipeline_evidence_read_phase(read) != Failed {
    let _ = advance_pipeline_evidence_read(read)
  }
  assert_eq(pipeline_evidence_read_owned_work(read), Some(5))
  let issue = pipeline_evidence_read_issue(read).unwrap()
  assert_eq(issue.kind, BudgetExceeded)
  assert_true(physical_equal(issue.source, source))
  guard read.state is Rejected(body, _) &&
    body.step is CoreRunning(core) &&
    core.state is Rejected(original, _) else {
    abort("same failed Core expected")
  }
  let nested = original.carrier_read.unwrap().contract.unwrap()
  assert_true(nested.state is Rejected(_))
  assert_true(!original.names.contains("rows"))
  assert_eq(pipeline_evidence_read_owned_work(read), Some(5))
  clear_pipeline_evidence_read(read)
  assert_true(nested.state is Cleared)
  assert_true(pipeline_evidence_read_owned_work(read) is None)
}

///|
test "wide nested Contract push backing retires to the original final Map without a policy-sized stack" {
  let source = evidence_read_cursor("[]")
  let number = @contract.primitive(NumberType, nullable=false)
  let fields : Array[(String, @contract.Contract)] = []
  for i in 0..<32 {
    fields.push(("f" + i.to_string(), number))
  }
  let nested = @contract.object_contract(
    fields,
    nullable=false,
    max_fields=32,
    max_name_bytes=100,
  ).unwrap()
  let schema = @schema.from_fields(
    [(Unqualified("payload"), nested)],
    max_fields=1,
    max_name_bytes=7,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(schema))
  let read = begin_pipeline_core_read(
    source,
    [("rows", carrier)],
    None,
    None,
    evidence_read_limits(),
    None,
    None,
    [],
    [None],
    [None],
    [None],
    [CarrierInput(carrier)],
    None,
  ).unwrap()
  guard read.state is Reading(body) else { abort("original Core expected") }
  let mut grows = 0
  while body.phase == Inputs {
    let q = core_input_step_construction(body).unwrap()
    let old = input_construction_bytes(q.replaced)
    let _ = advance_pipeline_core_read(read)
    assert_true(pipeline_core_read_phase(read) != Failed)
    let new = input_construction_bytes(core_input_retained(body).unwrap())
    assert_true(
      new <= old + input_construction_bytes(q.peak) + 2L * q.peak_utf16_units,
    )
    if new > old {
      grows += 1
    }
  }
  assert_true(grows > 16)
  assert_true(body.carrier_read is None)
  let final_held = core_input_retained(body).unwrap()
  let map = @shape.map_retained_extent(1L, body.names.capacity().to_int64(), 1L).unwrap()
  assert_eq(final_held.record_headers, map.record_headers + 1L)
  assert_eq(final_held.reference_slots, map.reference_slots)
  assert_eq(final_held.scalar_words, map.scalar_words + 1L)
}
