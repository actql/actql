///|
test "original Core input yields before each Carrier construction and retains its exact consumed prefix" {
  let source = evidence_read_cursor("[]")
  let read = original_core_fixture(source)
  guard read.state is Reading(body) else { abort("original Core expected") }
  let original_budget = body.b
  let original_inputs = body.inputs
  let original_names = body.names
  assert_eq(pipeline_core_read_owned_work(read), Some(1))
  let _ = advance_pipeline_core_read(read)
  assert_true(body.input_step is Duplicate)
  assert_eq(pipeline_core_read_owned_work(read), Some(2))
  assert_eq(body.b.text, body.limits.max_text_bytes - 4)
  let _ = advance_pipeline_core_read(read)
  assert_true(body.input_step is CarrierStart)
  assert_true(body.carrier_read is None)
  let _ = advance_pipeline_core_read(read)
  let carrier = body.carrier_read.unwrap()
  assert_true(physical_equal(carrier.b, original_budget))
  assert_true(physical_equal(carrier.original, original_inputs[0].1))
  while body.input_step is Carrier {
    let _ = advance_pipeline_core_read(read)
    assert_true(physical_equal(body.b, original_budget))
    assert_true(physical_equal(body.inputs, original_inputs))
    assert_true(physical_equal(body.names, original_names))
  }
  assert_true(body.input_step is Register)
  assert_true(body.carrier_read is None)
  assert_true(carrier.state is Cleared)
  assert_true(!body.names.contains("rows"))
  assert_eq(pipeline_core_read_owned_work(read), Some(5))
  assert_eq(body.b.text, body.limits.max_text_bytes - 6)
  let _ = advance_pipeline_core_read(read)
  assert_eq(body.names.get("rows"), Some(Input(0)))
  assert_true(body.input_step is Name)
  assert_true(advance_pipeline_core_read(read) == Parameters)
  let checked = check_carriers(
    source,
    [("rows", original_inputs[0].1)],
    None,
    None,
    evidence_read_limits(),
  ).unwrap()
  // Original later bodies add imported-evidence2 and final-evidence3 visits;
  // this input-only prefix above remains5, not the complete Usage10.
  assert_eq(checked.usage.work, 10)
  assert_eq(checked.usage.text_bytes, 6)
}

///|
test "clear retires the original in-progress Core Carrier Contract without completing its input" {
  let source = evidence_read_cursor("[]")
  let read = original_core_fixture(source)
  for _ in 0..<6 {
    let _ = advance_pipeline_core_read(read)
  }
  guard read.state is Reading(body) else { abort("original Core expected") }
  let carrier = body.carrier_read.unwrap()
  let contract = carrier.contract.unwrap()
  let budget = body.b
  let work = budget.work
  let text = budget.text
  assert_true(contract.state is Pending)
  assert_true(!body.names.contains("rows"))
  clear_pipeline_core_read(read)
  assert_true(contract.state is Cleared)
  assert_true(carrier.state is Cleared)
  assert_true(body.carrier_read is None)
  assert_true(advance_pipeline_core_read(read) == Cleared)
  assert_eq(budget.work, work)
  assert_eq(budget.text, text)
  assert_true(!body.names.contains("rows"))
}
