///|
fn window_metadata_fixture(
  kind : Int,
  name : String,
  output? : String = "zzzz",
  work? : Int = 100000,
  entries? : Int = 10000,
  empty? : Bool = false,
) -> BoundedBindingRowsExecution raise {
  let contract = if kind == 0 {
    "{\"type\":\"object\",\"nullable\":true,\"fields\":{\"leaf\":{\"type\":\"number\",\"nullable\":false}}}"
  } else {
    "{\"type\":\"number\",\"nullable\":false}"
  }
  let rows = if empty {
    "[]"
  } else if kind == 0 {
    "[{\"id\":1,\"" +
    name +
    "\":{\"leaf\":7}},{\"id\":2,\"" +
    name +
    "\":null}]"
  } else {
    "[{\"id\":1,\"" +
    name +
    "\":100},{\"id\":2,\"" +
    name +
    "\":80},{\"id\":3,\"" +
    name +
    "\":95}]"
  }
  let source_owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"" +
    name +
    "\":" +
    contract +
    "},\"rows\":" +
    rows +
    "},\"as\":\"seed\"}" +
    (if kind == 2 {
      ",{\"from\":\"seed\",\"assert_rows\":{\"unique_by\":[\"id\"]},\"as\":\"keyed\"}]"
    } else {
      "]"
    }),
  )
  let source_step = if kind == 2 { 1 } else { 0 }
  let source_generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(source_owner),
    [],
    Array::makei(source_step + 1, index => {
      @lower.node_id(
        @lower.node_at(@lower.bound_preparation(source_owner), index).unwrap(),
      )
    }),
    100000,
    10000,
  ).unwrap()
  let source = completed_output(
    execute_generated_sequence(source_generated, [], compute_test_limits()).unwrap(),
    @pipeline.Step(source_step),
  ).unwrap()
  let operation = if kind == 0 {
    "\"json_pick\":{\"column\":\"" +
    name +
    "\",\"path\":[\"leaf\"],\"output\":\"" +
    output +
    "\"}"
  } else if kind == 1 {
    "\"watermark_rows\":{\"time\":\"" +
    name +
    "\",\"late_policy\":\"mark\",\"watermark_ms\":90}"
  } else {
    "\"lag\":{\"partition_by\":[],\"order_by\":[{\"" +
    name +
    "\":\"desc\"}],\"field\":\"" +
    name +
    "\",\"output\":\"" +
    output +
    "\",\"offset\":1}"
  }
  let receiver = bounded_binding_rows_receiver(
    source_owner,
    source_step~,
    metadata_operation=Some(order_metadata_operation(operation)),
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    [
      @lower.node_id(
        @lower.node_at(@lower.bound_preparation(receiver), 0).unwrap(),
      ),
    ],
    100000,
    10000,
  ).unwrap()
  let input = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, source_owner, source).unwrap(),
    100,
    10000,
  ).unwrap()
  start_bounded_binding_rows(
    @bounded.control(),
    generated,
    input,
    100,
    run_limits().input_values,
    run_limits().output_values,
    work,
    100,
    entries,
    10000,
  ).unwrap()
}

///|
test "generated row metadata is not materialized before bounded resume" {
  for kind in [0, 1, 2] {
    let execution = window_metadata_fixture(kind, "a".repeat(256))
    assert_eq(
      execution.state.input_names.length(),
      0,
      msg="generated-column kernels must prepare names inside resume",
    )
    assert_true(execution.state.output_names.is_empty())
    @bounded.request_cancel(execution.state.engine) |> ignore
    assert_true(
      advance_bounded_binding_rows(execution, 1).unwrap()
      is BoundedBindingRowsStopped(_, ..),
    )
    cleanup_bounded_binding_rows(execution).unwrap() |> ignore
    assert_eq(execution.state.workspace.live, 0)
    assert_true((execution.state.available)())
  }
}

