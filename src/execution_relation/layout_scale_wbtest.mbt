///|
// Experimental B/C continuation of the exact legacy fixture and preparation.
// Shares the admitted sequence driver; does not manufacture CompletedOutput.
fn profile_column_sequence(
  generated : GeneratedSequence,
  input : CapturedRows,
  candidate : LayoutCandidate,
  count : Int,
  width : Int,
  same : Bool,
  value_limits : ValueLimits,
  total_clock : @bench.Timestamp,
  import_clock : @bench.Timestamp,
  fixture_us : Double,
  prepare_us : Double,
  profile : Bool,
) -> Unit raise {
  let ledger = layout_ledger(100000000, 100000000, 100000000)
  let physical = {
    ..layout_allocation(100000000, 100000000, 100000000),
    ledger: Some(ledger),
  }
  let source = retain_layout_capture(input, ledger).unwrap()
  let control = { remaining: 100000000, max_frames: 100, }
  let limits : SequenceRunLimits = {
    max_rows: count,
    metadata_entries: 100000,
    retained_entries: 20000000,
    operation_entries: 20000000,
    input_values: value_limits,
    output_values: value_limits,
  }
  let invocation = prepare_sequence_with_importers(
    generated.contracts,
    generated.sequence,
    [input],
    generated.retained_ids,
    limits,
    control,
    fn(captured) {
      if !physical_equal(captured, input) {
        return Err(InvalidRows)
      }
      import_layout_capture_columns(source, candidate, physical)
    },
    fn(_bound, _id, _output) { Err(InvalidRows) },
    release_table=fn(table : LayoutRelation) {
      release_layout_columns(table.storage)
    },
    produced=[],
    fragments=Some(generated.contexts),
    ordered={ contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
  ).unwrap()
  let import_us = @bench.monotonic_clock_end(import_clock)
  let execute_clock = @bench.monotonic_clock_start()
  run_sequence_with_backend(invocation, fn(_captured) { Err(InvalidRows) }, fn(
    kernel,
    table,
    logical,
  ) {
    evaluate_layout_kernel(
      kernel,
      table,
      count,
      control,
      invocation.output_budget,
      { limit: limits.operation_entries, live: 0, peak: 0, },
      physical,
      logical,
    )
  }).unwrap()
  let execute_us = @bench.monotonic_clock_end(execute_clock)
  let observe_clock = @bench.monotonic_clock_start()
  let store = invocation.store
  // One supplied input precedes step slots. Both terminal branches are retained.
  let unique = store.tables[6].unwrap().table
  let chosen = store.tables[9].unwrap().table
  let expected = if same { 1 } else { 10 }
  assert_eq(unique.storage.count, expected)
  assert_eq(chosen.storage.count, expected)
  assert_eq(chosen.names.length(), width)
  let positions : Map[String, Int] = Map([])
  for i = 0; i < chosen.names.length(); i = i + 1 {
    positions[chosen.names[i]] = i
  }
  for i = 0; i < expected; i = i + 1 {
    assert_true(
      layout_cell(unique.storage, i, 0) is Some(Number(n)) &&
      n == (i + 1).to_double(),
    )
    assert_true(
      layout_cell(chosen.storage, i, positions.get("id").unwrap())
      is Some(Number(n)) &&
      n == (i + 1).to_double(),
    )
    assert_true(
      layout_cell(chosen.storage, i, positions.get("rank").unwrap())
      is Some(Number(n)) &&
      n == (i + 1).to_double(),
    )
    for j = 2; j < width; j = j + 1 {
      assert_true(
        layout_cell(
          chosen.storage,
          i,
          positions.get("p" + j.to_string()).unwrap(),
        )
        is Some(Number(n)) &&
        n == (i + 1 + j).to_double(),
      )
    }
  }
  for slot = 0; slot < store.tables.length(); slot = slot + 1 {
    if slot != 6 && slot != 9 {
      assert_true(store.tables[slot] is None)
    }
  }
  let observe_us = @bench.monotonic_clock_end(observe_clock)
  let total_us = @bench.monotonic_clock_end(total_clock)
  if profile {
    let phases = [fixture_us, prepare_us, import_us, execute_us, observe_us]
    println(
      "{\"kind\":\"layout-sample\",\"candidate\":\"" +
      (if candidate == ValueColumns { "B" } else { "C" }) +
      "\",\"rows\":" +
      count.to_string() +
      ",\"columns\":" +
      width.to_string() +
      ",\"same_keys\":" +
      same.to_string() +
      ",\"phases_us\":" +
      phases.to_json().stringify() +
      ",\"end_to_end_us\":" +
      total_us.to_string() +
      ",\"retained_slots\":" +
      store.workspace.live.to_string() +
      ",\"peak_retained_slots\":" +
      store.workspace.peak.to_string() +
      ",\"owned_buffer_slots\":" +
      ledger.slots.live.to_string() +
      ",\"peak_owned_buffer_slots\":" +
      ledger.slots.peak.to_string() +
      ",\"owned_typed_bytes\":" +
      ledger.bytes.live.to_string() +
      ",\"peak_owned_typed_bytes\":" +
      ledger.bytes.peak.to_string() +
      ",\"control_remaining\":" +
      control.remaining.to_string() +
      "}",
    )
  }
  // Cleanup is outside phase timings for both current harness continuations.
  // The complete experiment must separately include this in its enclosing E2E.
  clear_table_store(store)
  release_owned_layout_buffer(ledger, source).unwrap()
  assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
}

///|
test "legacy branches have independent closed form results in both column layouts" {
  for candidate in [ValueColumns, TypedColumns] {
    for same in [false, true] {
      sequence_scale(100, 2, same, candidate~)
      sequence_scale(100, 64, same, candidate~)
    }
  }
}
