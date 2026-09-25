///|
fn bounded_unnest_fixture(
  rows : String,
  large_items? : Bool = false,
  input_values? : ValueLimits = run_limits().input_values,
  max_rows? : Int = 10,
  max_work? : Int = 10000,
  max_entries? : Int = 100,
) -> (@bounded.Control, BoundedUnnestExecution, CompletedOutput) raise {
  let item_limit = if large_items { "256" } else { "2" }
  let source_owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"items\":{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"number\",\"nullable\":true},\"max_items\":" +
    item_limit +
    "}},\"rows\":" +
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
    input_cursor(
      "[{\"from\":\"seed\",\"unnest\":{\"column\":\"items\",\"as\":\"item\",\"with_index\":\"position\",\"outer\":true}}]",
    ),
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
    ["unnest_0"],
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
  let execution = start_bounded_unnest(
    control,
    generated,
    read,
    max_rows,
    input_values,
    run_limits().output_values,
    max_work,
    100,
    max_entries,
    10000,
  ).unwrap()
  (control, execution, source)
}

///|
fn long_unnest_items_rows(count : Int) -> String {
  "[{\"id\":1,\"items\":[" + Array::make(count, "1").join(",") + "]}]"
}

///|
test "bounded unnest stops inside its long input array" {
  let (control, execution, source) = bounded_unnest_fixture(
    long_unnest_items_rows(256),
    large_items=true,
    max_rows=256,
    max_work=1000,
  )
  let mut measuring = false
  for _ in 0..<30 {
    if !measuring {
      match advance_bounded_unnest(execution, 1).unwrap() {
        BoundedUnnestContinue(..) =>
          measuring = bounded_unnest_measuring_input(execution)
        _ => fail("long input completed before cancellation")
      }
    }
  }
  assert_true(measuring)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_unnest(execution, 1).unwrap() is BoundedUnnestStopped(_, ..),
  )
  assert_true(cleanup_bounded_unnest(execution).unwrap())
  assert_true(completed_output_available(source))
}

///|
test "bounded unnest preserves exact input array charges" {
  // One row, id, array, and eight items cost 11 nodes and 18 work.
  for
    (nodes, work, accepted) in [
      (11, 18, true),
      (10, 18, false),
      (11, 17, false),
    ] {
    let input_values : ValueLimits = {
      ..run_limits().input_values,
      max_nodes: nodes,
      max_text_bytes: 7,
      max_work: work,
    }
    let (_, execution, source) = bounded_unnest_fixture(
      long_unnest_items_rows(8),
      large_items=true,
      input_values~,
      max_rows=8,
      max_work=1000,
    )
    let mut terminal = false
    for _ in 0..<500 {
      if !terminal {
        match advance_bounded_unnest(execution, 1).unwrap() {
          BoundedUnnestContinue(..) => ()
          BoundedUnnestComplete(output, ..) => {
            assert_true(accepted)
            assert_eq(completed_row_count(output), 8)
            terminal = true
          }
          BoundedUnnestFailed(InputLimit, ..) => {
            assert_false(accepted)
            terminal = true
          }
          _ => fail("input array ended with another result")
        }
      }
    }
    assert_true(terminal)
    assert_true(cleanup_bounded_unnest(execution).unwrap())
    assert_true(completed_output_available(source))
  }
}

///|
test "bounded unnest retains item order and outer indexed rows" {
  let (_, execution, source) = bounded_unnest_fixture(
    "[{\"id\":1,\"items\":[2,null]},{\"id\":2,\"items\":[]},{\"id\":3,\"items\":null}]",
  )
  let mut completed : CompletedOutput? = None
  let mut previous_work = 0L
  for _ in 0..<200 {
    if completed is None {
      match advance_bounded_unnest(execution, 1).unwrap() {
        BoundedUnnestContinue(work=next, ..) => {
          assert_true(next - previous_work <= 1L)
          previous_work = next
        }
        BoundedUnnestComplete(output, work=next, ..) => {
          assert_true(next - previous_work <= 1L)
          completed = Some(output)
        }
        _ => fail("bounded unnest did not complete")
      }
    }
  }
  guard completed is Some(output) else { fail("bounded unnest did not finish") }
  assert_eq(completed_row_count(output), 4)
  assert_true(completed_cell(output, 0, 1) is Some(Number(2)))
  assert_true(completed_cell(output, 0, 3) is Some(Number(0)))
  assert_true(completed_cell(output, 1, 1) is Some(Null))
  assert_true(completed_cell(output, 1, 3) is Some(Number(1)))
  assert_true(completed_cell(output, 2, 0) is Some(Number(2)))
  assert_true(completed_cell(output, 2, 1) is Some(Null))
  assert_true(completed_cell(output, 2, 3) is Some(Null))
  assert_true(completed_cell(output, 3, 0) is Some(Number(3)))
  assert_true(completed_output_available(source))
  assert_true(cleanup_bounded_unnest(execution).unwrap())
  assert_true(completed_output_available(source))
}