///|
test "generated metadata preserves exact roles NULL and occurrence order across quanta" {
  let name = "a".repeat(128) + "😀é"
  let output_name = "z".repeat(128) + "😀é"
  for kind in [0, 1, 2] {
    let mut charges : (Int, Int)? = None
    for quantum in [1, 7, 256] {
      let execution = window_metadata_fixture(kind, name, output=output_name)
      let output = finish_order_metadata_fixture(execution, quantum)
      let rows = if kind == 0 { 2 } else { 3 }
      assert_eq(completed_row_count(output), rows)
      let names = Array::makei(completed_column_count(output), column => {
        completed_column_name(output, column).unwrap()
      })
      assert_eq(
        names,
        if kind == 1 {
          [name, "id", "watermark_decision", "watermark_late", "watermark_ms"]
        } else {
          [name, "id", output_name]
        },
      )
      for row in 0..<rows {
        assert_true(
          completed_cell(output, row, 1) is Some(Number(id)) &&
          id == (row + 1).to_double(),
        )
        if kind == 0 {
          assert_true(
            if row == 0 {
              completed_cell(output, row, 2) is Some(Number(7))
            } else {
              completed_cell(output, row, 2) is Some(Null)
            },
          )
        } else if kind == 1 {
          assert_true(
            completed_cell(output, row, 0) is Some(Number(time)) &&
            time == [100.0, 80.0, 95.0][row],
          )
          assert_true(
            completed_cell(output, row, 2) is Some(Text(decision)) &&
            decision == (if row == 1 { "mark" } else { "keep" }),
          )
          assert_true(
            completed_cell(output, row, 3) is Some(Boolean(late)) &&
            late == (row == 1),
          )
          assert_true(completed_cell(output, row, 4) is Some(Number(90)))
        } else {
          assert_true(
            if row == 0 {
              completed_cell(output, row, 2) is Some(Null)
            } else {
              completed_cell(output, row, 2) is Some(Number(value)) &&
              value == (if row == 1 { 95.0 } else { 100.0 })
            },
          )
        }
      }
      let actual = (
        execution.state.control.remaining,
        execution.state.workspace.peak,
      )
      match charges {
        None => charges = Some(actual)
        Some(expected) => assert_eq(actual, expected)
      }
      cleanup_bounded_binding_rows(execution).unwrap() |> ignore
      assert_eq(execution.state.workspace.live, 0)
      assert_true((execution.state.available)())
    }
  }
}

///|
test "generated output roles do not depend on being the final schema column" {
  let name = "z".repeat(256)
  for kind in [0, 2] {
    let execution = window_metadata_fixture(kind, name, output="a")
    let output = finish_order_metadata_fixture(execution, 1)
    assert_eq(
      Array::makei(completed_column_count(output), column => {
        completed_column_name(output, column).unwrap()
      }),
      ["a", "id", name],
    )
    assert_true(
      if kind == 0 {
        completed_cell(output, 0, 0) is Some(Number(7))
      } else {
        completed_cell(output, 0, 0) is Some(Null)
      },
    )
    cleanup_bounded_binding_rows(execution).unwrap() |> ignore
    assert_eq(execution.state.workspace.live, 0)
  }
}

///|
test "generated metadata stops inside role matching and source lookup before input charging" {
  for kind in [0, 1, 2] {
    for role_match in [false, true] {
      let execution = window_metadata_fixture(
        kind,
        "a".repeat(256),
        output="z".repeat(256),
      )
      let mut reached = false
      for _ in 0..<1000 {
        if !reached {
          assert_true(
            advance_bounded_binding_rows(execution, 1).unwrap()
            is BoundedBindingRowsContinue(..),
          )
          reached = if role_match {
            execution.state.phase is PrepareRowSources &&
            (if kind == 1 {
              execution.state.metadata_generated_field == 1
            } else {
              execution.state.metadata_generated_field == 0 &&
              execution.state.metadata_offset == 64
            })
          } else {
            execution.state.phase is PrepareOperationMetadata &&
            execution.state.metadata_lookup
            .map(cursor => cursor.offset == 64)
            .unwrap_or(false)
          }
        }
      }
      assert_true(reached)
      assert_eq(execution.state.input_values.nodes, 0)
      assert_eq(execution.state.control.remaining, 100000)
      @bounded.request_cancel(execution.state.engine) |> ignore
      assert_true(
        advance_bounded_binding_rows(execution, 1).unwrap()
        is BoundedBindingRowsStopped(_, ..),
      )
      cleanup_bounded_binding_rows(execution).unwrap() |> ignore
      assert_eq(execution.state.workspace.live, 0)
      assert_true(execution.state.metadata_lookup is None)
      assert_true(execution.state.metadata_source is None)
      assert_true(execution.state.row_sources.is_empty())
      assert_true((execution.state.available)())
      assert_true(execution.state.rows.val is None)
    }
  }
}

