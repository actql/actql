///|
fn bounded_row_window_fixture(
  rows : String,
  window? : String = "{\"kind\":\"sliding\",\"time\":\"at\",\"size\":10,\"step\":6,\"offset\":2}",
  max_rows? : Int = 10,
  max_work? : Int = 10000,
  max_entries? : Int = 100,
) -> (@bounded.Control, BoundedRowWindowExecution, CompletedOutput) raise {
  let source_owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"at\":{\"type\":\"number\",\"nullable\":false},\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":" +
    rows +
    "},\"as\":\"seed\"}]",
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
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(source_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor("[{\"from\":\"seed\",\"row_window\":" + window + "}]"),
    [("seed", @pipeline.ProducedInput(producer))],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let receiver = @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 100000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    ["window_0"],
    100000,
    10000,
  ).unwrap()
  let read = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, source_owner, source).unwrap(),
    100,
    10000,
  ).unwrap()
  let control = @bounded.control()
  let execution = start_bounded_row_window(
    control,
    generated,
    read,
    max_rows,
    run_limits().input_values,
    run_limits().output_values,
    max_work,
    100,
    max_entries,
    10000,
  ).unwrap()
  (control, execution, source)
}

///|
test "bounded row windows preserve ascending memberships at quantum one" {
  let (_, execution, source) = bounded_row_window_fixture(
    "[{\"at\":5,\"id\":1},{\"at\":7,\"id\":2}]",
  )
  let mut completed : CompletedOutput? = None
  let mut polls = 0
  let mut previous_work = 0L
  while completed is None && polls < 200 {
    polls += 1
    match advance_bounded_row_window(execution, 1).unwrap() {
      BoundedRowWindowContinue(work=next, ..) => {
        assert_true(next - previous_work <= 1L)
        previous_work = next
      }
      BoundedRowWindowComplete(output, work=next, ..) => {
        assert_true(next - previous_work <= 1L)
        completed = Some(output)
      }
      BoundedRowWindowFailed(_, ..) => fail("bounded row window failed")
      BoundedRowWindowStopped(_, ..) => fail("bounded row window stopped")
    }
  }
  guard completed is Some(output) else { fail("row window did not finish") }
  assert_eq(completed_row_count(output), 3)
  assert_true(completed_cell(output, 0, 2) is Some(Number(6)))
  assert_true(completed_cell(output, 0, 3) is Some(Number(-4)))
  assert_true(completed_cell(output, 1, 2) is Some(Number(12)))
  assert_true(completed_cell(output, 1, 3) is Some(Number(2)))
  assert_true(completed_cell(output, 2, 0) is Some(Number(7)))
  assert_true(completed_output_available(source))
  assert_true(cleanup_bounded_row_window(execution).unwrap())
  assert_true(completed_output_available(source))
}

///|
test "bounded row window cancellation stops before exposing partial rows" {
  let (control, execution, source) = bounded_row_window_fixture(
    "[{\"at\":5,\"id\":1}]",
    window="{\"kind\":\"sliding\",\"time\":\"at\",\"size\":100,\"step\":1}",
    max_rows=100,
    max_entries=200,
  )
  let mut emitted = false
  for _ in 0..<200 {
    if !emitted {
      match advance_bounded_row_window(execution, 1).unwrap() {
        BoundedRowWindowContinue(progress~, ..) =>
          if progress > 0L {
            emitted = true
          }
        _ => fail("row window ended before cancellation")
      }
    }
  }
  assert_true(emitted)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_row_window(execution, 1).unwrap()
    is BoundedRowWindowStopped(_, ..),
  )
  assert_true(cleanup_bounded_row_window(execution).unwrap())
  assert_true(completed_output_available(source))
}

///|
test "bounded row window rejects a one-short output ceiling incrementally" {
  let (_, execution, _) = bounded_row_window_fixture(
    "[{\"at\":5,\"id\":1}]",
    window="{\"kind\":\"sliding\",\"time\":\"at\",\"size\":10,\"step\":1}",
    max_rows=9,
  )
  let mut failed = false
  for _ in 0..<100 {
    if !failed {
      match advance_bounded_row_window(execution, 1).unwrap() {
        BoundedRowWindowContinue(..) => ()
        BoundedRowWindowFailed(Rows(RowLimit), ..) => failed = true
        _ => fail("one-short output ceiling was not enforced")
      }
    }
  }
  assert_true(failed)
  assert_true(cleanup_bounded_row_window(execution).unwrap())
}

