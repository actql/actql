///|
// Supplementary construction diagnostics, never allocator-wide counts or a
// logical/physical budget. Disabled in timed samples. Cell transfers include
// NULL adoption (whose typed buffer was already initialized), not deep payload
// copies. Metadata, runtime allocation headers and scalar temporaries are outside
// these counters and must not be inferred from them.
priv struct LayoutTraffic {
  mut data_arrays : Int64
  mut validity_arrays : Int64
  mut validity_capacity : Int64
  mut column_cell_transfers : Int64
  mut selection_arrays : Int64
  mut selection_index_copies : Int64
  mut row_cell_transfers : Int64
  mut row_reference_copies : Int64
}

///|
fn layout_traffic() -> LayoutTraffic {
  {
    data_arrays: 0L,
    validity_arrays: 0L,
    validity_capacity: 0L,
    column_cell_transfers: 0L,
    selection_arrays: 0L,
    selection_index_copies: 0L,
    row_cell_transfers: 0L,
    row_reference_copies: 0L,
  }
}

///|
fn profile_layout_traffic(
  workload : ProfiledLayoutWorkload,
  count : Int,
  width : Int,
  same : Bool,
  candidate : LayoutCandidate,
) -> Unit raise {
  let traffic = layout_traffic()
  ignore(
    measure_additional_layout(workload, count, candidate, traffic=Some(traffic)),
  )
  println(
    "{\"kind\":\"layout-traffic\",\"candidate\":\"" +
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
    ",\"data_arrays\":" +
    traffic.data_arrays.to_string() +
    ",\"validity_arrays\":" +
    traffic.validity_arrays.to_string() +
    ",\"validity_capacity\":" +
    traffic.validity_capacity.to_string() +
    ",\"column_cell_transfers\":" +
    traffic.column_cell_transfers.to_string() +
    ",\"selection_arrays\":" +
    traffic.selection_arrays.to_string() +
    ",\"selection_index_copies\":" +
    traffic.selection_index_copies.to_string() +
    ",\"row_cell_transfers\":" +
    traffic.row_cell_transfers.to_string() +
    ",\"row_reference_copies\":" +
    traffic.row_reference_copies.to_string() +
    "}",
  )
}

///|
test "traffic row driver consumes the same checked sequence and observes both outputs" {
  let traffic = layout_traffic()
  ignore(
    measure_additional_layout(
      LegacyWorkload(2, false),
      100,
      RowLayout,
      traffic=Some(traffic),
    ),
  )
  assert_true(traffic.data_arrays > 0L)
  assert_true(traffic.row_cell_transfers > 0L)
  assert_true(traffic.row_reference_copies > 0L)
  assert_eq(traffic.column_cell_transfers, 0L)
  assert_eq(traffic.validity_arrays, 0L)
}

///|
// Count successful data-container construction by the existing row functions.
// Sort/take/distinct/dedupe copy row references, not every cell. These are source
// level array constructions, not malloc events or transient expression arrays.
fn traffic_row_result(
  result : Result[Table, RowIssue],
  materialized : Bool,
  traffic : LayoutTraffic,
) -> Result[Table, RowIssue] {
  if result is Ok(table) {
    traffic.data_arrays += 1L
    traffic.row_reference_copies += table.rows.length().to_int64()
    if materialized {
      traffic.data_arrays += table.rows.length().to_int64()
      for row in table.rows {
        traffic.row_cell_transfers += row.length().to_int64()
      }
    }
  }
  result
}

///|
fn prepare_traffic_rows(
  generated : GeneratedSequence,
  supplied : Array[CapturedRows],
  produced : Array[BoundProducerInput],
  limits : SequenceRunLimits,
  control : ControlBudget,
  traffic : LayoutTraffic,
) -> Result[SequenceInvocation[Table], SequenceRunIssue] {
  prepare_sequence_with_importers(
    generated.contracts,
    generated.sequence,
    supplied,
    generated.retained_ids,
    limits,
    control,
    fn(captured) {
      traffic_row_result(
        table_from_capture_bounded(captured, control, {
          limit: limits.operation_entries,
          live: 0,
          peak: 0,
        }),
        true,
        traffic,
      )
    },
    fn(bound, id, output_budget) {
      let source = test_row_output(bound.output)
      let adopted : Table = {
        owner: bound.receiver,
        id,
        names: source.names,
        rows: source.rows,
      }
      match bound.projection {
        None => Ok(adopted)
        Some(projection) =>
          traffic_row_result(
            evaluate_row_body(
              CheckedProjection(projection),
              adopted,
              id,
              limits.max_rows,
              control,
              output_budget,
              { limit: limits.operation_entries, live: 0, peak: 0, },
            ),
            true,
            traffic,
          )
      }
    },
    produced~,
    fragments=Some(generated.contexts),
    ordered={ contexts: [], max_bytes: 0, max_nodes: 0, max_depth: 0, },
  )
}