///|
test "generated source preparation admits independent exact and one-short temporary workspace" {
  // Path view 3 + input names 2 + output names 3 + input ordinals 2
  // + projection ordinals 3 + cached sources 3 + borrowed source role 1 = 17.
  // A lookup cursor adds one slot and is released before input charging.
  for (entries, success) in [(18, true), (17, false)] {
    let execution = window_metadata_fixture(0, "a".repeat(256), entries~)
    assert_eq(execution.state.workspace.live, 17)
    let mut ready = false
    let mut rejected = false
    for _ in 0..<1000 {
      if !ready && !rejected {
        match advance_bounded_binding_rows(execution, 1).unwrap() {
          BoundedBindingRowsContinue(..) =>
            ready = execution.state.phase is ChargeInput
          BoundedBindingRowsFailed(Rows(RowLimit), ..) => rejected = true
          _ => fail("unexpected generated metadata boundary outcome")
        }
      }
    }
    assert_eq(ready, success)
    assert_eq(rejected, !success)
    assert_eq(execution.state.input_values.nodes, 0)
    assert_eq(execution.state.control.remaining, 100000)
    @bounded.request_cancel(execution.state.engine) |> ignore
    if success {
      advance_bounded_binding_rows(execution, 1) |> ignore
    }
    cleanup_bounded_binding_rows(execution).unwrap() |> ignore
    assert_eq(execution.state.workspace.live, 0)
    assert_true((execution.state.available)())
  }
}

///|
test "generated JSON output preserves independently derived whole execution work limits" {
  // Two input openings and two output openings: 4. Non-take row copying
  // charges names, not another cell entry: id(2) + source(256) + output(256).
  // The non-NULL source probes leaf once: one visit plus four bytes = 5.
  // The NULL row has no leaf probe. Total: 4 + 2*514 + 5 = 1037.
  for quantum in [1, 7, 256] {
    for (work, success) in [(1037, true), (1036, false)] {
      let execution = window_metadata_fixture(
        0,
        "a".repeat(256),
        output="z".repeat(256),
        work~,
      )
      let mut complete = false
      let mut rejected = false
      for _ in 0..<12000 {
        if !complete && !rejected {
          match advance_bounded_binding_rows(execution, quantum).unwrap() {
            BoundedBindingRowsContinue(..) => ()
            BoundedBindingRowsComplete(output, ..) => {
              assert_true(completed_cell(output, 0, 2) is Some(Number(7)))
              assert_true(completed_cell(output, 1, 2) is Some(Null))
              complete = true
            }
            BoundedBindingRowsFailed(Rows(RowLimit), ..) => rejected = true
            _ => fail("unexpected generated JSON work outcome")
          }
        }
      }
      assert_eq((complete, rejected), (success, !success))
      cleanup_bounded_binding_rows(execution).unwrap() |> ignore
      assert_eq(execution.state.workspace.live, 0)
      assert_true((execution.state.available)())
    }
  }
}

///|
test "generated metadata terminates with empty input and no partial generated output" {
  for kind in [0, 1, 2] {
    let execution = window_metadata_fixture(kind, "a".repeat(256), empty=true)
    let output = finish_order_metadata_fixture(execution, 1)
    assert_eq(completed_row_count(output), 0)
    assert_true(execution.state.metadata_source is None)
    cleanup_bounded_binding_rows(execution).unwrap() |> ignore
    assert_eq(execution.state.workspace.live, 0)
    assert_true((execution.state.available)())
  }
}
