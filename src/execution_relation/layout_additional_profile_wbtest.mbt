///|
priv enum ProfiledLayoutWorkload {
  SuppliedWorkload(NumericLayoutWorkload)
  ProducerWorkload
  LegacyWorkload(Int, Bool)
}

///|
fn additional_layout_case(
  index : Int,
) -> (String, ProfiledLayoutWorkload, Int, Int) raise {
  match index {
    0 => ("numeric-project-1000", SuppliedWorkload(NarrowProjection), 1000, 64)
    1 =>
      ("numeric-project-10000", SuppliedWorkload(NarrowProjection), 10000, 64)
    2 => ("nullable-1000", SuppliedWorkload(NullableProjection), 1000, 64)
    3 => ("nullable-10000", SuppliedWorkload(NullableProjection), 10000, 64)
    4 => ("numeric-full-add", SuppliedWorkload(FullWidthAddition), 10000, 64)
    5 => ("filter-low", SuppliedWorkload(LowSelectivity), 10000, 64)
    6 => ("filter-high", SuppliedWorkload(HighSelectivity), 10000, 64)
    7 => ("short-text", SuppliedWorkload(ShortText), 1000, 8)
    8 => ("long-text", SuppliedWorkload(LongText), 1000, 8)
    9 => ("decimal-temporal", SuppliedWorkload(DecimalTemporal), 1000, 8)
    10 => ("nested-small-result", SuppliedWorkload(NestedSmallResult), 1000, 8)
    11 => ("producer-branches", ProducerWorkload, 1000, 64)
    12 => ("zero-columns", SuppliedWorkload(ZeroColumns), 1000, 0)
    13 => ("conditional-frames", SuppliedWorkload(ConditionalFrames), 1000, 2)
    14 => ("ordered-frames", SuppliedWorkload(OrderedFrames), 1000, 2)
    15 => ("long-frames", SuppliedWorkload(LongFrames), 1000, 2)
    _ => fail("additional layout case not connected")
  }
}

///|
// Only scalars escape this scope. The enclosing invocation clock also includes
// clearing the output store and disposing of fixture, input and lease owners.
fn measure_additional_layout(
  workload : ProfiledLayoutWorkload,
  count : Int,
  candidate : LayoutCandidate,
  traffic? : LayoutTraffic? = None,
) -> (Array[Double], Array[Int]) raise {
  let phases = []
  let (generated, supplied, produced) = match workload {
    LegacyWorkload(width, same) => {
      let (generated, input) = legacy_layout_fixture(count, width, same, phases)
      (generated, [input], [])
    }
    SuppliedWorkload(shape) => {
      let (generated, input) = numeric_layout_fixture(
        shape,
        count,
        timings=Some(phases),
      )
      (generated, [input], [])
    }
    ProducerWorkload => {
      let (generated, bound) = layout_producer_case(count, timings=Some(phases))
      phases.push(0.0)
      (generated, [], [bound])
    }
  }
  let import_clock = @bench.monotonic_clock_start()
  let limits = numeric_layout_limits(count)
  let control = { remaining: 100000000, max_frames: 100, }
  if candidate == RowLayout {
    if traffic is Some(trace) {
      let invocation = prepare_traffic_rows(
        generated, supplied, produced, limits, control, trace,
      ).unwrap()
      run_traffic_rows(invocation, trace).unwrap()
      observe_additional_layout(invocation.store, workload, count)
      clear_table_store(invocation.store)
      assert_true(invocation.store.tables.all(t => t is None))
      // Diagnostic callers discard timing; do not emit fabricated phase clocks.
      return ([], [])
    }
    let invocation = prepare_sequence_invocation(
      generated.contracts,
      generated.sequence,
      supplied,
      generated.retained_ids,
      limits,
      control,
      produced~,
      fragments=Some(generated.contexts),
      ordered={ contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
    ).unwrap()
    phases[2] += @bench.monotonic_clock_end(import_clock)
    let execute_clock = @bench.monotonic_clock_start()
    let completed = run_sequence_invocation(invocation).unwrap()
    phases.push(@bench.monotonic_clock_end(execute_clock))
    let observe_clock = @bench.monotonic_clock_start()
    observe_additional_layout(test_row_store(completed), workload, count)
    phases.push(@bench.monotonic_clock_end(observe_clock))
    let counters = [
      test_row_store(completed).workspace.live,
      test_row_store(completed).workspace.peak,
      control.remaining,
      0,
      0,
    ]
    clear_table_store(test_row_store(completed))
    assert_true(test_row_store(completed).tables.all(t => t is None))
    return (phases, counters)
  }
  let ledger = { ..layout_ledger(100000000, 100000000, 100000000), traffic, }
  let physical = {
    ..layout_allocation(100000000, 100000000, 100000000),
    ledger: Some(ledger),
  }
  let source = match supplied.get(0) {
    Some(input) => Some(retain_layout_capture(input, ledger).unwrap())
    None => None
  }
  let producer_source = match produced.get(0) {
    Some(bound) =>
      Some(retain_layout_producer_output(bound.output, ledger).unwrap())
    None => None
  }
  let invocation = prepare_sequence_with_importers(
    generated.contracts,
    generated.sequence,
    supplied,
    generated.retained_ids,
    limits,
    control,
    fn(captured) {
      guard source is Some(root) else { return Err(InvalidRows) }
      if !physical_equal(captured, supplied[0]) {
        return Err(InvalidRows)
      }
      import_layout_capture_columns(root, candidate, physical)
    },
    fn(bound, id, output) {
      import_layout_producer(
        bound, id, candidate, limits, control, output, physical,
      )
    },
    release_table=fn(table : LayoutRelation) {
      release_layout_columns(table.storage)
    },
    produced~,
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
  observe_additional_layout(invocation.store, workload, count)
  phases.push(@bench.monotonic_clock_end(observe_clock))
  let counters = [
    invocation.store.workspace.live,
    invocation.store.workspace.peak,
    control.remaining,
    ledger.slots.peak,
    ledger.bytes.peak,
  ]
  clear_table_store(invocation.store)
  if source is Some(root) {
    release_owned_layout_buffer(ledger, root).unwrap()
  }
  if producer_source is Some(root) {
    release_owned_layout_buffer(ledger, root).unwrap()
  }
  assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
  return (phases, counters)
}

///|
fn[T : RelationRows] observe_additional_layout(
  store : TableStore[T],
  workload : ProfiledLayoutWorkload,
  count : Int,
) -> Unit raise {
  match workload {
    LegacyWorkload(width, same) =>
      verify_legacy_layout_store(store, width, same)
    SuppliedWorkload(shape) =>
      verify_numeric_layout_output(
        store.tables[store.tables.length() - 1].unwrap().table,
        shape,
        count,
      )
    ProducerWorkload =>
      verify_layout_producer_case(
        store.tables[1].unwrap().table,
        store.tables[2].unwrap().table,
        count,
      )
  }
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
