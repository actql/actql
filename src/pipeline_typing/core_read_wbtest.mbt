///|
fn original_core_fixture(
  source : @decode.Cursor,
  from? : @decode.Cursor? = None,
) -> PipelineCoreRead {
  let carrier = evidence_read_carrier()
  begin_pipeline_core_read(
    source,
    [("rows", carrier)],
    None,
    from,
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
}

///|
test "original core read retains one budget inputs and operation loop across semantic boundaries" {
  let source = evidence_read_cursor(
    "[{\"derive\":{\"next\":\"id + 1\"}},{\"select\":[\"next\"]}]",
  )
  let read = original_core_fixture(source)
  assert_true(pipeline_core_read_phase(read) == Inputs)
  assert_eq(pipeline_core_read_consumed_work(read), Some(1))
  guard read.state is Reading(original) else { abort("original core expected") }
  assert_true(physical_equal(original.source, source))
  let budget = original.b
  let input_array = original.inputs
  let bodies = original.bodies
  assert_eq(bodies.length(), 2)
  let quote = pipeline_core_read_entry_construction(source, 1).unwrap()
  let held = pipeline_core_read_entry_holdings(read).unwrap()
  assert_true(held.record_headers <= quote.record_headers)
  assert_true(held.reference_slots <= quote.reference_slots)
  assert_true(held.scalar_words <= quote.scalar_words)
  assert_true(take_pipeline_core_read(read) is None)
  while pipeline_core_read_phase(read) == Inputs {
    let before = pipeline_core_read_consumed_work(read).unwrap()
    let _ = advance_pipeline_core_read(read)
    assert_true(pipeline_core_read_consumed_work(read).unwrap() >= before)
    assert_true(physical_equal(original.b, budget))
    assert_true(physical_equal(original.inputs, input_array))
  }
  assert_true(pipeline_core_read_phase(read) == Parameters)
  while pipeline_core_read_phase(read) == Parameters {
    let _ = advance_pipeline_core_read(read)
  }
  assert_true(pipeline_core_read_phase(read) == ImportedEvidence)
  for expected in [DeltaContracts, Steps, FinalEvidence, Complete] {
    let before_phase = pipeline_core_read_phase(read)
    let before = pipeline_core_read_consumed_work(read).unwrap()
    assert_true(pipeline_core_read_phase(read) == before_phase)
    assert_eq(pipeline_core_read_consumed_work(read), Some(before))
    assert_true(advance_pipeline_core_read(read) == expected)
    assert_true(pipeline_core_read_consumed_work(read).unwrap() >= before)
    assert_true(physical_equal(original.b, budget))
    assert_true(physical_equal(original.inputs, input_array))
    assert_true(physical_equal(original.bodies, bodies))
  }
  assert_true(advance_pipeline_core_read(read) == Complete)
  let actual_work = pipeline_core_read_consumed_work(read).unwrap()
  let checked = take_pipeline_core_read(read).unwrap().unwrap()
  assert_eq(checked.usage.work, actual_work)
  assert_eq(step_count(checked), 2)
  assert_eq(current(checked), Some(Step(1)))
  assert_true(physical_equal(checked.source, source))
  assert_true(physical_equal(checked.inputs, input_array))
  assert_true(take_pipeline_core_read(read) is None)
  clear_pipeline_core_read(read)
  assert_true(advance_pipeline_core_read(read) == Taken)
}

///|
test "original core typed selector failure remains original and clear stops every pending body" {
  let source = evidence_read_cursor("[]")
  let missing = evidence_read_cursor("\"missing\"")
  let read = original_core_fixture(source, from=Some(missing))
  while pipeline_core_read_phase(read) == Inputs {
    let _ = advance_pipeline_core_read(read)
  }
  assert_true(pipeline_core_read_phase(read) == Parameters)
  while pipeline_core_read_phase(read) == Parameters {
    let _ = advance_pipeline_core_read(read)
  }
  assert_true(pipeline_core_read_phase(read) == Failed)
  assert_eq(pipeline_core_read_consumed_work(read), Some(6))
  assert_true(advance_pipeline_core_read(read) == Failed)
  guard take_pipeline_core_read(read) is Some(Err(issue)) else {
    abort("typed original issue expected")
  }
  assert_eq(issue.kind, UnknownName("missing"))
  assert_true(physical_equal(issue.source, missing))
  for steps in 0..<6 {
    let read = original_core_fixture(source)
    for _ in 0..<steps {
      let _ = advance_pipeline_core_read(read)
    }
    assert_true(take_pipeline_core_read(read) is None)
    clear_pipeline_core_read(read)
    assert_true(advance_pipeline_core_read(read) == Cleared)
    assert_true(pipeline_core_read_consumed_work(read) is None)
  }
}
