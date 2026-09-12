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
  import_clock : @bench.Timestamp,
  fixture_us : Double,
  prepare_us : Double,
  capture_us : Double,
) -> (Array[Double], Array[Int]) raise {
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
  let import_us = capture_us + @bench.monotonic_clock_end(import_clock)
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
  verify_legacy_layout_store(store, width, same)
  let observe_us = @bench.monotonic_clock_end(observe_clock)
  let counters = [
    store.workspace.live,
    store.workspace.peak,
    control.remaining,
    ledger.slots.live,
    ledger.slots.peak,
    ledger.bytes.live,
    ledger.bytes.peak,
  ]
  // The caller's enclosing clock stops after this function and its fixture-owning
  // parent return. No output handles escape, only phase/capacity measurements.
  clear_table_store(store)
  release_owned_layout_buffer(ledger, source).unwrap()
  assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
  ([fixture_us, prepare_us, import_us, execute_us, observe_us], counters)
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