///|
fn run_traffic_rows(
  invocation : SequenceInvocation[Table],
  traffic : LayoutTraffic,
) -> Result[Unit, SequenceRunIssue] {
  let limits = invocation.limits
  let control = invocation.control
  let output = invocation.output_budget
  run_sequence_with_backend(
    invocation,
    fn(captured) {
      traffic_row_result(
        table_from_capture_bounded(captured, control, {
          limit: limits.operation_entries,
          live: 0,
          peak: 0,
        }),
        true,
        traffic,
      )
    },
    fn(kernel, input, logical) {
      let workspace = { limit: limits.operation_entries, live: 0, peak: 0, }
      evaluate_rows_dispatch(
        kernel,
        input,
        {
          release: fn(_) { () },
          sort: fn(k, table, id) {
            traffic_row_result(
              evaluate_sort_rows(
                k,
                table,
                id,
                limits.max_rows,
                control,
                output,
                workspace,
              ),
              false,
              traffic,
            )
          },
          dedupe: fn(k, table, id) {
            traffic_row_result(
              evaluate_dedupe_rows(
                k,
                table,
                id,
                limits.max_rows,
                control,
                output,
                workspace,
              ),
              false,
              traffic,
            )
          },
          distinct: fn(table, id) {
            traffic_row_result(
              evaluate_distinct_rows(
                table,
                id,
                limits.max_rows,
                control,
                output,
                workspace,
              ),
              false,
              traffic,
            )
          },
          take: fn(table, id, count, offset) {
            traffic_row_result(
              evaluate_take_rows(
                table,
                id,
                count,
                offset,
                limits.max_rows,
                control,
                output,
                workspace,
              ),
              false,
              traffic,
            )
          },
          body: fn(body, table, id, logical) {
            traffic_row_result(
              evaluate_row_body(
                body,
                table,
                id,
                limits.max_rows,
                control,
                output,
                workspace,
                ordered_budget=logical,
              ),
              true,
              traffic,
            )
          },
        },
        ordered_budget=logical,
      )
    },
  )
}

///|
test "row traffic preserves reference sharing instead of claiming cell copies" {
  let owner = row_owner("")
  let captured = capture_values(owner, 0, max_rows=2, run_limits().input_values).unwrap()
  let traffic = layout_traffic()
  let control = { remaining: 100000, max_frames: 100, }
  let input = traffic_row_result(
    table_from_capture_bounded(captured, control, {
      limit: 10000,
      live: 0,
      peak: 0,
    }),
    true,
    traffic,
  ).unwrap()
  assert_eq(traffic.data_arrays, 3L)
  assert_eq(traffic.row_cell_transfers, 4L)
  let selected = traffic_row_result(
    evaluate_take_rows(input, "taken", 1L, 0L, 2, control, row_output(), {
      limit: 10000,
      live: 0,
      peak: 0,
    }),
    false,
    traffic,
  ).unwrap()
  assert_true(physical_equal(selected.rows[0], input.rows[0]))
  assert_eq(traffic.data_arrays, 4L)
  assert_eq(traffic.row_cell_transfers, 4L)
  assert_eq(traffic.row_reference_copies, 3L)
}

///|
test "column traffic distinguishes construction, sharing and index copies" {
  let owner = row_owner("")
  let captured = capture_values(owner, 0, max_rows=2, run_limits().input_values).unwrap()
  for candidate in [ValueColumns, TypedColumns] {
    let traffic = layout_traffic()
    let ledger = { ..layout_ledger(100, 100, 10000), traffic: Some(traffic), }
    let budget = {
      ..layout_allocation(10000, 10000, 10000),
      ledger: Some(ledger),
    }
    let root = retain_layout_capture(captured, ledger).unwrap()
    // Registering existing source storage allocates no new data array.
    assert_eq(traffic.data_arrays, 0L)
    let table = import_layout_capture_columns(root, candidate, budget).unwrap()
    assert_eq(traffic.data_arrays, 2L)
    assert_eq(
      traffic.validity_arrays,
      if candidate == TypedColumns {
        2L
      } else {
        0L
      },
    )
    assert_eq(
      traffic.validity_capacity,
      if candidate == TypedColumns {
        4L
      } else {
        0L
      },
    )
    assert_eq(traffic.column_cell_transfers, 4L)
    let projection = project_layout(table.storage, [0], budget).unwrap()
    let selection = select_layout_rows(projection, [1, 0, 1], budget).unwrap()
    let composed = select_layout_rows(selection, [2, 0], budget).unwrap()
    assert_eq(traffic.data_arrays, 2L)
    assert_eq(traffic.column_cell_transfers, 4L)
    assert_eq(traffic.selection_arrays, 2L)
    assert_eq(traffic.selection_index_copies, 5L)
    release_layout_columns(composed)
    release_layout_columns(selection)
    release_layout_columns(projection)
    release_layout_columns(table.storage)
    release_owned_layout_buffer(ledger, root).unwrap()
    assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
    // Traffic is cumulative; cleanup cannot erase construction costs.
    assert_eq(traffic.data_arrays, 2L)
    assert_eq(traffic.column_cell_transfers, 4L)
  }
}

///|
test "rejected construction never fabricates buffer allocation traffic" {
  let captured = capture_values(
    row_owner(""),
    0,
    max_rows=2,
    run_limits().input_values,
  ).unwrap()
  let traffic = layout_traffic()
  let ledger = { ..layout_ledger(0, 0, 100), traffic: Some(traffic), }
  let budget = {
    ..layout_allocation(10000, 10000, 10000),
    ledger: Some(ledger),
  }
  assert_true(
    layout_column_builder(captured.schema, ["a", "b"], 2, TypedColumns, budget)
    is Err(RowLimit),
  )
  assert_eq(traffic.data_arrays, 0L)
  assert_eq(traffic.validity_arrays, 0L)
  assert_eq(traffic.column_cell_transfers, 0L)
}
