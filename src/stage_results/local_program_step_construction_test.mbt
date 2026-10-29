///|
test "original two-stage repeated imports retain producer identity within their construction envelopes" {
  let source = local_program_source(true, untyped=true)
  let limits = local_program_limits()
  let environment = @local.prepare_environment(
    source,
    local_environment_fixture(),
    {
      max_work: limits.max_work,
      max_nodes: limits.max_nodes,
      max_text_bytes: limits.max_text_bytes,
      max_depth: limits.max_depth,
    },
  ).unwrap()
  let read = begin_local_program_read(
    source,
    limits,
    environment=Some(environment),
  ).unwrap()
  let peaks : Array[@shape.CollectionConstructionExtent] = []
  for _ in 0..<200 {
    let before = local_program_read_phase(read)
    if before == Complete {
      break
    }
    let quote = local_program_read_step_construction(read)
    if before == Imports {
      peaks.push(quote.unwrap().peak)
    }
    let next = advance_local_program_read(read)
    assert_false(next == Failed)
    if quote is Some(q) {
      let held = local_program_read_step_retained_extent(read, before).unwrap()
      assert_true(q.peak.record_headers >= held.extent.record_headers)
      assert_true(q.peak.reference_slots >= held.extent.reference_slots)
      assert_true(q.peak.scalar_words >= held.extent.scalar_words)
    }
  }
  assert_eq(peaks.length(), 2)
  assert_true(peaks[1].record_headers > peaks[0].record_headers)
  let (result, _) = take_local_program_read(read).unwrap().unwrap()
  guard result is Publication(wiring) else { fail("publication expected") }
  let producer = wiring_stage_at(wiring, 0).unwrap()
  let imported = attached_imports(wiring_imports_at(wiring, 1).unwrap())
  assert_eq(import_count(imported), 2)
  for i in 0..<2 {
    assert_true(
      physical_equal(input_stage(import_at(imported, i).unwrap()), producer),
    )
  }
}
