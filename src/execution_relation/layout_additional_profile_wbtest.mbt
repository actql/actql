///|
fn additional_layout_case(
  index : Int,
) -> (String, NumericLayoutWorkload, Int, Int) raise {
  match index {
    0 => ("numeric-project-1000", NarrowProjection, 1000, 64)
    1 => ("numeric-project-10000", NarrowProjection, 10000, 64)
    2 => ("nullable-1000", NullableProjection, 1000, 64)
    3 => ("nullable-10000", NullableProjection, 10000, 64)
    4 => ("numeric-full-add", FullWidthAddition, 10000, 64)
    5 => ("filter-low", LowSelectivity, 10000, 64)
    6 => ("filter-high", HighSelectivity, 10000, 64)
    7 => ("short-text", ShortText, 1000, 8)
    8 => ("long-text", LongText, 1000, 8)
    9 => ("decimal-temporal", DecimalTemporal, 1000, 8)
    10 => ("nested-small-result", NestedSmallResult, 1000, 8)
    12 => ("zero-columns", ZeroColumns, 1000, 0)
    _ => fail("additional layout case not connected")
  }
}

///|
// Only scalars escape this scope. The enclosing invocation clock also includes
// clearing the output store and disposing of fixture, input and lease owners.
fn measure_additional_layout(
  workload : NumericLayoutWorkload,
  count : Int,
  candidate : LayoutCandidate,
) -> (Array[Double], Array[Int]) raise {
  let phases = []
  let (generated, input) = numeric_layout_fixture(
    workload,
    count,
    timings=Some(phases),
  )
  let import_clock = @bench.monotonic_clock_start()
  let limits = numeric_layout_limits(count)
  let control = { remaining: 100000000, max_frames: 100, }
  let slot = @lower.sequence_count(generated.sequence)
  if candidate == RowLayout {
    let invocation = prepare_sequence_invocation(
      generated.contracts,
      generated.sequence,
      [input],
      generated.retained_ids,
      limits,
      control,
      produced=[],
      fragments=Some(generated.contexts),
      ordered={ contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
    ).unwrap()
    phases[2] += @bench.monotonic_clock_end(import_clock)
    let execute_clock = @bench.monotonic_clock_start()
    let completed = run_sequence_invocation(invocation).unwrap()
    phases.push(@bench.monotonic_clock_end(execute_clock))
    let observe_clock = @bench.monotonic_clock_start()
    verify_numeric_layout_output(
      completed.store.tables[slot].unwrap().table,
      workload,
      count,
    )
    phases.push(@bench.monotonic_clock_end(observe_clock))
    let counters = [
      completed.store.workspace.live,
      completed.store.workspace.peak,
      control.remaining,
      0,
      0,
    ]
    clear_table_store(completed.store)
    assert_true(completed.store.tables.all(t => t is None))
    return (phases, counters)
  }
  let ledger = layout_ledger(100000000, 100000000, 100000000)
  let physical = {
    ..layout_allocation(100000000, 100000000, 100000000),
    ledger: Some(ledger),
  }
  let source = retain_layout_capture(input, ledger).unwrap()
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
  phases[2] += @bench.monotonic_clock_end(import_clock)
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
  phases.push(@bench.monotonic_clock_end(execute_clock))
  let observe_clock = @bench.monotonic_clock_start()
  verify_numeric_layout_output(
    invocation.store.tables[slot].unwrap().table,
    workload,
    count,
  )
  phases.push(@bench.monotonic_clock_end(observe_clock))
  let counters = [
    invocation.store.workspace.live,
    invocation.store.workspace.peak,
    control.remaining,
    ledger.slots.peak,
    ledger.bytes.peak,
  ]
  clear_table_store(invocation.store)
  release_owned_layout_buffer(ledger, source).unwrap()
  assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
  return (phases, counters)
}

///|
fn profile_additional_layout(
  index : Int,
  candidate : LayoutCandidate,
  emit? : Bool = false,
) -> Unit raise {
  let (id, workload, count, width) = additional_layout_case(index)
  let clock = @bench.monotonic_clock_start()
  let (phases, counters) = measure_additional_layout(workload, count, candidate)
  let total = @bench.monotonic_clock_end(clock)
  assert_eq(phases.length(), 5)
  if emit {
    println(
      "{\"kind\":\"layout-sample\",\"case_id\":\"" +
      id +
      "\",\"candidate\":\"" +
      (match candidate {
        RowLayout => "A"
        ValueColumns => "B"
        TypedColumns => "C"
      }) +
      "\",\"rows\":" +
      count.to_string() +
      ",\"columns\":" +
      width.to_string() +
      ",\"same_keys\":false,\"disposal_included\":true,\"phases_us\":" +
      phases.to_json().stringify() +
      ",\"end_to_end_us\":" +
      total.to_string() +
      ",\"retained_slots\":" +
      counters[0].to_string() +
      ",\"peak_retained_slots\":" +
      counters[1].to_string() +
      ",\"control_remaining\":" +
      counters[2].to_string() +
      ",\"peak_owned_buffer_slots\":" +
      (if candidate == RowLayout { "null" } else { counters[3].to_string() }) +
      ",\"peak_owned_typed_bytes\":" +
      (if candidate == RowLayout { "null" } else { counters[4].to_string() }) +
      "}",
    )
  }
}