///|
test "bounded row window admits exact live metadata and rejects one short" {
  // Two input names and ordinals, four output columns, two pending
  // memberships, and four cells in the output row overlap: 14 slots.
  let (_, admitted, _) = bounded_row_window_fixture(
    "[{\"at\":5,\"id\":1},{\"at\":7,\"id\":2}]",
    max_entries=14,
  )
  let mut done = false
  for _ in 0..<200 {
    if !done {
      match advance_bounded_row_window(admitted, 1).unwrap() {
        BoundedRowWindowContinue(..) => ()
        BoundedRowWindowComplete(output, ..) => {
          assert_eq(completed_row_count(output), 3)
          done = true
        }
        _ => fail("exact metadata budget rejected")
      }
    }
  }
  assert_true(done)
  assert_true(cleanup_bounded_row_window(admitted).unwrap())
  let (_, rejected, _) = bounded_row_window_fixture(
    "[{\"at\":5,\"id\":1},{\"at\":7,\"id\":2}]",
    max_entries=13,
  )
  let mut failed = false
  for _ in 0..<200 {
    if !failed {
      match advance_bounded_row_window(rejected, 1).unwrap() {
        BoundedRowWindowContinue(..) => ()
        BoundedRowWindowFailed(Rows(RowLimit), ..) => failed = true
        _ => fail("one-short metadata budget accepted")
      }
    }
  }
  assert_true(failed)
  assert_true(cleanup_bounded_row_window(rejected).unwrap())
}

///|
test "bounded row window admits exact control work and rejects one short" {
  // Input names cost 6; boundary names cost 22; output names cost 26.
  // One input row and its time read cost 2; two memberships cost 2;
  // two four-cell output rows cost 8: 66 total control units.
  let (_, admitted, _) = bounded_row_window_fixture(
    "[{\"at\":5,\"id\":1}]",
    max_work=66,
  )
  let mut done = false
  for _ in 0..<100 {
    if !done {
      match advance_bounded_row_window(admitted, 1).unwrap() {
        BoundedRowWindowContinue(..) => ()
        BoundedRowWindowComplete(output, ..) => {
          assert_eq(completed_row_count(output), 2)
          done = true
        }
        _ => fail("exact control-work budget rejected")
      }
    }
  }
  assert_true(done)
  assert_true(cleanup_bounded_row_window(admitted).unwrap())
  let (_, rejected, _) = bounded_row_window_fixture(
    "[{\"at\":5,\"id\":1}]",
    max_work=65,
  )
  let mut failed = false
  for _ in 0..<100 {
    if !failed {
      match advance_bounded_row_window(rejected, 1).unwrap() {
        BoundedRowWindowContinue(..) => ()
        BoundedRowWindowFailed(Rows(RowLimit), ..) => failed = true
        _ => fail("one-short control-work budget accepted")
      }
    }
  }
  assert_true(failed)
  assert_true(cleanup_bounded_row_window(rejected).unwrap())
}

///|
test "bounded row window preserves empty output and exact large boundaries" {
  let (_, empty, _) = bounded_row_window_fixture("[]", max_rows=0)
  let mut empty_done = false
  for _ in 0..<20 {
    if !empty_done {
      match advance_bounded_row_window(empty, 1).unwrap() {
        BoundedRowWindowContinue(..) => ()
        BoundedRowWindowComplete(output, ..) => {
          assert_eq(completed_row_count(output), 0)
          empty_done = true
        }
        _ => fail("empty row window failed")
      }
    }
  }
  assert_true(empty_done)
  assert_true(cleanup_bounded_row_window(empty).unwrap())
  let (_, large, _) = bounded_row_window_fixture(
    "[{\"at\":9007199254740991,\"id\":1}]",
    window="{\"kind\":\"fixed\",\"time\":\"at\",\"size\":9007199254740991}",
    max_rows=1,
  )
  let mut large_done = false
  for _ in 0..<50 {
    if !large_done {
      match advance_bounded_row_window(large, 1).unwrap() {
        BoundedRowWindowContinue(..) => ()
        BoundedRowWindowComplete(output, ..) => {
          assert_true(
            completed_cell(output, 0, 2) is Some(Number(18014398509481982.0)),
          )
          assert_true(
            completed_cell(output, 0, 3) is Some(Number(9007199254740991.0)),
          )
          large_done = true
        }
        _ => fail("representable large boundary failed")
      }
    }
  }
  assert_true(large_done)
  assert_true(cleanup_bounded_row_window(large).unwrap())
}
