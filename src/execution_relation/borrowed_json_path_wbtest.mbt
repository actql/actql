///|
fn borrowed_json_path_fixture(
  count : Int,
  work? : Int = 10000,
  nonnull? : Bool = false,
  segment? : String = "step",
) -> BoundedBindingRowsExecution raise {
  let mut contract = "{\"type\":\"number\",\"nullable\":false}"
  let mut value = "7"
  for depth in 0..<count {
    contract = "{\"type\":\"object\",\"nullable\":" +
      (if depth == count - 1 { "true" } else { "false" }) +
      ",\"fields\":{\"" +
      segment +
      "\":" +
      contract +
      "}}"
    value = "{\"" + segment + "\":" + value + "}"
  }
  let source_owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"payload\":" +
    contract +
    "},\"rows\":[{\"payload\":" +
    (if nonnull { value } else { "null" }) +
    "}]},\"as\":\"seed\"}]",
  )
  let source_generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(source_owner),
    [],
    ["values_0"],
    100000,
    10000,
  ).unwrap()
  let source = completed_output(
    execute_generated_sequence(source_generated, [], compute_test_limits()).unwrap(),
    @pipeline.Step(0),
  ).unwrap()
  let path = Array::make(count, "\"" + segment + "\"").join(",")
  let receiver = bounded_binding_rows_receiver(
    source_owner,
    // The fixture deliberately admits a deep typed schema; these are test
    // preparation limits, not an installed Host policy change.
    metadata_max_depth=4000,
    metadata_operation=Some(
      order_metadata_operation(
        "\"json_pick\":{\"column\":\"payload\",\"path\":[" +
        path +
        "],\"output\":\"picked\"}",
      ),
    ),
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver, max_bindings=count + 2),
    [],
    [
      @lower.node_id(
        @lower.node_at(@lower.bound_preparation(receiver), 0).unwrap(),
      ),
    ],
    100000,
    10000,
  ).unwrap()
  let read = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, source_owner, source).unwrap(),
    100,
    10000,
  ).unwrap()
  start_bounded_binding_rows(
    @bounded.control(),
    generated,
    read,
    1,
    run_limits().input_values,
    run_limits().output_values,
    work,
    100,
    10000,
    10000,
  ).unwrap()
}

///|
test "borrowed JSON path preserves nullable demand and charges across quanta" {
  // NULL short-circuits the path without scanning its 128 admitted segments.
  // One input row open, one output row open and payload/picked spelling bytes:
  // 1 + 1 + 7 + 6 = 15. No non-NULL object field is probed.
  for quantum in [1, 7, 256] {
    let execution = borrowed_json_path_fixture(128, work=15)
    assert_eq(
      @lower.json_pick_path_count(execution.state.json_path.unwrap()),
      128,
    )
    let output = finish_order_metadata_fixture(execution, quantum)
    assert_eq(completed_row_count(output), 1)
    assert_eq(completed_column_count(output), 2)
    assert_eq(completed_column_name(output, 0), Some("payload"))
    assert_eq(completed_column_name(output, 1), Some("picked"))
    assert_true(completed_cell(output, 0, 0) is Some(Null))
    assert_true(completed_cell(output, 0, 1) is Some(Null))
    cleanup_bounded_binding_rows(execution).unwrap() |> ignore
    assert_eq(execution.state.workspace.live, 0)
    assert_true((execution.state.available)())
    let short = borrowed_json_path_fixture(128, work=14)
    let mut failed = false
    for _ in 0..<10000 {
      match advance_bounded_binding_rows(short, quantum).unwrap() {
        BoundedBindingRowsContinue(_, ..) => ()
        BoundedBindingRowsFailed(Rows(RowLimit), ..) => {
          failed = true
          break
        }
        _ => fail("expected the independent JSON work boundary")
      }
    }
    assert_true(failed)
    assert_true(short.state.rows.val is None)
    cleanup_bounded_binding_rows(short).unwrap() |> ignore
    assert_eq(short.state.workspace.live, 0)
    assert_true((short.state.available)())
  }
}

///|
test "borrowed JSON path observes stop without materializing the path" {
  let execution = borrowed_json_path_fixture(128)
  assert_eq(
    @lower.json_pick_path_count(execution.state.json_path.unwrap()),
    128,
  )
  @bounded.request_cancel(execution.state.engine) |> ignore
  assert_true(
    advance_bounded_binding_rows(execution, 1).unwrap()
    is BoundedBindingRowsStopped(_, ..),
  )
  assert_eq(execution.state.control.remaining, 10000)
  assert_true(execution.state.rows.val is None)
  cleanup_bounded_binding_rows(execution).unwrap() |> ignore
  cleanup_bounded_binding_rows(execution).unwrap() |> ignore
  assert_eq(execution.state.workspace.live, 0)
  assert_true((execution.state.available)())
}

///|
test "borrowed JSON path preserves Unicode probes and independent work limits" {
  let segment = "a".repeat(128) + "😀é"
  // Four field probes: four entries plus 4 * (128 + 4 + 2) UTF-8 bytes.
  // Input/output row opens and payload/picked bytes add 15: total 555.
  for quantum in [1, 7, 256] {
    let execution = borrowed_json_path_fixture(
      4,
      work=555,
      nonnull=true,
      segment~,
    )
    let output = finish_order_metadata_fixture(execution, quantum)
    assert_true(completed_cell(output, 0, 1) is Some(Number(7)))
    cleanup_bounded_binding_rows(execution).unwrap() |> ignore
    assert_eq(execution.state.workspace.live, 0)
    let short = borrowed_json_path_fixture(4, work=554, nonnull=true, segment~)
    let mut failed = false
    for _ in 0..<10000 {
      match advance_bounded_binding_rows(short, quantum).unwrap() {
        BoundedBindingRowsContinue(_, ..) => ()
        BoundedBindingRowsFailed(Rows(RowLimit), ..) => {
          failed = true
          break
        }
        _ => fail("expected the independent Unicode probe boundary")
      }
    }
    assert_true(failed)
    cleanup_bounded_binding_rows(short).unwrap() |> ignore
    assert_eq(short.state.workspace.live, 0)
    assert_true((short.state.available)())
  }
}

///|
test "borrowed JSON path stops inside a later Unicode segment" {
  let execution = borrowed_json_path_fixture(
    4,
    nonnull=true,
    segment="a".repeat(128) + "😀é",
  )
  let mut reached = false
  for _ in 0..<10000 {
    assert_true(
      advance_bounded_binding_rows(execution, 1).unwrap()
      is BoundedBindingRowsContinue(..),
    )
    if execution.state.phase is PickJson &&
      execution.state.json_segment == 2 &&
      execution.state.json_name_offset == 64 {
      reached = true
      break
    }
  }
  assert_true(reached)
  let remaining = execution.state.control.remaining
  assert_true(remaining < 10000)
  @bounded.request_cancel(execution.state.engine) |> ignore
  assert_true(
    advance_bounded_binding_rows(execution, 1).unwrap()
    is BoundedBindingRowsStopped(_, ..),
  )
  assert_eq(execution.state.control.remaining, remaining)
  assert_true(execution.state.rows.val is None)
  cleanup_bounded_binding_rows(execution).unwrap() |> ignore
  assert_eq(execution.state.workspace.live, 0)
  assert_true((execution.state.available)())
}
