///|
// Prepared-input samples are separate processes from the enclosing E2E samples.
// The same imported buffers survive warmup and measurement; every invocation
// still passes common ownership, key and input-value admission with fresh budgets.
fn[T : RelationRows] repeat_prepared_layout(
  generated : GeneratedSequence,
  supplied : Array[CapturedRows],
  produced : Array[BoundProducerInput],
  workload : ProfiledLayoutWorkload,
  count : Int,
  attach : (LayoutLedger) -> Result[T, RowIssue],
  release : (T) -> Unit,
  execute : (SequenceInvocation[T], LayoutAllocation) -> Result[
    Unit,
    SequenceRunIssue,
  ],
) -> Array[Double] raise {
  let samples = []
  let usage = []
  assert_eq(supplied.length() + produced.length(), 1)
  // These fixed workloads need no receiving projection. Do not silently cache
  // away a projection's output charges if a future benchmark adds one.
  for bound in produced {
    assert_true(bound.projection is None)
  }
  for _repeat in 0..<2 {
    let limits = numeric_layout_limits(count)
    let control = { remaining: 100000000, max_frames: 100, }
    let ledger = layout_ledger(100000000, 100000000, 100000000)
    let physical = {
      ..layout_allocation(100000000, 100000000, 100000000),
      ledger: Some(ledger),
    }
    let source = supplied
      .get(0)
      .map(input => retain_layout_capture(input, ledger).unwrap())
    let producer = produced
      .get(0)
      .map(bound => retain_layout_producer_output(bound.output, ledger).unwrap())
    let invocation = prepare_sequence_with_importers(
      generated.contracts,
      generated.sequence,
      supplied,
      generated.retained_ids,
      limits,
      control,
      fn(captured) {
        guard supplied.get(0) is Some(expected) else { return Err(InvalidRows) }
        if !physical_equal(captured, expected) {
          return Err(InvalidRows)
        }
        attach(ledger)
      },
      fn(bound, id, _output) {
        guard produced.get(0) is Some(expected) else { return Err(InvalidRows) }
        if !physical_equal(bound, expected) || bound.projection is Some(_) {
          return Err(InvalidRows)
        }
        match attach(ledger) {
          Ok(table) => {
            if RelationRows::relation_id(table) != id ||
              !physical_equal(
                RelationRows::checked_owner(table),
                bound.receiver,
              ) {
              release(table)
              return Err(InvalidRows)
            }
            Ok(table)
          }
          Err(issue) => Err(issue)
        }
      },
      release_table=release,
      produced~,
      fragments=Some(generated.contexts),
      ordered={ contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
    ).unwrap()
    let clock = @bench.monotonic_clock_start()
    execute(invocation, physical).unwrap()
    samples.push(@bench.monotonic_clock_end(clock))
    observe_additional_layout(invocation.store, workload, count)
    usage.push(
      (
        control.remaining,
        invocation.input_budget.nodes,
        invocation.input_budget.work,
        invocation.output_budget.nodes,
        invocation.output_budget.work,
      ),
    )
    clear_table_store(invocation.store)
    if source is Some(root) {
      release_owned_layout_buffer(ledger, root).unwrap()
    }
    if producer is Some(root) {
      release_owned_layout_buffer(ledger, root).unwrap()
    }
    assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
  }
  assert_eq(usage[0], usage[1])
  samples
}

///|
fn profile_prepared_additional_layout(
  index : Int,
  candidate : LayoutCandidate,
) -> Unit raise {
  let (id, workload, count, width) = additional_layout_case(index)
  profile_prepared_layout(Some(id), workload, count, width, false, candidate)
}

///|
fn profile_prepared_layout(
  id : String?,
  workload : ProfiledLayoutWorkload,
  count : Int,
  width : Int,
  same : Bool,
  candidate : LayoutCandidate,
) -> Unit raise {
  let (generated, supplied, produced) = match workload {
    LegacyWorkload(width, same) => {
      let (generated, input) = legacy_layout_fixture(count, width, same, [])
      (generated, [input], [])
    }
    SuppliedWorkload(shape) => {
      let (generated, input) = numeric_layout_fixture(shape, count)
      (generated, [input], [])
    }
    ProducerWorkload => {
      let (generated, bound) = layout_producer_case(count)
      (generated, [], [bound])
    }
  }
  // Initial full admission provides an actual imported input, not fabricated
  // producer evidence. Its row buffer is also the A prepared-input baseline.
  let initial = prepare_sequence_invocation(
    generated.contracts,
    generated.sequence,
    supplied,
    generated.retained_ids,
    numeric_layout_limits(count),
    { remaining: 100000000, max_frames: 100, },
    produced~,
    fragments=Some(generated.contexts),
    ordered={ contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
  ).unwrap()
  let row_input = initial.store.tables[0].unwrap().table
  let times = if candidate == RowLayout {
    repeat_prepared_layout(
      generated,
      supplied,
      produced,
      workload,
      count,
      fn(_ledger) { Ok(row_input) },
      fn(_table) { () },
      fn(invocation, _physical) {
        match run_sequence_invocation(invocation) {
          Ok(_) => Ok(())
          Err(issue) => Err(issue)
        }
      },
    )
  } else {
    let ledger = layout_ledger(100000000, 100000000, 100000000)
    let physical = {
      ..layout_allocation(100000000, 100000000, 100000000),
      ledger: Some(ledger),
    }
    let source = supplied
      .get(0)
      .map(input => retain_layout_capture(input, ledger).unwrap())
    let producer_source = produced
      .get(0)
      .map(bound => retain_layout_producer_output(bound.output, ledger).unwrap())
    let imported = match source {
      Some(root) =>
        import_layout_capture_columns(root, candidate, physical).unwrap()
      None =>
        import_layout_producer(
          produced[0],
          row_input.id,
          candidate,
          numeric_layout_limits(count),
          { remaining: 100000000, max_frames: 100, },
          value_budget(numeric_layout_limits(count).output_values).unwrap(),
          physical,
        ).unwrap()
    }
    let snapshot = retain_layout_input_snapshot(imported, ledger).unwrap()
    release_layout_columns(imported.storage)
    let times = repeat_prepared_layout(
      generated,
      supplied,
      produced,
      workload,
      count,
      fn(run_ledger) { attach_layout_input_snapshot(snapshot, run_ledger) },
      fn(table) { release_layout_columns(table.storage) },
      fn(invocation, physical) {
        run_sequence_with_backend(
          invocation,
          fn(_captured) { Err(InvalidRows) },
          fn(kernel, table, logical) {
            evaluate_layout_kernel(
              kernel,
              table,
              count,
              invocation.control,
              invocation.output_budget,
              { limit: invocation.limits.operation_entries, live: 0, peak: 0, },
              physical,
              logical,
            )
          },
        )
      },
    )
    release_layout_input_snapshot(snapshot)
    if source is Some(root) {
      release_owned_layout_buffer(ledger, root).unwrap()
    }
    if producer_source is Some(root) {
      release_owned_layout_buffer(ledger, root).unwrap()
    }
    assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
    times
  }
  clear_table_store(initial.store)
  println(
    "{\"kind\":\"prepared-layout-sample\"" +
    (match id {
      Some(id) => ",\"case_id\":\"" + id + "\""
      None => ""
    }) +
    ",\"candidate\":\"" +
    (match candidate {
      RowLayout => "A"
      ValueColumns => "B"
      TypedColumns => "C"
    }) +
    "\",\"rows\":" +
    count.to_string() +
    ",\"columns\":" +
    width.to_string() +
    ",\"same_keys\":" +
    same.to_string() +
    ",\"reused_input\":true,\"fresh_budgets\":true,\"warmup_operation_us\":" +
    times[0].to_string() +
    ",\"operation_us\":" +
    times[1].to_string() +
    "}",
  )
}