///|
test "bounded unnest stops after output work without partial completion" {
  let (control, execution, source) = bounded_unnest_fixture(
    "[{\"id\":1,\"items\":[2,null]},{\"id\":2,\"items\":[3]}]",
  )
  let mut emitted = false
  for _ in 0..<100 {
    if !emitted {
      match advance_bounded_unnest(execution, 1).unwrap() {
        BoundedUnnestContinue(progress~, ..) =>
          if progress > 0L {
            emitted = true
          }
        _ => fail("unnest ended before cancellation")
      }
    }
  }
  assert_true(emitted)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_unnest(execution, 1).unwrap() is BoundedUnnestStopped(_, ..),
  )
  assert_true(cleanup_bounded_unnest(execution).unwrap())
  assert_true(completed_output_available(source))
}

///|
test "bounded unnest admits exact empty metadata and rejects one short" {
  // Two input names and ordinals (4) and four output columns (4) coexist.
  let (_, exact, _) = bounded_unnest_fixture("[]", max_rows=0, max_entries=8)
  let mut completed = false
  for _ in 0..<30 {
    if !completed {
      match advance_bounded_unnest(exact, 1).unwrap() {
        BoundedUnnestContinue(..) => ()
        BoundedUnnestComplete(output, ..) => {
          assert_eq(completed_row_count(output), 0)
          completed = true
        }
        _ => fail("exact unnest metadata was rejected")
      }
    }
  }
  assert_true(completed)
  assert_true(cleanup_bounded_unnest(exact).unwrap())
  let (_, short, _) = bounded_unnest_fixture("[]", max_rows=0, max_entries=7)
  let mut failed = false
  for _ in 0..<30 {
    if !failed {
      match advance_bounded_unnest(short, 1).unwrap() {
        BoundedUnnestContinue(..) => ()
        BoundedUnnestFailed(Rows(RowLimit), ..) => failed = true
        _ => fail("one-short unnest metadata was accepted")
      }
    }
  }
  assert_true(failed)
  assert_true(cleanup_bounded_unnest(short).unwrap())
}

///|
test "bounded unnest admits exact empty work and rejects one short" {
  // Input names cost 2 + 7 UTF-8 bytes and output names cost 19 bytes.
  let (_, exact, _) = bounded_unnest_fixture("[]", max_rows=0, max_work=28)
  let mut completed = false
  for _ in 0..<30 {
    if !completed {
      match advance_bounded_unnest(exact, 1).unwrap() {
        BoundedUnnestContinue(..) => ()
        BoundedUnnestComplete(_, ..) => completed = true
        _ => fail("exact unnest work was rejected")
      }
    }
  }
  assert_true(completed)
  assert_true(cleanup_bounded_unnest(exact).unwrap())
  let (_, short, _) = bounded_unnest_fixture("[]", max_rows=0, max_work=27)
  let mut failed = false
  for _ in 0..<30 {
    if !failed {
      match advance_bounded_unnest(short, 1).unwrap() {
        BoundedUnnestContinue(..) => ()
        BoundedUnnestFailed(Rows(RowLimit), ..) => failed = true
        _ => fail("one-short unnest work was accepted")
      }
    }
  }
  assert_true(failed)
  assert_true(cleanup_bounded_unnest(short).unwrap())
}

///|
test "bounded unnest admits exact nonempty work and workspace" {
  // Input and output names cost 28 control units and eight live slots.
  // One input row, two item occurrences, and eight output cells add
  // 1 + 2 + 8 control units. One four-cell row overlaps metadata.
  for
    (work, entries, success) in [
      (39, 12, true),
      (38, 12, false),
      (39, 11, false),
    ] {
    let (_, execution, source) = bounded_unnest_fixture(
      "[{\"id\":1,\"items\":[2,null]}]",
      max_rows=2,
      max_work=work,
      max_entries=entries,
    )
    let mut accepted = false
    let mut terminal = false
    for _ in 0..<100 {
      if !terminal {
        match advance_bounded_unnest(execution, 1).unwrap() {
          BoundedUnnestContinue(..) => ()
          BoundedUnnestComplete(output, ..) => {
            assert_eq(completed_row_count(output), 2)
            accepted = true
            terminal = true
          }
          BoundedUnnestFailed(Rows(RowLimit), ..) => terminal = true
          _ => fail("unexpected unnest resource result")
        }
      }
    }
    assert_true(terminal)
    assert_eq(accepted, success)
    assert_true(cleanup_bounded_unnest(execution).unwrap())
    assert_true(completed_output_available(source))
  }
}

///|
test "bounded unnest rejects output overflow incrementally" {
  let (_, execution, source) = bounded_unnest_fixture(
    "[{\"id\":1,\"items\":[2,null]}]",
    max_rows=1,
  )
  let mut failed = false
  for _ in 0..<100 {
    if !failed {
      match advance_bounded_unnest(execution, 1).unwrap() {
        BoundedUnnestContinue(..) => ()
        BoundedUnnestFailed(Rows(RowLimit), ..) => failed = true
        _ => fail("unnest output ceiling was not enforced")
      }
    }
  }
  assert_true(failed)
  assert_true(cleanup_bounded_unnest(execution).unwrap())
  assert_true(completed_output_available(source))
}
